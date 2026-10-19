import Foundation
import XCTest
import CoreographyDrivers
@testable import CoreographyKit

final class OpenFileMonitorTests: XCTestCase {
    func testReadsOpenFilesPerProcessAndCountsWhatItCannotRead() async throws {
        let snapshot = await OpenFileMonitor(driver: Files()).sample(try processes([0, 10, 11, 12, 13]))
        XCTAssertNil(snapshot.unavailableReason)
        XCTAssertEqual(snapshot.files.values.flatMap { $0 }, ["/Users/me/Notes.txt"])
        XCTAssertEqual(snapshot.restrictedProcesses, 1)
        XCTAssertEqual(snapshot.truncatedProcesses, 1)
        XCTAssertEqual(snapshot.failedProcesses, 0)

        let unsupported = await OpenFileMonitor(driver: NoFiles()).sample(try processes([10]))
        XCTAssertEqual(unsupported.unavailableReason, "Open files need macOS")
    }

    func testTheInspectorsListSaysWhenItIsCut() async throws {
        let rows = try processes([10, 13]).processes
        let complete = await OpenFileMonitor(driver: Files()).files(of: rows[0])
        XCTAssertEqual(complete?.paths, ["/Users/me/Notes.txt"])
        XCTAssertEqual(complete?.isComplete, true)
        let cut = await OpenFileMonitor(driver: Files()).files(of: rows[1])
        XCTAssertEqual(cut?.isComplete, false, "a process holding more files than one read keeps is marked incomplete")
    }

    private func processes(_ pids: [Int32]) throws -> ProcessSnapshot {
        let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date())
        let rows = try pids.map { pid in
            ProcessReading(
                id: try ProcessIdentity(pid: pid, startSeconds: 1, startMicroseconds: 0), parentPID: 1, uid: 501,
                name: "P\(pid)", stamp: stamp, cpuPercentOfMachine: try .measured(0), memoryFootprintBytes: try .measured(1),
                diskReadBytesPerSecond: try .measured(0), diskWriteBytesPerSecond: try .measured(0),
                executablePath: nil, responsiblePID: nil
            )
        }
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(Double(rows.count)), enumerationTruncated: false,
            processes: rows, issues: [], continuity: .continuous
        )
    }
}

/// 10 has a file, 11 belongs to another user, 12 exited, 13 holds too many.
private struct Files: ProcessFileReading {
    func files(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) async -> Result<RawProcessFiles, DescriptorReadError> {
        switch pid {
        case 0: XCTFail("the kernel is never read"); return .failure(.notPermitted)
        case 10: return .success(RawProcessFiles(paths: ["/Users/me/Notes.txt"], truncated: false))
        case 11: return .failure(.notPermitted)
        case 12: return .failure(.exited)
        default: return .success(RawProcessFiles(paths: [], truncated: true))
        }
    }
}

private struct NoFiles: ProcessFileReading {
    func files(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) async -> Result<RawProcessFiles, DescriptorReadError> {
        .failure(.unsupportedPlatform)
    }
}
