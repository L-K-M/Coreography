import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class HelperSpindumpTests: XCTestCase {
    private static let team = "AB12CD34EF"
    private static let target = HelperProcessIdentity(pid: 300, startSeconds: 5, startMicroseconds: 7)

    func testTheHandlerRunsTheAllowlistedToolForTheNamedProcess() async throws {
        let runs = Runs()
        let handler = HelperRequestHandler(runSpindump: { process, seconds in
            await runs.record(process, seconds)
            return .success("report for \(process.pid)@\(process.startSeconds) over \(seconds)s")
        })

        let reply = try await Self.reply(handler, .spindump(process: Self.target, seconds: 3))
        XCTAssertEqual(reply, .spindumpReport("report for 300@5 over 3s"))
        var asked = await runs.all
        XCTAssertEqual(asked.map(\.process), [Self.target], "exactly the process the app named, once")

        let refused: [HelperRequest] = [
            .spindump(process: HelperProcessIdentity(pid: 0, startSeconds: 5, startMicroseconds: 7), seconds: 3),
            .spindump(process: HelperProcessIdentity(pid: -4, startSeconds: 5, startMicroseconds: 7), seconds: 3),
            .spindump(process: Self.target, seconds: HelperWire.spindumpSeconds.lowerBound - 1),
            .spindump(process: Self.target, seconds: HelperWire.spindumpSeconds.upperBound + 1)
        ]
        for request in refused {
            guard case .refused = try await Self.reply(handler, request) else {
                return XCTFail("a refusal was expected for \(request)")
            }
        }
        asked = await runs.all
        XCTAssertEqual(asked.count, 1, "a refused request never reaches the tool")
    }

    func testAToolFailureReachesTheAppAsTheReason() async throws {
        let cases: [(ProcessSampleError, String)] = [
            (.failed("spindump: unable to gather"), "spindump: unable to gather"),
            (.exited, "The process exited before it could be read."),
            (.unsupportedPlatform, "spindump needs macOS.")
        ]
        for (error, reason) in cases {
            let handler = HelperRequestHandler(runSpindump: { _, _ in .failure(error) })
            let reply = try await Self.reply(handler, .spindump(process: Self.target, seconds: 3))
            XCTAssertEqual(reply, .spindumpFailed(reason))
        }
    }

    func testAReportTooLargeIsCutToFitAndMarked() async throws {
        // Whole-system stacks run to many megabytes; the reply still has to fit.
        let report = String(repeating: "line\n", count: HelperReply.maximumBytes)
        let handler = HelperRequestHandler(runSpindump: { _, _ in .success(report) })

        let message = await handler.reply(to: HelperWire.encode(HelperRequest.spindump(process: Self.target, seconds: 3)))
        XCTAssertLessThanOrEqual(message.count, HelperReply.maximumBytes)
        guard case .spindumpReport(let kept) = try HelperWire.decode(HelperReply.self, from: message) else {
            return XCTFail("a report was expected")
        }
        XCTAssertTrue(kept.hasPrefix("line"), "the head is kept: the target sorts topmost")
        XCTAssertTrue(kept.hasSuffix("[The output was cut to fit the helper's reply.]"))
    }

    func testAReportWithinTheLimitArrivesUncut() async throws {
        let handler = HelperRequestHandler(runSpindump: { _, _ in .success("short report") })
        let reply = try await Self.reply(handler, .spindump(process: Self.target, seconds: 3))
        XCTAssertEqual(reply, .spindumpReport("short report"))
    }

    func testSpindumpWaitsLongerThanARead() {
        XCTAssertEqual(HelperRequest.spindump(process: Self.target, seconds: 30).replyTimeout, 90)
        XCTAssertEqual(HelperRequest.hello.replyTimeout, 10)
        XCTAssertEqual(HelperRequest.processCounters(pids: [1]).replyTimeout, 10)
    }

    func testInvalidDurationsNeverReachTheTransport() async {
        let transport = SpindumpTransport()
        let helper = PrivilegedHelper(registration: Enabled(), transport: transport, teamID: Self.team)
        for seconds in [Int.min, 0, Int(HelperWire.spindumpSeconds.upperBound) + 1, Int.max] {
            let result = await helper.spindump(Self.target, seconds: seconds)
            guard case .failure = result else { return XCTFail("invalid duration must fail before exchange") }
        }
        let count = await transport.count
        XCTAssertEqual(count, 0)
        XCTAssertLessThanOrEqual(HelperRequest.spindump(process: Self.target, seconds: .max).replyTimeout, 90)
    }

    func testReportReadIsBoundedBeforeEncoding() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("spindump-test-\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: path) }
        try Data(repeating: 0x61, count: HelperReply.maximumBytes + 1).write(to: path)
        let text = try ProcessSpindumpDriver.readReport(at: path)
        XCTAssertTrue(text.hasPrefix("aaa"))
        XCTAssertTrue(text.hasSuffix("[The report was cut to fit the helper's reply.]"))
        XCTAssertLessThan(text.utf8.count, HelperReply.maximumBytes)
    }

    func testTheHelperMapsTheReplyAndStaysQuietForAWrongKind() async throws {
        let transport = SpindumpTransport()
        let helper = PrivilegedHelper(registration: Enabled(), transport: transport, teamID: Self.team)

        let report = await helper.spindump(Self.target, seconds: 3)
        guard case .success(let text) = report else { return XCTFail("a report was expected, got \(String(describing: report))") }
        XCTAssertEqual(text, "the report")

        let failed = await helper.spindump(Self.target, seconds: 3)
        XCTAssertEqual(failed, .failure(ProcessSampleFailure(reason: "the reason")))

        // A broken answer stops further requests for the quiet minute.
        let wrong = await helper.spindump(Self.target, seconds: 3)
        XCTAssertNil(wrong)
        let quiet = await helper.spindump(Self.target, seconds: 3)
        XCTAssertNil(quiet)
        let asked = await transport.count
        XCTAssertEqual(asked, 3, "the fourth request never left the app")
    }

    func testSpindumpWithoutAHelperAnswersNil() async {
        let helper = PrivilegedHelper(registration: NotInstalled(), transport: SpindumpTransport(), teamID: Self.team)
        let answer = await helper.spindump(Self.target, seconds: 3)
        XCTAssertNil(answer)
    }

    func testTheSpindumperWrapsTheReportWithItsTool() async throws {
        let reading = try Self.reading(pid: 300)
        let withoutHelper = await ProcessSpindumper(helper: nil).spindump(reading)
        XCTAssertNil(withoutHelper)

        let helper = PrivilegedHelper(registration: Enabled(), transport: SpindumpTransport(), teamID: Self.team)
        let report = await ProcessSpindumper(helper: helper).spindump(reading)
        guard case .success(let captured) = report else { return XCTFail("a report was expected") }
        XCTAssertEqual(captured.tool, .spindump)
        XCTAssertEqual(captured.name, "P300")
        XCTAssertEqual(captured.seconds, ProcessSpindumper.defaultSeconds)
        XCTAssertEqual(captured.text, "the report")
    }

    private static func reply(_ handler: HelperRequestHandler, _ request: HelperRequest) async throws -> HelperReply {
        try HelperWire.decode(HelperReply.self, from: await handler.reply(to: HelperWire.encode(request)))
    }

    private static func reading(pid: Int32) throws -> ProcessReading {
        ProcessReading(
            id: try ProcessIdentity(pid: pid, startSeconds: 5, startMicroseconds: 7), parentPID: 1, uid: 502,
            name: "P\(pid)", stamp: SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date()),
            cpuPercentOfMachine: try .measured(0), memoryFootprintBytes: try .measured(1),
            diskReadBytesPerSecond: try .measured(0), diskWriteBytesPerSecond: try .measured(0),
            executablePath: nil, responsiblePID: nil
        )
    }
}

private actor Runs {
    private(set) var all: [(process: HelperProcessIdentity, seconds: Int32)] = []
    func record(_ process: HelperProcessIdentity, _ seconds: Int32) { all.append((process, seconds)) }
}

/// Answers a report, a failure, then a wrong kind on consecutive requests.
private actor SpindumpTransport: HelperTransport {
    private(set) var count = 0

    func exchange(_ message: Data) async throws -> Data {
        count += 1
        let request = try HelperWire.decode(HelperRequest.self, from: message)
        guard case .spindump = request else { return HelperWire.encode(HelperReply.refused("unexpected")) }
        switch count {
        case 1: return HelperWire.encode(HelperReply.spindumpReport("the report"))
        case 2: return HelperWire.encode(HelperReply.spindumpFailed("the reason"))
        default: return HelperWire.encode(HelperReply.actionDone)
        }
    }
}

private struct Enabled: HelperRegistering {
    func status() -> HelperRegistrationStatus { .enabled }
    func register() throws {}
    func unregister() async throws {}
    func openApprovalSettings() {}
}

private struct NotInstalled: HelperRegistering {
    func status() -> HelperRegistrationStatus { .notRegistered }
    func register() throws {}
    func unregister() async throws {}
    func openApprovalSettings() {}
}
