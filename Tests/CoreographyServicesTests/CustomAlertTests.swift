import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class CustomAlertTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// Plan: "CPU above 90% for 10 s, clear below 70% for 30 s".
    func testACustomRuleRaisesAndClearsAcrossItsHysteresisBand() {
        let rule = CustomAlertRule(
            metric: .cpu, direction: .above, threshold: 90, clearThreshold: 70, raiseAfter: 10, clearAfter: 30, notifies: false
        )
        XCTAssertEqual(rule.title, "CPU above 90 % for 10 s")
        var engine = AlertEngine(rules: [rule.alertRule])
        func step(_ second: TimeInterval, _ cpu: Double?) -> [AlertEvent.Kind] {
            engine.evaluate(AlertInputs(readings: cpu.map { [.cpu: $0] } ?? [:]), at: epoch.addingTimeInterval(second)).map(\.kind)
        }
        XCTAssertEqual(step(0, 95), [])
        XCTAssertEqual(step(5, 85), [], "a dip below the threshold restarts the raise wait")
        XCTAssertEqual(step(6, 95), [])
        XCTAssertEqual(step(15, 95), [])
        XCTAssertEqual(step(16, 95), [.raised])
        engine = AlertEngine(rules: [rule.alertRule])
        XCTAssertEqual(step(0, 95), [])
        XCTAssertEqual(step(10, 95), [.raised])
        XCTAssertEqual(step(11, 80), [], "inside the band the alert holds")
        XCTAssertEqual(step(60, 70), [], "the clear threshold itself still holds")
        XCTAssertEqual(step(61, 60), [])
        XCTAssertEqual(step(80, nil), [], "a missing reading counts toward clearing, not raising")
        XCTAssertEqual(step(81, 60), [])
        XCTAssertEqual(step(111, 60), [.cleared])
        XCTAssertEqual(step(112, 85), [], "below the raise threshold nothing starts")
    }

    /// A sampler that stops must not hold a rule raised on its last value.
    func testARaisedRuleClearsWhenItsReadingsStop() {
        let rule = CustomAlertRule(
            metric: .gpuBusy, direction: .above, threshold: 90, clearThreshold: 70, raiseAfter: 0, clearAfter: 30, notifies: false
        )
        var engine = AlertEngine(rules: [rule.alertRule])
        XCTAssertEqual(engine.evaluate(AlertInputs(readings: [.gpuBusy: 95]), at: epoch).map(\.kind), [.raised])
        XCTAssertEqual(engine.evaluate(AlertInputs(), at: epoch.addingTimeInterval(1)).map(\.kind), [])
        XCTAssertEqual(engine.evaluate(AlertInputs(), at: epoch.addingTimeInterval(31)).map(\.kind), [.cleared])
        XCTAssertEqual(engine.evaluate(AlertInputs(), at: epoch.addingTimeInterval(60)).map(\.kind), [], "and nothing raises it again")
    }

    func testABelowRuleMirrorsTheBand() {
        let rule = CustomAlertRule(
            metric: .batteryCharge, direction: .below, threshold: 20, clearThreshold: 30, raiseAfter: 0, clearAfter: 0, notifies: true
        )
        var engine = AlertEngine(rules: [rule.alertRule])
        XCTAssertEqual(engine.evaluate(AlertInputs(readings: [.batteryCharge: 19]), at: epoch).map(\.kind), [.raised])
        XCTAssertEqual(engine.evaluate(AlertInputs(readings: [.batteryCharge: 25]), at: epoch.addingTimeInterval(1)).map(\.kind), [])
        XCTAssertEqual(engine.evaluate(AlertInputs(readings: [.batteryCharge: 31]), at: epoch.addingTimeInterval(2)).map(\.kind), [.cleared])
        XCTAssertEqual(rule.alertRule.lane, .power)
    }

    func testEditsAreNormalizedIntoAWorkableRule() {
        let wrongSide = CustomAlertRule(
            metric: .cpu, direction: .above, threshold: 50, clearThreshold: 80, raiseAfter: -5, clearAfter: 1e9, notifies: false
        ).normalized()
        XCTAssertEqual(wrongSide?.clearThreshold, 50, "an above rule clears at or under its threshold")
        XCTAssertEqual(wrongSide?.raiseAfter, 0)
        XCTAssertEqual(wrongSide?.clearAfter, CustomAlertRule.maximumSeconds)

        let below = CustomAlertRule(
            metric: .hottestCelsius, direction: .below, threshold: 40, clearThreshold: 30, raiseAfter: 5, clearAfter: 5, notifies: false
        ).normalized()
        XCTAssertEqual(below?.clearThreshold, 40)

        let broken = CustomAlertRule(
            metric: .cpu, direction: .above, threshold: .nan, clearThreshold: 70, raiseAfter: 5, clearAfter: 5, notifies: false
        )
        XCTAssertNil(broken.normalized(), "a rule without a threshold is dropped, not turned into one that always fires")
        let unbounded = CustomAlertRule(
            metric: .cpu, direction: .above, threshold: 80, clearThreshold: .infinity, raiseAfter: .nan, clearAfter: 5, notifies: false
        ).normalized()
        XCTAssertEqual(unbounded?.clearThreshold, 80)
        XCTAssertEqual(unbounded?.raiseAfter, 0)
    }

    func testRulesPersistDedupedAndSurviveBadData() throws {
        let suite = "CustomAlertTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CustomAlertRules(defaults: defaults)
        XCTAssertEqual(store.all, [])

        let rule = CustomAlertRule.starter
        store.save([rule, rule])
        XCTAssertEqual(store.all, [rule], "one id is one rule")

        defaults.set(Data("not json".utf8), forKey: CustomAlertRules.defaultsKey)
        XCTAssertEqual(store.all, [], "unreadable rules are dropped, not fatal")

        store.save(Array(repeating: (), count: CustomAlertRules.maximumCount + 3).map { _ in CustomAlertRule.starter })
        XCTAssertEqual(store.all.count, CustomAlertRules.maximumCount)
    }

    func testReadingsSkipStaleAndMissingSamples() {
        let samples = [
            HistorySample(metric: .cpu, time: epoch, value: 42, availability: .measured),
            HistorySample(metric: .gpuBusy, time: epoch.addingTimeInterval(-60), value: 99, availability: .measured),
            HistorySample(metric: .hottestCelsius, time: epoch, value: nil, availability: .gap),
            HistorySample(metric: .memoryApp, time: epoch, value: 1, availability: .measured),
            HistorySample(metric: .memoryUsed, time: epoch, value: 8e9, availability: .measured)
        ]
        XCTAssertEqual(AlertReadings.latest(samples, now: epoch), [.cpu: 42, .memoryUsed: 8e9],
                       "stale and missing readings are left out, and a memory layer is not a metric rules watch")
    }

    func testActiveTitlesShareALane() {
        let first = CustomAlertRule(metric: .cpu, direction: .above, threshold: 90, clearThreshold: 70, raiseAfter: 0, clearAfter: 0, notifies: false)
        let second = CustomAlertRule(metric: .cpu, direction: .above, threshold: 50, clearThreshold: 40, raiseAfter: 0, clearAfter: 0, notifies: false)
        let rules = [first.alertRule, second.alertRule] + AlertRules.shipped
        let titles = AlertRules.activeTitles(rules, active: [first.alertRule.id, second.alertRule.id, "memory-critical"])
        XCTAssertEqual(titles[.cpu], "CPU above 90 % for 0 s · CPU above 50 % for 0 s")
        XCTAssertEqual(titles[.memory], "Critical memory pressure")
        XCTAssertNil(titles[.disk])
    }

    func testReplacingRulesKeepsOnlyUnchangedState() {
        let kept = CustomAlertRule(metric: .cpu, direction: .above, threshold: 90, clearThreshold: 70, raiseAfter: 0, clearAfter: 0, notifies: false)
        let edited = CustomAlertRule(metric: .gpuBusy, direction: .above, threshold: 90, clearThreshold: 70, raiseAfter: 0, clearAfter: 0, notifies: false)
        var engine = AlertEngine(rules: [kept.alertRule, edited.alertRule])
        _ = engine.evaluate(AlertInputs(readings: [.cpu: 95, .gpuBusy: 95]), at: epoch)
        XCTAssertEqual(engine.activeRuleIDs.count, 2)

        var changed = edited
        changed.threshold = 99
        engine = engine.replacingRules([kept.alertRule, changed.alertRule], keeping: [kept.alertRule.id])
        XCTAssertEqual(engine.activeRuleIDs, [kept.alertRule.id], "an edited rule starts over")
    }
}
