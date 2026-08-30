import Foundation

enum LiveReviewCaptureStability: String, Sendable, Equatable {
    case checking
    case steady
    case moving
    case unavailable
}

struct LiveReviewMotionSample: Sendable, Equatable {
    let rotationMagnitude: Double
    let accelerationMagnitude: Double
}

struct LiveReviewStabilityClassifier: Sendable, Equatable {
    var minimumSamples = 12
    var maximumSamples = 20
    var maximumRotationMagnitude = 0.035
    var maximumAccelerationMagnitude = 0.025
    var minimumStableRatio = 0.8

    func classify(_ samples: [LiveReviewMotionSample]) -> LiveReviewCaptureStability {
        guard samples.count >= minimumSamples else { return .checking }
        let window = samples.suffix(maximumSamples)
        let steadyCount = window.reduce(into: 0) { result, sample in
            if sample.rotationMagnitude < maximumRotationMagnitude,
               sample.accelerationMagnitude < maximumAccelerationMagnitude {
                result += 1
            }
        }
        let stableRatio = Double(steadyCount) / Double(window.count)
        return stableRatio >= minimumStableRatio ? .steady : .moving
    }
}

struct LiveReviewCaptureQuality: Sendable, Equatable {
    enum FocusExposureState: String, Sendable, Equatable {
        case settling
        case locked
        case unavailable
    }

    var framesPerSecond: Double
    var focusExposureState: FocusExposureState
    var stability: LiveReviewCaptureStability
    var framingGuidance: String

    static let preparing = LiveReviewCaptureQuality(
        framesPerSecond: 0,
        focusExposureState: .settling,
        stability: .checking,
        framingGuidance: "Brace the phone behind the ball and keep the full flight corridor in frame."
    )
}

enum LiveReviewState: Sendable, Equatable {
    case idle
    case requestingPermission
    case preparing
    case armed
    case collectingPostRoll(candidate: SwingCandidate, completesAt: Date)
    case finalising(candidate: SwingCandidate)
    case paused(reason: LiveReviewPauseReason)
    case failed(message: String)
}

enum LiveReviewPauseReason: String, Sendable, Equatable {
    case interrupted
    case thermalPressure
    case lowStorage
    case captureUnavailable
}

struct LiveReviewReplaySchedule: Sendable, Equatable {
    let candidateID: UUID
    let fireDate: Date
    let clipWindow: ImpactClipWindow

    init(candidate: SwingCandidate, fireDate: Date) {
        candidateID = candidate.id
        self.fireDate = fireDate
        clipWindow = candidate.clipWindow
    }
}

struct FinalizedCaptureSegment: Identifiable, Sendable, Equatable {
    let id: UUID
    let url: URL
    let timeRange: ReviewTimeRange

    init(id: UUID = UUID(), url: URL, timeRange: ReviewTimeRange) {
        self.id = id
        self.url = url
        self.timeRange = timeRange
    }
}

/// A value-only segment ledger. Video writers own bytes; the controller uses this to avoid deleting a segment
/// which might contribute to a pending impact clip.
struct RollingSegmentLedger: Sendable, Equatable {
    private(set) var segments: [FinalizedCaptureSegment] = []
    let retentionDuration: TimeInterval

    init(retentionDuration: TimeInterval = 8) {
        self.retentionDuration = max(retentionDuration, ImpactClipWindow.defaultPreRoll)
    }

    mutating func append(_ segment: FinalizedCaptureSegment) -> [FinalizedCaptureSegment] {
        segments.append(segment)
        return evictableSegments(at: segment.timeRange.end)
    }

    func protectedSegments(for window: ImpactClipWindow) -> [FinalizedCaptureSegment] {
        let protectedRange = ReviewTimeRange(
            start: max(0, window.impactTime - window.preRoll),
            duration: window.preRoll + window.postRoll
        )
        return segments.filter { segment in
            segment.timeRange.start < protectedRange.end && segment.timeRange.end > protectedRange.start
        }
    }

    func evictableSegments(at currentTime: TimeInterval, protectedIDs: Set<UUID> = []) -> [FinalizedCaptureSegment] {
        let cutoff = currentTime - retentionDuration
        return segments.filter { $0.timeRange.end <= cutoff && !protectedIDs.contains($0.id) }
    }

    mutating func remove(ids: Set<UUID>) {
        segments.removeAll { ids.contains($0.id) }
    }
}
