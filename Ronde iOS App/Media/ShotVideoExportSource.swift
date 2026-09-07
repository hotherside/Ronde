@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

struct ShotVideoThumbnail: Identifiable, @unchecked Sendable {
    let time: TimeInterval
    let image: CGImage
    var id: TimeInterval { time }
}

actor ShotVideoSourceInspector {
    /// Read compressed sample timing, not a guessed frame rate. Sorting accounts for B-frame
    /// decode order and preserves a variable-rate source's actual presentation sequence.
    func presentationTimes(url: URL) async throws -> [TimeInterval] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { throw ShotVideoExportError.cannotRead }
        var times: [TimeInterval] = []
        while let time = autoreleasepool(invoking: { () -> TimeInterval? in
            guard let sample = output.copyNextSampleBuffer() else { return nil }
            return CMSampleBufferGetPresentationTimeStamp(sample).seconds
        }) {
            if Task.isCancelled { reader.cancelReading(); throw CancellationError() }
            if time.isFinite, time >= 0 { times.append(time) }
        }
        guard reader.status != .failed else { throw ShotVideoExportError.cannotRead }
        return Array(Set(times)).sorted()
    }

    func thumbnails(url: URL, duration: TimeInterval, count: Int = 9) async -> [ShotVideoThumbnail] {
        guard duration > 0 else { return [] }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 260, height: 260)
        let safeCount = max(2, min(12, count))
        var images: [ShotVideoThumbnail] = []
        for index in 0..<safeCount {
            guard !Task.isCancelled else { generator.cancelAllCGImageGeneration(); break }
            let time = duration * Double(index) / Double(safeCount)
            if let image = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 60_000)).image {
                images.append(ShotVideoThumbnail(time: time, image: image))
            }
        }
        return images
    }

    func image(url: URL, at time: TimeInterval) async -> ShotVideoThumbnail? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        guard let image = try? await generator.image(at: CMTime(seconds: max(0, time), preferredTimescale: 60_000)).image else { return nil }
        return ShotVideoThumbnail(time: time, image: image)
    }
}
