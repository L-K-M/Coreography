import Foundation
import Observation
import CoreographyKit

/// Measures where the startup volume's space goes. Walking a home folder
/// reads hundreds of thousands of files, so a survey starts only when the
/// person looks; once started it finishes even if the lens closes, as it
/// does when a macOS privacy prompt takes the focus.
@MainActor
@Observable
public final class SpaceSurveyor {
    /// Remembers that the person let macOS ask, so later surveys include
    /// the protected folders without asking again here.
    public nonisolated static let accessKey = "spaceAccess"
    /// A survey this recent is shown as is; older ones walk again on open.
    public nonisolated static let freshness: TimeInterval = 10 * 60

    public private(set) var sizes: [CapturedSpaceArea: CapturedSpaceSize] = [:]
    public private(set) var measuring: CapturedSpaceArea?
    public private(set) var measuredAt: Date?
    public var isMeasuring: Bool { task != nil }

    @ObservationIgnored private let survey: SpaceSurvey?
    @ObservationIgnored private let defaults: UserDefaults
    private var task: Task<Void, Never>?

    public convenience init() { self.init(survey: SpaceSurvey(), defaults: .standard) }

    /// A nil survey never measures: tests and platforms without a home.
    init(survey: SpaceSurvey?, defaults: UserDefaults) {
        self.survey = survey
        self.defaults = defaults
    }

    public var access: CapturedSpaceAccess {
        defaults.string(forKey: Self.accessKey).flatMap(SpaceAccess.init(rawValue:)) ?? .withoutPrompts
    }

    /// Areas the current access leaves out.
    public var unmeasured: [CapturedSpaceArea] {
        guard access == .withoutPrompts else { return [] }
        return SpaceSurvey.order.filter(\.asksMacOS)
    }

    public func braid(for volume: CapturedVolume) -> SpaceBraid {
        SpaceBraid(volume: volume, sizes: sizes, unmeasured: unmeasured, measuring: measuring)
    }

    /// Walks again when the last survey is missing or stale.
    public func refreshIfStale(now: Date = Date()) {
        if let measuredAt, now.timeIntervalSince(measuredAt) < Self.freshness { return }
        measure()
    }

    /// Walks every area the access allows; widening the access is
    /// remembered. Sizes from the last survey stay until each is replaced.
    public func measure(_ widened: CapturedSpaceAccess? = nil) {
        guard let survey else { return }
        if let widened { defaults.set(widened.rawValue, forKey: Self.accessKey) }
        guard task == nil || widened != nil else { return }
        task?.cancel()

        let areas = SpaceSurvey.order.filter { access == .askingMacOS || !$0.asksMacOS }
        task = Task { [weak self] in
            for area in areas {
                guard !Task.isCancelled else { return }
                self?.measuring = area
                let size = await survey.measure(area)
                guard !Task.isCancelled, let self else { return }
                self.sizes[area] = size
            }
            guard let self else { return }
            self.measuring = nil
            self.measuredAt = Date()
            self.task = nil
        }
    }
}
