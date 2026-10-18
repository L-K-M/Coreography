import Foundation
import XCTest
@testable import CoreographyDrivers
@testable import CoreographyKit

final class ProcessInspectorTests: XCTestCase {
    func testArgumentBlockYieldsArgumentsButNeverTheEnvironment() {
        var block = withUnsafeBytes(of: Int32(2)) { Array($0) }
        block += Array("/usr/bin/tool".utf8) + [0, 0, 0, 0]
        block += Array("tool".utf8) + [0] + Array("--token=abc".utf8) + [0]
        block += Array("SECRET=hunter2".utf8) + [0]
        XCTAssertEqual(ProcessArguments.parse(block), ["tool", "--token=abc"])

        XCTAssertNil(ProcessArguments.parse([1, 0]), "shorter than argc")
        let truncated = withUnsafeBytes(of: Int32(3)) { Array($0) } + Array("/x".utf8) + [0, 0] + Array("x".utf8) + [0]
        XCTAssertNil(ProcessArguments.parse(truncated), "fewer arguments than argc is malformed")
    }

    func testDetailNamesWhyArgumentsAreMissingAndWhoSigned() async throws {
        let mine = try process(pid: 10, path: "/Applications/Tool.app/Contents/MacOS/Tool")
        let detail = await ProcessInspector(driver: Details()).detail(of: mine)
        XCTAssertEqual(detail.arguments, ["Tool", "-v"])
        XCTAssertNil(detail.argumentsProblem)
        XCTAssertEqual(detail.signing, ProcessSigning(signer: .developer(team: "ABCDE12345"), identifier: "com.example.tool"))

        let theirs = await ProcessInspector(driver: Details()).detail(of: try process(pid: 11, path: nil))
        XCTAssertNil(theirs.arguments)
        XCTAssertEqual(theirs.argumentsProblem, "Another user's process; its arguments need the helper")
        XCTAssertNil(theirs.signing, "no path, no signature to read")
    }

    private func process(pid: Int32, path: String?) throws -> ProcessReading {
        ProcessReading(
            id: try ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1, uid: 501, name: "Tool",
            stamp: SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date()),
            cpuPercentOfMachine: try .measured(0), memoryFootprintBytes: try .measured(1),
            diskReadBytesPerSecond: try .measured(0), diskWriteBytesPerSecond: try .measured(0),
            executablePath: path, responsiblePID: nil
        )
    }
}

private struct Details: ProcessDetailReading {
    func arguments(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) async -> Result<[String], ProcessDetailError> {
        pid == 10 ? .success(["Tool", "-v"]) : .failure(.notPermitted)
    }

    func signing(path: String) async -> CodeSigning {
        CodeSigning(signature: .otherSigner, identifier: "com.example.tool", teamID: "ABCDE12345")
    }
}
