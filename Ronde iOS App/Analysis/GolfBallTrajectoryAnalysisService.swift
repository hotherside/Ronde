@preconcurrency import AVFoundation
import Foundation
import ImageIO
import Vision

struct GolfBallTrajectoryConfiguration: Sendable, Equatable {
    /// The request consumes the timestamps that exist in the upload. It never rejects a source
    /// because of its nominal frame rate.
    var maximumPostImpactDuration: TimeInterval
    var trajectoryLength: Int
    var minimumNormalizedRadius: Float
    var maximumNormalizedRadius: Float
    var minimumConfidence: Float

    static let uploadedVideo = GolfBallTrajectoryConfiguration(
        maximumPostImpactDuration: 3.2,
        trajectoryLength: 5,
        minimumNormalizedRadius: 0.00025,
        maximumNormalizedRadius: 0.018,
        minimumConfidence: 0.35
    )
}

enum GolfBallTrajectoryAnalysisError: LocalizedError, Sendable, Equatable {
    case unreadableAsset
    case noVideoTrack
    case ineligibleShot
    case noDefensibleBallTrack
    case readerFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableAsset:
            "The selected video cannot be read on this device."
        case .noVideoTrack:
            "The selected video has no readable video track."
        case .ineligibleShot:
            "A tracer can only be analysed for an accepted real shot."
        case .noDefensibleBallTrack:
            "The ball was not tracked reliably enough to draw a tracer."
        case let .readerFailed(message):
            message
        }
    }
}

