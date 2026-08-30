import AVFoundation
import Foundation

/// Configuration retained for source compatibility while Vision trajectory output is deliberately
/// excluded from automatic shot creation. A generic parabola can be a person, bird or moving
/// shadow, so it must not become a shot candidate or a claimed ball tracer.
struct TrajectoryAnalysisConfiguration: Sendable, Equatable {
    var frameAnalysisSpacing: TimeInterval
    var trajectoryLength: Int
    var minimumNormalizedRadius: Float
    var maximumNormalizedRadius: Float

    static let golfPrototype = TrajectoryAnalysisConfiguration(
        frameAnalysisSpacing: 1.0 / 30.0,
        trajectoryLength: 5,
        minimumNormalizedRadius: 0.0005,
        maximumNormalizedRadius: 0.05
    )
}

enum TrajectoryAnalysisError: LocalizedError, Sendable {
    case noVideoTrack
    case unreadableAsset

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "The video has no readable video track."
        case .unreadableAsset: "The selected video cannot be read on this device."
        }
    }
}

/// Legacy compatibility surface. `VNDetectTrajectoriesRequest` is intentionally not used to
/// create `SwingCandidate`s: it detects generic parabolic objects, not golf shots. A future,
/// validated ball detector can expose its output through a distinct, confidence-gated tracer API.
actor TrajectoryAnalysisService {
    func analyse(
        url: URL,
        configuration _: TrajectoryAnalysisConfiguration = .golfPrototype,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [SwingCandidate] {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isReadable) else { throw TrajectoryAnalysisError.unreadableAsset }
        guard !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw TrajectoryAnalysisError.noVideoTrack
        }
        progress?(1)
        return []
    }
}
