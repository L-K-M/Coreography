import Foundation
import Observation
import CoreographyKit

/// Settings' view of the optional privileged helper: its state, and
/// installing or removing it on request, never at launch (plan: offer it
/// at the moment of need).
@MainActor
@Observable
public final class HelperAccess {
    /// Nil until the first refresh.
    public private(set) var state: HelperState?
    /// Why the last install or removal failed.
    public private(set) var problem: String?
    public private(set) var isBusy = false

    @ObservationIgnored private let helper: PrivilegedHelper

    public convenience init() { self.init(helper: PrivilegedHelper()) }

    init(helper: PrivilegedHelper) { self.helper = helper }

    public func refresh() async { state = await helper.state() }

    /// Registers the helper, then opens Login Items when macOS waits for approval.
    public func install() async {
        await run { () async throws(HelperFailure) in try await self.helper.install() }
        if state == .awaitingApproval { await helper.openApprovalSettings() }
    }

    public func remove() async { await run { () async throws(HelperFailure) in try await self.helper.remove() } }

    public func openApprovalSettings() async { await helper.openApprovalSettings() }

    private func run(_ change: @escaping () async throws(HelperFailure) -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        problem = nil
        do {
            try await change()
        } catch {
            problem = Self.message(error)
        }
        await refresh()
    }

    private static func message(_ failure: HelperFailure) -> String {
        switch failure {
        case .needsSignedBuild: "This build is not signed with a Developer ID, so macOS will not run the helper."
        case .system(let detail): detail
        }
    }
}