/// Native uploaded-video baseline for the tracer feasibility lane.
///
/// Vision's generic trajectory request is intentionally constrained to the post-impact window and
/// then filtered for a plausible down-the-line launch. It does not claim that every observation is
/// a golf ball, and its provisional geometry is not eligible for automatic display.
actor GolfBallTrajectoryAnalysisService {
    /// Policy-gated entry point for automatic tracer work. Callers that are analysing a longer
    /// session must use this API rather than passing a merely provisional impact marker.
    func analyse(
        url: URL,
        acceptedShot: AcceptedShot,
        configuration: GolfBallTrajectoryConfiguration = .uploadedVideo,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> BallFlightEstimate {
        guard acceptedShot.decision.kind == .accepted,
              acceptedShot.tracerEligibility == .eligible else {
            throw GolfBallTrajectoryAnalysisError.ineligibleShot
        }
        return try await analyse(
            url: url,
            impactTime: acceptedShot.impactTime,
            configuration: configuration,
            progress: progress
        )
    }

    /// Low-level frame analysis retained for manual review and single-shot playback. It does not
    /// make an eligibility decision and generic Vision results remain `.inferred`.
    func analyse(
        url: URL,
        impactTime: TimeInterval,
        configuration: GolfBallTrajectoryConfiguration = .uploadedVideo,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> BallFlightEstimate {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isReadable) else {
            throw GolfBallTrajectoryAnalysisError.unreadableAsset
        }
        let duration = max(CMTimeGetSeconds(try await asset.load(.duration)), 0)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw GolfBallTrajectoryAnalysisError.noVideoTrack
        }

        let nominalFrameRate = max(Double(try await track.load(.nominalFrameRate)), 1)
        let frameSpacing = CMTime(seconds: 1 / nominalFrameRate, preferredTimescale: 60_000)
        let startTime = min(max(0, impactTime - max(0.08, 2 / nominalFrameRate)), duration)
        let endTime = min(duration, impactTime + configuration.maximumPostImpactDuration)
        guard endTime > startTime else {
            progress?(1)
            throw GolfBallTrajectoryAnalysisError.noDefensibleBallTrack
        }

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 60_000),
            end: CMTime(seconds: endTime, preferredTimescale: 60_000)
        )
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw GolfBallTrajectoryAnalysisError.unreadableAsset
        }
        reader.add(output)
        guard reader.startReading() else {
            throw GolfBallTrajectoryAnalysisError.readerFailed(
                reader.error?.localizedDescription ?? "Ball-flight reader failed to start."
            )
        }

        let request = VNDetectTrajectoriesRequest(
            frameAnalysisSpacing: frameSpacing,
            trajectoryLength: max(3, configuration.trajectoryLength)
        )
        request.objectMinimumNormalizedRadius = configuration.minimumNormalizedRadius
        request.objectMaximumNormalizedRadius = configuration.maximumNormalizedRadius
        let handler = VNSequenceRequestHandler()
        let orientation = try await Self.visionOrientation(for: track)
        var observations: [VNTrajectoryObservation] = []
        var attemptedFrameCount = 0
        var successfulFrameCount = 0
        var lastVisionError: String?

        while let sampleBuffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                throw CancellationError()
            }
            let sampleTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let seconds = CMTimeGetSeconds(sampleTime)
            attemptedFrameCount += 1
            do {
                // The CMSampleBuffer carries the presentation timestamp required by Vision's
                // stateful trajectory request. `targetFrameTime` is a processing deadline, not a
                // replacement for media time.
                try handler.perform([request], on: sampleBuffer, orientation: orientation)
                successfulFrameCount += 1
                observations.append(contentsOf: (request.results ?? []).filter {
                    $0.confidence >= configuration.minimumConfidence
                })
            } catch {
                // A single undecodable or difficult frame must not discard the imported video.
                lastVisionError = error.localizedDescription
            }
            progress?(min(max((seconds - startTime) / max(endTime - startTime, 0.001), 0), 1))
        }

        if reader.status == .failed {
            throw GolfBallTrajectoryAnalysisError.readerFailed(
                reader.error?.localizedDescription ?? "Ball-flight analysis failed."
            )
        }
        if attemptedFrameCount > 0, successfulFrameCount == 0 {
            throw GolfBallTrajectoryAnalysisError.readerFailed(
                "Ball-flight frame analysis failed: \(lastVisionError ?? "Vision rejected every frame.")"
            )
        }
        progress?(1)

        guard let selected = Self.selectPlausibleTrajectory(from: observations) else {
            throw GolfBallTrajectoryAnalysisError.noDefensibleBallTrack
        }
        return Self.estimate(from: selected)
    }

    static func selectPlausibleTrajectory(
        from observations: [VNTrajectoryObservation]
    ) -> VNTrajectoryObservation? {
        observations
            .compactMap { observation -> (VNTrajectoryObservation, Double)? in
                let points = observation.detectedPoints
                guard points.count >= 3, let first = points.first, let last = points.last else {
                    return nil
                }
                let verticalTravel = Double(last.y - first.y)
                let horizontalTravel = abs(Double(last.x - first.x))
                let travel = hypot(horizontalTravel, verticalTravel)

                // A down-the-line shot begins in the lower portion of the oriented frame and moves
                // away from the mat. This removes most people, club heads, birds and range lights
                // without pretending that the remaining trajectory is model-classified golf flight.
                guard first.y <= 0.46,
                      first.x >= 0.12, first.x <= 0.88,
                      verticalTravel > 0.012,
                      travel > 0.018,
                      horizontalTravel < 0.55 else {
                    return nil
                }
                let launchCentreDistance = abs(Double(first.x) - 0.5)
                let score = (Double(observation.confidence) * 2.0)
                    + min(verticalTravel * 6.0, 1.2)
                    + min(travel * 3.0, 0.8)
                    - launchCentreDistance
                return (observation, score)
            }
            .max(by: { $0.1 < $1.1 })?
            .0
    }

    static func estimate(from observation: VNTrajectoryObservation) -> BallFlightEstimate {
        let detected = observation.detectedPoints.map {
            NormalizedPoint(x: Double($0.x), y: Double($0.y))
        }
        let projected = observation.projectedPoints.map {
            NormalizedPoint(x: Double($0.x), y: Double($0.y))
        }
        let trajectory = DetectedTrajectory(
            detectedPoints: detected,
            projectedPoints: projected,
            equationCoefficients: [
                observation.equationCoefficients.x,
                observation.equationCoefficients.y,
                observation.equationCoefficients.z
            ],
            confidence: Double(observation.confidence)
        )

        let screenDetected = detected.map { NormalizedPoint(x: $0.x, y: 1 - $0.y) }
        guard let first = screenDetected.first, let last = screenDetected.last else {
            preconditionFailure("Vision trajectories with no detected points are filtered before estimation.")
        }
        let horizontalDirection = last.x >= first.x ? 1.0 : -1.0
        let visibleRise = max(0.04, first.y - screenDetected.map(\.y).min()!)
        let apex = NormalizedPoint(
            x: first.x + (horizontalDirection * min(0.17, max(0.06, abs(last.x - first.x) * 1.4))),
            y: max(0.08, first.y - min(0.58, max(0.34, visibleRise * 2.4)))
        )
        let landing = NormalizedPoint(
            x: apex.x + (horizontalDirection * min(0.18, max(0.08, abs(last.x - first.x) * 1.2))),
            y: min(0.78, max(apex.y + 0.22, first.y - 0.16))
        )

        return BallFlightEstimate(
            launch: first,
            apex: apex,
            landing: landing,
            // Generic Vision establishes screen-space motion, not object identity. Until a
            // golf-ball-specific model passes the held-out gate, this geometry remains an
            // inferred tracer even when Vision supplied plausible points.
            source: .inferred,
            confidence: Double(observation.confidence),
            observedPointCount: detected.count,
            observedTrajectory: trajectory
        )
    }

    private static func visionOrientation(for track: AVAssetTrack) async throws -> CGImagePropertyOrientation {
        let transform = try await track.load(.preferredTransform)
        let a = Int(transform.a.rounded())
        let b = Int(transform.b.rounded())
        let c = Int(transform.c.rounded())
        let d = Int(transform.d.rounded())

        switch (a, b, c, d) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }
}
