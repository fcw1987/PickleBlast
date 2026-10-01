import AVFoundation
import AppKit
import Foundation
let args = CommandLine.arguments
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
let directory = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for second in args.dropFirst(3).compactMap(Double.init) {
    do {
        let image = try await generator.image(at: CMTime(seconds: second, preferredTimescale: 600)).image
        let bitmap = NSBitmapImageRep(cgImage: image)
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(String(format: "frame-%05.2f.png", second)))
    } catch { print("Frame \(second): \(error)") }
}
