@preconcurrency import AVFoundation
import Foundation
import ImageIO
import Vision

/// A sampled change in the golfer's recognised pose. This is deliberately a motion marker, not
/// a classifier: a practice swing can produce the same signal as a struck ball.
struct BodyMotionPeak: Sendable, Equatable, Comparable {
    let time: TimeInterval
    let strength: Double

    init(time: TimeInterval, strength: Double) {
        self.time = max(0, time)
        self.strength = max(0, strength)
    }

    static func < (lhs: BodyMotionPeak, rhs: BodyMotionPeak) -> Bool {
        lhs.time == rhs.time ? lhs.strength < rhs.strength : lhs.time < rhs.time
    }
}

struct BodyMotionAnalysisConfiguration: Sendable, Equatable {
    /// Pose analysis is intentionally sampled rather than run on every 4K source frame.
    var sampleInterval: TimeInterval
    var minimumJointConfidence: Float
    var minimumRecognisedJoints: Int
    var minimumMotion: Double
    var clusterSeparation: TimeInterval
    var refractoryPeriod: TimeInterval
    var minimumSignalToNoiseRatio: Double

    static let golfTripod = BodyMotionAnalysisConfiguration(
        sampleInterval: 0.1,
        minimumJointConfidence: 0.25,
        minimumRecognisedJoints: 4,
        minimumMotion: 0.025,
        clusterSeparation: 0.45,
        refractoryPeriod: 4.0,
        minimumSignalToNoiseRatio: 2.75
    )
}

enum BodyMotionAnalysisError: LocalizedError, Sendable {
    case unreadableAsset
    case noVideoTrack
    case readerFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableAsset:
            "The selected video cannot be read on this device."
        case .noVideoTrack:
            "The selected video has no readable video track."
        case let .readerFailed(message):
            message
        }
    }
}

/// Deterministic policy for grouping motion bursts into human-reviewable markers.
struct BodyMotionPeakSelector: Sendable {
    func select(
        from rawPeaks: [BodyMotionPeak],
        configuration: BodyMotionAnalysisConfiguration = .golfTripod
    ) -> [BodyMotionPeak] {
        let peaks = rawPeaks
            .filter { $0.time.isFinite && $0.strength.isFinite && $0.strength > 0 }
            .sorted()
        guard !peaks.isEmpty else { return [] }

        let noiseFloor = percentile(peaks.map(\.strength), percentile: 0.5)
        let threshold = max(
            configuration.minimumMotion,
            noiseFloor * configuration.minimumSignalToNoiseRatio
        )
        let strongPeaks = peaks.filter { $0.strength >= threshold }
        guard !strongPeaks.isEmpty else { return [] }

        return enforceRefractoryPeriod(
            mergeClusters(strongPeaks, separation: configuration.clusterSeparation),
            period: configuration.refractoryPeriod
        )
    }

    func mergeClusters(_ peaks: [BodyMotionPeak], separation: TimeInterval) -> [BodyMotionPeak] {
        guard let first = peaks.sorted().first else { return [] }
        let safeSeparation = max(0, separation)
        var selected: [BodyMotionPeak] = []
        var current = first
        var previousTime = first.time

        for peak in peaks.sorted().dropFirst() {
            if peak.time - previousTime <= safeSeparation {
                if peak.strength > current.strength { current = peak }
            } else {
                selected.append(current)
                current = peak
            }
            previousTime = peak.time
        }
        selected.append(current)
        return selected
    }

    func enforceRefractoryPeriod(_ peaks: [BodyMotionPeak], period: TimeInterval) -> [BodyMotionPeak] {
        guard let first = peaks.sorted().first else { return [] }
        let safePeriod = max(0, period)
        var selected: [BodyMotionPeak] = []
        var current = first

        for peak in peaks.sorted().dropFirst() {
            if peak.time - current.time < safePeriod {
                if peak.strength > current.strength { current = peak }
            } else {
                selected.append(current)
                current = peak
            }
        }
        selected.append(current)
        return selected
    }

    private func percentile(_ values: [Double], percentile: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let index = min(max(Int((Double(sorted.count - 1) * percentile).rounded()), 0), sorted.count - 1)
        return sorted[index]
    }
}

