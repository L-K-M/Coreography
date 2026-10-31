import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class DashboardNavigationTests: XCTestCase {
    func testEveryDestinationHasARoundTrippingWidgetLink() {
        for section in DashboardSection.allCases {
            XCTAssertEqual(AutomationLink.command(from: section.url), .success(.navigate(section)))
        }
        XCTAssertEqual(AutomationLink.command(from: URL(string: "coreography://show/MEMORY")!), .success(.navigate(.memory)))
        XCTAssertEqual(AutomationLink.command(from: URL(string: "coreography://show/missing")!),
                       .failure(.invalidArgument("Unknown section \"missing\"")))
        XCTAssertEqual(AutomationLink.command(from: URL(string: "coreography://show/cpu/quit")!),
                       .failure(.unknownCommand("show/cpu/quit")))
    }

    @MainActor
    func testNavigationPreservesTheInvestigationAndTimelineLayout() throws {
        let model = try makeModel()
        XCTAssertEqual(model.section, .overview)
        let savedLayout = model.laneLayout
        defer { model.laneLayout = savedLayout }
        model.laneLayout = .standard
        model.laneLayout.set(.cpu, .hidden)
        model.laneLayout.set(.memory, .compact)
        model.laneLayout.move(.network, .up)
        model.toggleDetail(.power)
        let layout = model.laneLayout
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        model.timeRange = .hour
        model.cursorTime = start
        model.selection = start...start.addingTimeInterval(10)
        model.scopedApp = "Fixture"
        model.processFilter = "mem:>1GB"
        model.toggleDisplayHold()

        for section in DashboardSection.allCases {
            model.navigate(to: section)
            XCTAssertEqual(model.section, section)
            XCTAssertEqual(model.timeRange, .hour)
            XCTAssertEqual(model.cursorTime, start)
            XCTAssertEqual(model.selection, start...start.addingTimeInterval(10))
            XCTAssertEqual(model.scopedApp, "Fixture")
            XCTAssertEqual(model.processFilter, "mem:>1GB")
            XCTAssertEqual(model.displayMode, .held)
            XCTAssertEqual(model.laneLayout, layout)
            XCTAssertEqual(model.expandedLanes, [.power], "Resource details do not overwrite Timeline expansion")
            for lane in section.lanes { XCTAssertTrue(model.showsLaneDetail(lane)) }
        }
        XCTAssertEqual(DashboardSection.cpu.lanes, [.cpu], "A hidden Timeline lane still has a resource page")
        XCTAssertEqual(DashboardSection.power.lanes, [.power, .thermal])
        XCTAssertFalse(model.showsLaneDetail(.cpu), "Timeline keeps its own expansion")
    }

    @MainActor
    func testResourceDetailActionsDoNotChangeTimelineExpansion() throws {
        let model = try makeModel()
        for section in DashboardSection.allCases where !section.lanes.isEmpty {
            model.navigate(to: section)
            for lane in section.lanes {
                model.toggleDetail(lane)
                XCTAssertTrue(model.showsLaneDetail(lane))
                XCTAssertTrue(model.expandedLanes.isEmpty, "Resource pages do not change Timeline preferences")
            }
        }
        model.navigate(to: .timeline)
        model.toggleDetail(.cpu)
        XCTAssertEqual(model.expandedLanes, [.cpu])
    }

    @MainActor
    func testLegacyPaneCommandsRevealTheirSidebarDestination() async throws {
        let model = try makeModel()
        let destinations: [(DetailPane, DashboardSection)] = [
            (.processes, .processes), (.connections, .network), (.startup, .startup),
            (.sensors, .power), (.sessions, .recordings)
        ]
        for (pane, section) in destinations {
            await model.run(.pane(pane))
            XCTAssertEqual(model.section, section)
            XCTAssertEqual(model.detailPane, pane)
        }
        for section in DashboardSection.allCases {
            XCTAssertTrue(model.paletteEntries.contains { $0.action == .section(section) })
            await model.run(.section(section))
            XCTAssertEqual(model.section, section)
        }
        await model.run(.filter("Fixture"))
        XCTAssertEqual(model.section, .processes)
    }

    @MainActor
    func testAutomationNavigatesToVisibleContent() async throws {
        let model = try makeModel()
        for section in DashboardSection.allCases {
            _ = await model.open(section.url)
            XCTAssertEqual(model.section, section)
        }
        _ = await model.perform(.show)
        XCTAssertEqual(model.section, .overview)
        _ = await model.perform(.filter("port:443"))
        XCTAssertEqual(model.section, .processes)
        _ = await model.perform(.range(.hour))
        XCTAssertEqual(model.section, .timeline)
        model.navigate(to: .network)
        XCTAssertEqual(model.detailPane, .connections)
        model.navigate(to: .overview)
        XCTAssertEqual(model.detailPane, .processes, "Leaving Network releases its on-demand pane")
    }

    @MainActor
    private func makeModel() throws -> DashboardModel {
        DashboardModel(monitor: try SystemMonitor(driver: UnusedHost()), interval: .seconds(1))
    }
}

private struct UnusedHost: HostSampleReading {
    func read() async -> RawHostSnapshot {
        preconditionFailure("Navigation must not start collection")
    }
}
