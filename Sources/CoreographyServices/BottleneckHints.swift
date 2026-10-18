import Foundation
import CoreographyKit

/// A labelled heuristic about what limits performance now (plan:
/// bottleneck hints, after PresentMon and RTSS). Thresholds over the last
/// seconds, never a verdict; the evidence says which readings tripped it.
public struct BottleneckHint: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case gpuBound, cpuBound, throttling
    }

    public let kind: Kind
    public let title: String
    /// Example: ["GPU busy 97% (at least 90%)", "P cores 31% active (at most 50%)"].
    public let evidence: [String]
}

enum BottleneckHints {
    /// Recent seconds compared against thresholds; the throttling check
    /// compares them with the seconds before.
    static let window: TimeInterval = 5
    private static let pinnedGPUPercent = 90.0
    private static let idleTopTierPercent = 50.0
    private static let saturatedTopTierPercent = 90.0
    /// Within this share of its top frequency, a tier runs flat out.
    private static let topFrequencyShare = 0.95
    private static let gpuHeadroomPercent = 70.0
    /// A drop this large while busy and under thermal pressure suggests throttling.
    private static let frequencyDropShare = 0.10

    /// Hints from the newest `window` seconds of each series; none without data.
    static func evaluate(
        gpu: [CapturedGPU], silicon: [CapturedSilicon], thermal: ThermalPressureLevel?, now: Date
    ) -> [BottleneckHint] {
        let recentStart = now.addingTimeInterval(-window)
        let recentSilicon = silicon.filter { $0.stamp.wallTime > recentStart && $0.stamp.wallTime <= now }
        let earlierSilicon = silicon.filter {
            $0.stamp.wallTime > recentStart.addingTimeInterval(-window) && $0.stamp.wallTime <= recentStart
        }
        let gpuBusy = mean(gpu.filter { $0.stamp.wallTime > recentStart && $0.stamp.wallTime <= now }.compactMap { frame in
            frame.devices.compactMap(\.utilizationPercent.numericValue).max()
        })
        let topActive = mean(recentSilicon.compactMap { $0.topTier?.activePercent.numericValue })
        let topFrequency = mean(recentSilicon.compactMap { $0.topTier?.frequencyMHz.numericValue })
        let earlierFrequency = mean(earlierSilicon.compactMap { $0.topTier?.frequencyMHz.numericValue })
        let topMaximum = recentSilicon.last?.topTier?.maximumMHz
        let tier = recentSilicon.last?.topTier.map { "\($0.kind.rawValue) cores" } ?? "Top cores"

        var hints: [BottleneckHint] = []
        if let gpuBusy, let topActive, gpuBusy >= pinnedGPUPercent, topActive <= idleTopTierPercent {
            hints.append(BottleneckHint(kind: .gpuBound, title: "Looks GPU-bound", evidence: [
                "GPU busy \(percent(gpuBusy)) (at least \(percent(pinnedGPUPercent)))",
                "\(tier) \(percent(topActive)) active (at most \(percent(idleTopTierPercent)))"
            ]))
        }
        if let topActive, let topFrequency, let topMaximum, let gpuBusy,
           topActive >= saturatedTopTierPercent, topFrequency >= topMaximum * topFrequencyShare, gpuBusy <= gpuHeadroomPercent {
            hints.append(BottleneckHint(kind: .cpuBound, title: "Looks CPU-bound", evidence: [
                "\(tier) \(percent(topActive)) active (at least \(percent(saturatedTopTierPercent)))",
                "\(tier) at \(megahertz(topFrequency)) of \(megahertz(topMaximum))",
                "GPU busy \(percent(gpuBusy)) (at most \(percent(gpuHeadroomPercent)))"
            ]))
        }
        if let thermal, thermal.rawValue >= ThermalPressureLevel.moderate.rawValue, let topActive, let topFrequency, let earlierFrequency,
           topActive >= idleTopTierPercent, topFrequency <= earlierFrequency * (1 - frequencyDropShare) {
            hints.append(BottleneckHint(kind: .throttling, title: "Possibly throttling", evidence: [
                "Thermal pressure \(thermal)",
                "\(tier) fell from \(megahertz(earlierFrequency)) to \(megahertz(topFrequency)) while \(percent(topActive)) active"
            ]))
        }
        return hints
    }

    private static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    private static func megahertz(_ value: Double) -> String { "\(Int(value.rounded())) MHz" }
}
