// Extracts stills from a recording at a fixed rate, for frame-by-frame review.
import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 4, let rate = Double(arguments[3]), rate > 0 else {
    print("usage: frames.swift <movie> <directory> <frames per second>")
    exit(2)
}
let asset = AVURLAsset(url: URL(fileURLWithPath: arguments[1]))
let generator = AVAssetImageGenerator(asset: asset)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
let seconds = try await asset.load(.duration).seconds
var index = 0
var time = 0.0
while time < seconds {
    let image = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
    let url = URL(fileURLWithPath: arguments[2]).appendingPathComponent(String(format: "frame-%04d.png", index))
    if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
    index += 1
    time += 1 / rate
}
print("\(index) frames from \(String(format: "%.1f", seconds)) s")
