import Foundation
import CoreographyKit

public typealias CapturedSpaceArea = SpaceArea
public typealias CapturedSpaceAccess = SpaceAccess
public typealias CapturedSpaceSize = SpaceAreaSize

/// One strand of the startup volume's used space.
public struct SpaceStrand: Identifiable, Equatable, Sendable {
    public enum Kind: Hashable, Sendable {
        case area(CapturedSpaceArea)
        /// Used space no measured area explains: macOS itself, other
        /// users, swap, snapshots and every folder not walked.
        case rest
    }

    public var id: Kind { kind }
    public let kind: Kind
    /// Nil for the rest when the areas add up to more than the used space.
    public let bytes: Int64?
    /// Share of the used space, 0...1.
    public let share: Double?
    /// The area's walk saw only part of it, so the bytes are "at least".
    public let isLowerBound: Bool
    /// The rest is "at most": some area is a lower bound or unmeasured.
    public let isUpperBound: Bool
    public let size: CapturedSpaceSize?
}

/// The startup volume's used space braided from its areas (plan: the
/// Disk lane's capacity, taken apart). Areas add up because each file is
/// walked once, so the rest is what the walk did not see.
///
/// ```text
/// used = Applications + Library + ... + rest        free stays outside
/// rest = used - sum(measured areas)                 nil if negative
/// ```
public struct SpaceBraid: Equatable, Sendable {
    public let volume: CapturedVolume
    /// Measured areas largest first, then the rest.
    public let strands: [SpaceStrand]
    /// Areas macOS must allow first, not measured yet.
    public let unmeasured: [CapturedSpaceArea]
    /// The area being walked now.
    public let measuring: CapturedSpaceArea?

    public var usedBytes: Int64 { volume.totalBytes - volume.availableBytes }

    /// Each strand's stretch of the whole volume, 0...1, in strand order;
    /// free space follows the last. Areas that overrun the used space are
    /// scaled down to fit it, so the rope never claims free space.
    public var spans: [Range<Double>] {
        guard volume.totalBytes > 0 else { return strands.map { _ in 0..<0 } }
        let used = Double(max(usedBytes, 0))
        let sum = strands.reduce(0.0) { $0 + Double($1.bytes ?? 0) }
        let scale = sum > used && sum > 0 ? used / sum : 1
        var start = 0.0
        return strands.map { strand in
            let width = Double(strand.bytes ?? 0) * scale / Double(volume.totalBytes)
            defer { start += width }
            return start..<(start + width)
        }
    }

    /// False when the measured areas add up to more than the used space:
    /// APFS clones and files shared between apps count once per copy.
    public var reconciles: Bool { strands.last?.bytes != nil }

    public init(volume: CapturedVolume, sizes: [CapturedSpaceArea: CapturedSpaceSize],
                unmeasured: [CapturedSpaceArea], measuring: CapturedSpaceArea?) {
        self.volume = volume
        self.unmeasured = unmeasured
        self.measuring = measuring

        let used = max(volume.totalBytes - volume.availableBytes, 0)
        let share = { (bytes: Int64) -> Double? in used > 0 ? Double(bytes) / Double(used) : nil }
        let measured = sizes.values
            .filter { $0.bytes > 0 }
            .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.area.rawValue < $1.area.rawValue }
        var strands = measured.map {
            SpaceStrand(kind: .area($0.area), bytes: $0.bytes, share: share($0.bytes),
                        isLowerBound: $0.isLowerBound, isUpperBound: false, size: $0)
        }

        let remainder = used - measured.reduce(0) { $0 + $1.bytes }
        let rest: Int64? = remainder >= 0 ? remainder : nil
        let upper = !unmeasured.isEmpty || measuring != nil || measured.contains(where: \.isLowerBound)
        strands.append(SpaceStrand(kind: .rest, bytes: rest, share: rest.flatMap(share),
                                   isLowerBound: false, isUpperBound: upper, size: nil))
        self.strands = strands
    }
}
