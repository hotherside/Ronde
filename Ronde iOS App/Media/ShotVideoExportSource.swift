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
    /// `sourceRange` is expressed in the source movie's presentation timeline. Supplying it
    /// avoids reading every sample in a long recording merely to make a short child shot editable.
    func presentationTimes(url: URL, sourceRange: ReviewTimeRange? = nil) async throws -> [TimeInterval] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        if let sourceRange, sourceRange.duration > 0 {
            reader.timeRange = CMTimeRange(
                start: CMTime(seconds: sourceRange.start, preferredTimescale: 60_000),
                duration: CMTime(seconds: sourceRange.duration, preferredTimescale: 60_000)
            )
        }
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
            if time.isFinite, time >= 0,
               sourceRange.map({ time >= $0.start && time <= $0.end }) ?? true {
                times.append(time)
            }
        }
        guard reader.status != .failed else { throw ShotVideoExportError.cannotRead }
        return Array(Set(times)).sorted()
    }

    /// `sourceRange` keeps thumbnail requests near the editable child-shot window. The
    /// no-range overload behaviour remains the full asset interval from zero to `duration`.
    func thumbnails(url: URL, duration: TimeInterval, count: Int = 9, sourceRange: ReviewTimeRange? = nil) async -> [ShotVideoThumbnail] {
        let range = sourceRange ?? ReviewTimeRange(start: 0, duration: duration)
        guard range.duration > 0 else { return [] }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 260, height: 260)
        let safeCount = max(2, min(12, count))
        var images: [ShotVideoThumbnail] = []
        for index in 0..<safeCount {
            guard !Task.isCancelled else { generator.cancelAllCGImageGeneration(); break }
            let progress = safeCount == 1 ? 0 : Double(index) / Double(safeCount - 1)
            let time = range.start + range.duration * progress
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
