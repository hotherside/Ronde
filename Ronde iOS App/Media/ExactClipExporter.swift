import AVFoundation
import Foundation

enum ExactClipExportError: LocalizedError, Sendable {
    case sourceIsNotExportable
    case invalidRange
    case cannotCreateExportSession
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .sourceIsNotExportable: "This video cannot be exported on this device."
        case .invalidRange: "The requested clip range is outside the source video."
        case .cannotCreateExportSession: "Ronde could not create a video export session."
        case .cancelled: "Video export was cancelled."
        case let .failed(message): message
        }
    }
}

actor ExactClipExporter {
    /// Exports a new app-owned derivative. It never changes the source asset.
    func export(
        sourceURL: URL,
        range: ReviewTimeRange,
        destinationURL: URL,
        preset: String = AVAssetExportPresetHighestQuality
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard try await asset.load(.isExportable) else { throw ExactClipExportError.sourceIsNotExportable }
        let duration = try await asset.load(.duration)
        let sourceDuration = CMTimeGetSeconds(duration)
        guard range.start < sourceDuration, range.duration > 0, range.end <= sourceDuration + 0.001 else {
            throw ExactClipExportError.invalidRange
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ExactClipExportError.cannotCreateExportSession
        }

        session.outputURL = destinationURL
        session.outputFileType = .mov
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: range.start, preferredTimescale: 600),
            duration: CMTime(seconds: range.duration, preferredTimescale: 600)
        )

        let sessionBox = ExportSessionBox(session)
        try await withCheckedThrowingContinuation { continuation in
            sessionBox.session.exportAsynchronously {
                switch sessionBox.session.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: ExactClipExportError.cancelled)
                default:
                    continuation.resume(throwing: ExactClipExportError.failed(sessionBox.session.error?.localizedDescription ?? "Video export failed."))
                }
            }
        }
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}
