import Foundation
import XCTest
@testable import CoreographyDrivers

final class BoundedCommandRunnerTests: XCTestCase {
    private let runner = BoundedCommandRunner()

    func testReturnsOutputAndExitStatus() async throws {
        let output = try await runner.run(URL(fileURLWithPath: "/bin/echo"), arguments: ["hello"], timeout: .seconds(5), keepBytes: 1024)
        XCTAssertEqual(String(decoding: output.data, as: UTF8.self), "hello\n")
        XCTAssertFalse(output.truncated || output.timedOut)
        XCTAssertEqual(output.exitStatus, 0)
    }

    func testRuntimeCapStopsTheChildAndKeepsTheNewestBytes() async throws {
        let started = ContinuousClock.now
        let output = try await runner.run(URL(fileURLWithPath: "/usr/bin/yes"), arguments: ["line"], timeout: .milliseconds(300), keepBytes: 64)
        XCTAssertTrue(output.timedOut)
        XCTAssertTrue(output.truncated)
        XCTAssertEqual(output.data.count, 64)
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(5))
    }

    /// The sleep import relies on a failing child coming back as output, not a thrown error.
    func testANonZeroExitIsReportedNotThrown() async throws {
        let output = try await runner.run(URL(fileURLWithPath: "/usr/bin/false"), arguments: [], timeout: .seconds(5), keepBytes: 16)
        XCTAssertNotEqual(output.exitStatus, 0)
        XCTAssertFalse(output.timedOut)
    }

    func testMissingExecutableFailsToLaunch() async {
        do {
            _ = try await runner.run(URL(fileURLWithPath: "/nonexistent/tool"), arguments: [], timeout: .seconds(1), keepBytes: 16)
            XCTFail("expected a launch failure")
        } catch {
            guard case .launchFailed = error as? CommandRunnerError else { return XCTFail("\(error)") }
        }
    }
}
