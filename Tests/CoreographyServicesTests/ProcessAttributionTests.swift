import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class ProcessAttributionTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// Plan: an unattributed share where system and process accounting are
    /// compatible and additive. The host CPU over the process interval,
    /// less what readable processes used.
    func testCPUOutsideReadableProcessesIsTheHostShareOverTheProcessInterval() throws {
        let processes = try snapshot(at: 10, cpu: [20, 5, nil])
        let host = try [(8.0, 99.0), (9.0, 30.0), (10.0, 40.0), (11.0, 99.0)].map {
            (time: epoch.addingTimeInterval($0.0), cpu: try MetricReading.measured($0.1))
        }
        XCTAssertEqual(
            ProcessAttribution.unattributedCPU(host: host, processes: processes, interval: 2), 10,
            "host 30 % and 40 % over (8 s, 10 s] average 35 %; readable processes used 25 %"
        )
        let shifted = [(time: epoch.addingTimeInterval(10), cpu: try MetricReading.measured(20))]
        XCTAssertEqual(ProcessAttribution.unattributedCPU(host: shifted, processes: processes, interval: 2), 0,
                       "sampling skew never makes the remainder negative")

        let unread = [(time: epoch.addingTimeInterval(10), cpu: MetricReading.gap(reason: "Sleep"))]
        XCTAssertNil(ProcessAttribution.unattributedCPU(host: unread, processes: processes, interval: 2))
        XCTAssertNil(ProcessAttribution.unattributedCPU(host: [], processes: processes, interval: 2))
        let interrupted = try snapshot(at: 10, cpu: [20], continuity: .interrupted)
        XCTAssertNil(ProcessAttribution.unattributedCPU(host: host, processes: interrupted, interval: 2))
    }

    private func snapshot(
        at second: TimeInterval, cpu: [Double?], continuity: SamplingContinuity = .continuous
    ) throws -> CapturedProcesses {
        let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: epoch.addingTimeInterval(second))
        let processes = try cpu.enumerated().map { index, value in
            ProcessReading(
                id: try ProcessIdentity(pid: Int32(index + 1), startSeconds: 1, startMicroseconds: 0), parentPID: 1, uid: 501,
                name: "P\(index)", stamp: stamp,
                cpuPercentOfMachine: try value.map { try .measured($0) } ?? .restricted(reason: "EPERM"),
                memoryFootprintBytes: .collecting(), diskReadBytesPerSecond: .collecting(),
                diskWriteBytesPerSecond: .collecting(), executablePath: nil, responsiblePID: nil
            )
        }
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(Double(cpu.count)), enumerationTruncated: false,
            processes: processes, issues: [], continuity: continuity
        )
    }
}
