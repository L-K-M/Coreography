import Foundation
import CoreographyDrivers

/// A spindump of one process, as `spindump` wrote it. The tool only runs as
/// root, so the privileged helper does the work: without it the answer is
/// nil, not a report.
public struct ProcessSpindumper: Sendable {
    /// Long enough to catch a busy loop; the helper caps it at 30 seconds.
    public static let defaultSeconds = 3
    private let helper: PrivilegedHelper?

    public init() { self.init(helper: .shared) }

    init(helper: PrivilegedHelper?) { self.helper = helper }

    /// The report, or nil while the helper is not installed, approved and answering.
    public func spindump(_ process: ProcessReading, seconds: Int = defaultSeconds) async -> Result<ProcessSampleReport, ProcessSampleFailure>? {
        guard let helper else { return nil }
        let start = Date()
        guard let result = await helper.spindump(process.id.helperIdentity, seconds: seconds) else { return nil }
        switch result {
        case .success(let text):
            return .success(ProcessSampleReport(
                process: process.id, name: process.name, tool: .spindump, takenAt: start, seconds: seconds, text: text
            ))
        case .failure(let failure):
            return .failure(failure)
        }
    }
}
