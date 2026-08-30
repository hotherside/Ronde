import AVFoundation
import Foundation

struct VideoAssetMetadata: Codable, Sendable, Equatable {
    var duration: TimeInterval
    var naturalWidth: Double
    var naturalHeight: Double
    var nominalFrameRate: Float
    var isExportable: Bool
    var isReadable: Bool
    var preferredTransform: [Double]

    /// Display width divided by display height after the track's preferred
    /// orientation is applied. This keeps portrait footage portrait in review.
    var displayAspectRatio: Double? {
        guard naturalWidth > 0, naturalHeight > 0 else { return nil }
        let isQuarterTurn = preferredTransform.count >= 4
            && (abs(preferredTransform[1]) > 0.5 || abs(preferredTransform[2]) > 0.5)
        let width = isQuarterTurn ? naturalHeight : naturalWidth
        let height = isQuarterTurn ? naturalWidth : naturalHeight
        guard height > 0 else { return nil }
        return width / height
    }
}

enum VideoMetadataProbeError: LocalizedError, Sendable {
    case noVideoTrack

    var errorDescription: String? { "The selected media does not contain a video track." }
}

actor VideoMetadataProbe {
    func probe(url: URL) async throws -> VideoAssetMetadata {
        let asset = AVURLAsset(url: url)
        // AVAssetTrack is non-Sendable. Keep its asynchronous property loads ordered instead
        // of using async-let child tasks that could access the same track concurrently.
        let loadedDuration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let loadedExportable = try await asset.load(.isExportable)
        let loadedReadable = try await asset.load(.isReadable)
        guard let videoTrack = tracks.first else { throw VideoMetadataProbeError.noVideoTrack }
        let size = try await videoTrack.load(.naturalSize)
        let loadedFrameRate = try await videoTrack.load(.nominalFrameRate)
        let transform = try await videoTrack.load(.preferredTransform)
        return VideoAssetMetadata(
            duration: CMTimeGetSeconds(loadedDuration),
            naturalWidth: size.width,
            naturalHeight: size.height,
            nominalFrameRate: loadedFrameRate,
            isExportable: loadedExportable,
            isReadable: loadedReadable,
            preferredTransform: [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty]
        )
    }
}
