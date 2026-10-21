import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class HelperAccessTests: XCTestCase {
    @MainActor
    func testInstallWaitsForApprovalAndOpensLoginItems() async {
        let registration = Registration(.notRegistered)
        let access = HelperAccess(helper: PrivilegedHelper(registration: registration, transport: Hello(), teamID: "AB12CD34EF"))

        await access.refresh()
        XCTAssertEqual(access.state, .notInstalled)
        await access.install()
        XCTAssertEqual(access.state, .awaitingApproval)
        XCTAssertNil(access.problem)
        XCTAssertEqual(registration.settingsOpened, 1)

        registration.approve()
        await access.refresh()
        XCTAssertEqual(access.state, .ready)
        await access.remove()
        XCTAssertEqual(access.state, .notInstalled)
    }

    @MainActor
    func testAnUnsignedBuildExplainsWhyItCannotInstall() async {
        let registration = Registration(.notRegistered)
        let access = HelperAccess(helper: PrivilegedHelper(registration: registration, transport: Hello(), teamID: nil))

        await access.install()
        XCTAssertEqual(access.state, .needsSignedBuild)
        XCTAssertEqual(access.problem, "This build is not signed with a Developer ID, so macOS will not run the helper.")
        XCTAssertEqual(registration.settingsOpened, 0)
        XCTAssertEqual(registration.status(), .notRegistered, "nothing was registered")
    }
}

private final class Registration: HelperRegistering, @unchecked Sendable {
    private let lock = NSLock()
    private var current: HelperRegistrationStatus
    private var opened = 0

    init(_ status: HelperRegistrationStatus) { current = status }

    var settingsOpened: Int { lock.withLock { opened } }

    /// The person approves the helper in Login Items.
    func approve() { lock.withLock { current = .enabled } }

    func status() -> HelperRegistrationStatus { lock.withLock { current } }

    func register() throws { lock.withLock { current = .requiresApproval } }

    func unregister() async throws { lock.withLock { current = .notRegistered } }

    func openApprovalSettings() { lock.withLock { opened += 1 } }
}

private struct Hello: HelperTransport {
    func exchange(_ message: Data) async throws -> Data { await HelperRequestHandler().reply(to: message) }
}
