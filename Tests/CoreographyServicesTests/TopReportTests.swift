import Foundation
import XCTest
@testable import CoreographyKit
@testable import CoreographyServices

final class TopReportTests: XCTestCase {
    private let stamp = SampleStamp(clockID: UUID(), monotonicNanoseconds: 1, wallTime: Date(timeIntervalSince1970: 1_700_000_000))

    func testRanksAppsAndLoneProcessesAndSaysWhatItLeftOut() throws {
        let processes = try snapshot([
            (100, "Safari", "/Applications/Safari.app/Contents/MacOS/Safari", nil, 10, 1_000),
            (101, "Safari Helper", "/Applications/Safari.app/Contents/XPCServices/Helper.app/Contents/MacOS/Helper", 100, 15, 3_000),
            (200, "mds", nil, nil, 5, 9_000),
            (300, "kernel_task", nil, nil, nil, 1)
        ])
        let report = TopReport.make(processes: processes, traffic: nil, sortedBy: .cpu, count: 2)
        XCTAssertEqual(report.rows.map(\.name), ["Safari", "mds"])
        XCTAssertEqual(report.rows.first?.processes, 2)
        XCTAssertNil(report.rows.first?.pid, "an app has no single PID")
        XCTAssertEqual(report.rows.first?.cpuPercentOfMachine.numericValue, 25)
        XCTAssertEqual(report.rows.last?.pid, 200)
        XCTAssertEqual(report.total, 3, "two apps and the restricted process")
        XCTAssertEqual(report.restrictedProcesses, 1)
        XCTAssertEqual(report.sort, .cpu)

        let byMemory = TopReport.make(processes: processes, traffic: nil, sortedBy: .memory, count: 1)
        XCTAssertEqual(byMemory.rows.map(\.name), ["mds"])

        let json = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(TopReport.self, from: json)
        XCTAssertEqual(decoded.rows.map(\.name), ["Safari", "mds"])
    }

    private func snapshot(_ rows: [(Int32, String, String?, Int32?, Double?, Double)]) throws -> CapturedProcesses {
        let source = MetricSource(provider: "processes", driver: "libproc")
        let processes = try rows.map { pid, name, path, responsible, cpu, footprint in
            ProcessReading(
                id: try ProcessIdentity(pid: pid, startSeconds: UInt64(pid), startMicroseconds: 0), parentPID: 1, uid: 501,
                name: name, stamp: stamp,
                cpuPercentOfMachine: try cpu.map { try .measured($0, source: source) } ?? .restricted(reason: "EPERM", source: source),
                memoryFootprintBytes: try .measured(footprint, source: source),
                diskReadBytesPerSecond: try .measured(0, source: source), diskWriteBytesPerSecond: try .measured(0, source: source),
                executablePath: path, responsiblePID: responsible
            )
        }
        return ProcessSnapshot(
            stamp: stamp, collectorPID: 1, enumeration: try .measured(Double(processes.count)), enumerationTruncated: false,
            processes: processes, issues: [], continuity: .continuous
        )
    }
}