/// On-device Vision fallback when an imported video has no readable audio or its native audio
/// encoding cannot be decoded. It looks for an isolated full-swing motion burst on a fixed tripod.
actor BodyMotionAnalysisService {
    private let selector: BodyMotionPeakSelector

    init(selector: BodyMotionPeakSelector = .init()) {
        self.selector = selector
    }

    func analyse(
        url: URL,
        configuration: BodyMotionAnalysisConfiguration = .golfTripod,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [SwingCandidate] {
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isReadable) else { throw BodyMotionAnalysisError.unreadableAsset }
        let duration = try await asset.load(.duration)
        let durationSeconds = max(CMTimeGetSeconds(duration), 0.001)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw BodyMotionAnalysisError.noVideoTrack
        }
        let visionOrientation = try await Self.visionOrientation(for: videoTrack)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw BodyMotionAnalysisError.unreadableAsset }
        reader.add(output)
        guard reader.startReading() else {
            throw BodyMotionAnalysisError.readerFailed(reader.error?.localizedDescription ?? "Video reader failed to start.")
        }

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNSequenceRequestHandler()
        var rawPeaks: [BodyMotionPeak] = []
        var previousPose: [String: NormalizedPoint]?
        var lastAnalysedTime = -Double.infinity

        while let sampleBuffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                throw CancellationError()
            }
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let seconds = CMTimeGetSeconds(presentationTime)
            progress?(min(max(seconds / durationSeconds, 0), 1))
            guard seconds - lastAnalysedTime >= configuration.sampleInterval,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }
            lastAnalysedTime = seconds

            do {
                try handler.perform([request], on: pixelBuffer, orientation: visionOrientation)
            } catch {
                // A single difficult frame should not discard an imported recording.
                continue
            }
            guard let observation = request.results?.first,
                  let pose = Self.posePoints(from: observation, minimumConfidence: configuration.minimumJointConfidence),
                  pose.count >= configuration.minimumRecognisedJoints else {
                continue
            }

            if let previousPose {
                let motion = Self.motion(between: previousPose, and: pose)
                rawPeaks.append(BodyMotionPeak(time: seconds, strength: motion))
            }
            previousPose = pose
        }

        if reader.status == .failed {
            throw BodyMotionAnalysisError.readerFailed(reader.error?.localizedDescription ?? "Body-motion analysis failed.")
        }

        progress?(1)
        return selector.select(from: rawPeaks, configuration: configuration).map { peak in
            SwingCandidate(
                impactTime: peak.time,
                classification: .provisional(
                    confidence: Self.confidence(for: peak.strength),
                    explanation: "A burst of body motion was found. Review and adjust the impact frame before saving the shot."
                ),
                evidence: [.bodyMotion]
            )
        }
    }

    private static func posePoints(
        from observation: VNHumanBodyPoseObservation,
        minimumConfidence: Float
    ) -> [String: NormalizedPoint]? {
        let joints: [(String, VNHumanBodyPoseObservation.JointName)] = [
            ("leftWrist", .leftWrist),
            ("rightWrist", .rightWrist),
            ("leftElbow", .leftElbow),
            ("rightElbow", .rightElbow),
            ("leftShoulder", .leftShoulder),
            ("rightShoulder", .rightShoulder),
            ("leftHip", .leftHip),
            ("rightHip", .rightHip)
        ]
        var points: [String: NormalizedPoint] = [:]
        for (name, joint) in joints {
            guard let point = try? observation.recognizedPoint(joint), point.confidence >= minimumConfidence else {
                continue
            }
            points[name] = NormalizedPoint(x: point.location.x, y: point.location.y)
        }
        return points
    }

    /// AVFoundation stores many portrait phone movies as landscape pixel buffers plus a preferred
    /// transform. Vision needs the corresponding pixel-buffer orientation to see a person upright.
    private static func visionOrientation(for track: AVAssetTrack) async throws -> CGImagePropertyOrientation {
        let transform = try await track.load(.preferredTransform)
        let a = Int(transform.a.rounded())
        let b = Int(transform.b.rounded())
        let c = Int(transform.c.rounded())
        let d = Int(transform.d.rounded())

        switch (a, b, c, d) {
        case (0, 1, -1, 0):
            return CGImagePropertyOrientation.right
        case (0, -1, 1, 0):
            return CGImagePropertyOrientation.left
        case (-1, 0, 0, -1):
            return CGImagePropertyOrientation.down
        default:
            return CGImagePropertyOrientation.up
        }
    }

    private static func motion(
        between previous: [String: NormalizedPoint],
        and current: [String: NormalizedPoint]
    ) -> Double {
        let deltas = current.compactMap { name, point -> (String, Double)? in
            guard let earlier = previous[name] else { return nil }
            return (name, hypot(point.x - earlier.x, point.y - earlier.y))
        }
        guard !deltas.isEmpty else { return 0 }
        let wristMotion = deltas
            .filter { $0.0.contains("Wrist") }
            .map(\.1)
            .max() ?? 0
        let meanMotion = deltas.map(\.1).reduce(0, +) / Double(deltas.count)
        return max(wristMotion, meanMotion)
    }

    private static func confidence(for motion: Double) -> Double {
        // Motion magnitude ranks review markers only; it is not a shot-confidence score.
        min(max(0.36 + (motion * 2.2), 0.36), 0.68)
    }
}
