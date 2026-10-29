import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit
@testable import CoreographyServices

final class BackgroundModeTests: XCTestCase {
    @MainActor
    func testRunningInTheBackgroundStartsAtLoginAndIsRemembered() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let registration = Registration()
        let mode = BackgroundMode(loginItem: LoginItem(registration: registration), defaults: defaults)
        XCTAssertEqual(mode.presence, .window, "the window is the default")
        XCTAssertEqual(mode.loginStart, .off)

        await mode.set(.background)
        XCTAssertEqual(mode.loginStart, .on)
        XCTAssertNil(mode.problem)
        await mode.set(.background)
        XCTAssertEqual(registration.registrations, 1, "registering twice does nothing the second time")

        let relaunched = BackgroundMode(loginItem: LoginItem(registration: registration), defaults: defaults)
        XCTAssertEqual(relaunched.presence, .background)

        await relaunched.set(.window)
        XCTAssertEqual(relaunched.loginStart, .off)
        await relaunched.set(.window)
        XCTAssertEqual(registration.removals, 1, "macOS is not asked to remove what it never registered")
    }

    @MainActor
    func testARefusedLoginItemKeepsTheMenuBarModeAndSaysWhy() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let registration = Registration(refusing: true)
        let mode = BackgroundMode(loginItem: LoginItem(registration: registration), defaults: defaults)

        await mode.set(.background)
        XCTAssertEqual(mode.presence, .background)
        XCTAssertEqual(mode.loginStart, .off)
        XCTAssertEqual(mode.problem, "macOS would not start Coreography at login: refused")
    }

    @MainActor
    func testALoginItemTurnedOffInSystemSettingsShowsOnRefresh() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let registration = Registration()
        let mode = BackgroundMode(loginItem: LoginItem(registration: registration), defaults: defaults)
        await mode.set(.background)

        registration.current = .requiresApproval
        mode.refresh()
        XCTAssertEqual(mode.loginStart, .awaitingApproval)
        mode.openLoginItems()
        XCTAssertEqual(registration.settingsOpened, 1)
    }
}

private struct Refusal: LocalizedError {
    var errorDescription: String? { "refused" }
}

private final class Registration: LoginItemRegistering, @unchecked Sendable {
    private let lock = NSLock()
    private let refusing: Bool
    private var state: LoginItemStatus = .notRegistered
    private var counts = (registrations: 0, removals: 0, settingsOpened: 0)

    init(refusing: Bool = false) { self.refusing = refusing }

    var current: LoginItemStatus {
        get { lock.withLock { state } }
        set { lock.withLock { state = newValue } }
    }

    var registrations: Int { lock.withLock { counts.registrations } }
    var removals: Int { lock.withLock { counts.removals } }
    var settingsOpened: Int { lock.withLock { counts.settingsOpened } }

    func status() -> LoginItemStatus { current }

    func register() throws {
        if refusing { throw Refusal() }
        lock.withLock {
            counts.registrations += 1
            state = .enabled
        }
    }

    func unregister() async throws {
        lock.withLock {
            counts.removals += 1
            state = .notRegistered
        }
    }

    func openSettings() { lock.withLock { counts.settingsOpened += 1 } }
}
