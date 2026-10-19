import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class ScopedAppTests: XCTestCase {
    private let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date(timeIntervalSince1970: 1_700_000_000))

    /// Plan: a scoped app's memory and GPU are labelled readings with its rank kept visible.
    func testAScopedAppReadsItsFootprintAndGPUTimeWithItsRank() throws {
        let processes = try snapshot([
            (100, "Safari", "/Applications/Safari.app/Contents/MacOS/Safari", nil, 1_000, 5),
            (101, "Safari Helper", "/Applications/Safari.app/Contents/XPCServices/Helper.app/Contents/MacOS/Helper", 100, 3_000, 10),
            (200, "mds", nil, nil, 9_000, 0),
            (300, "kernel_task", nil, nil, nil, nil)
        ])
        let safari = ScopedApp.readings(of: "Safari", in: processes)
        let memory = try XCTUnwrap(safari[.memory])
        XCTAssertEqual(memory.value.numericValue, 4_000, "the app's processes summed")
        XCTAssertEqual(memory.rank, 2)
        XCTAssertEqual(memory.rankedApps, 2, "an unreadable footprint is not ranked")
        let gpu = try XCTUnwrap(safari[.gpu])
        XCTAssertEqual(gpu.value.numericValue, 15)
        XCTAssertEqual(gpu.rank, 1)
        XCTAssertEqual(gpu.rankedApps, 1)

        let idle = try XCTUnwrap(ScopedApp.readings(of: "mds", in: processes)[.gpu])
        XCTAssertEqual(idle.value.numericValue, 0)
        XCTAssertNil(idle.rank, "no GPU time is no rank, not last place")
        let leader = try XCTUnwrap(ScopedApp.readings(of: "mds", in: processes)[.memory])
        XCTAssertEqual(leader.rank, 1, "the largest footprint leads")
        XCTAssertEqual(leader.rankedApps, 2)

        let restricted = try XCTUnwrap(ScopedApp.readings(of: "kernel_task", in: processes)[.memory])
        XCTAssertNil(restricted.value.numericValue)
        XCTAssertEqual(restricted.value.reason, "EPERM")
        XCTAssertNil(restricted.rank)

        XCTAssertEqual(ScopedApp.readings(of: "Mail", in: processes), [:], "an app not observed has no reading, not zero")
    }

    private func snapshot(_ rows: [(Int32, String, String?, Int32?, Double?, Double?)]) throws -> CapturedProcesses {
        let source = MetricSource(provider: "processes", driver: "libproc")
        let processes = try rows.map { pid, name, path, responsible, footprint, gpu in
            ProcessReading(
                id: try ProcessIdentity(pid: pid, startSeconds: UInt64(pid), startMicroseconds: 0), parentPID: 1, uid: 501,
                name: name, stamp: stamp, cpuPercentOfMachine: try .measured(0, source: source),
                memoryFootprintBytes: try footprint.map { try .measured($0, source: source) } ?? .restricted(reason: "EPERM", source: source),
                diskReadBytesPerSecond: try .measured(0, source: source), diskWriteBytesPerSecond: try .measured(0, source: source),
                gpuMillisecondsPerSecond: try gpu.map { try .measured($0, source: source) } ?? .restricted(reason: "EPERM", source: source),
                executablePath: path, responsiblePID: responsible
            )
        }
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(Double(processes.count)), enumerationTruncated: false,
            processes: processes, issues: [], continuity: .continuous
        )
    }
}
