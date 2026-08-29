import Foundation

enum ReviewCaptureMode: String, Codable, Sendable {
    case importedVideo
    case liveReview
}

struct RangeReviewSession: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var createdAt: Date
    var captureMode: ReviewCaptureMode
    var source: LocalMediaReference?
    var analysisState: ReviewAnalysisState

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        captureMode: ReviewCaptureMode,
        source: LocalMediaReference? = nil,
        analysisState: ReviewAnalysisState = .idle
    ) {
        self.id = id
        self.createdAt = createdAt
        self.captureMode = captureMode
        self.source = source
        self.analysisState = analysisState
    }
}

struct LocalMediaReference: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    /// A path relative to the app-owned media root. Never store external security-scoped URLs here.
    let relativePath: String
    let originalFilename: String
    let importedAt: Date

    init(
        id: UUID = UUID(),
        relativePath: String,
        originalFilename: String,
        importedAt: Date = .now
    ) {
        self.id = id
        self.relativePath = relativePath
        self.originalFilename = originalFilename
        self.importedAt = importedAt
    }
}

struct ReviewTimeRange: Codable, Sendable, Equatable {
    let start: TimeInterval
    let duration: TimeInterval

    init(start: TimeInterval, duration: TimeInterval) {
        self.start = max(0, start)
        self.duration = max(0, duration)
    }

    var end: TimeInterval { start + duration }
}

struct ImpactClipWindow: Codable, Sendable, Equatable {
    static let defaultPreRoll: TimeInterval = 5
    static let defaultPostRoll: TimeInterval = 5

    let impactTime: TimeInterval
    let preRoll: TimeInterval
    let postRoll: TimeInterval

    init(
        impactTime: TimeInterval,
        preRoll: TimeInterval = Self.defaultPreRoll,
        postRoll: TimeInterval = Self.defaultPostRoll
    ) {
        self.impactTime = max(0, impactTime)
        self.preRoll = max(0, preRoll)
        self.postRoll = max(0, postRoll)
    }

    func clipped(to sourceDuration: TimeInterval) -> ReviewTimeRange {
        let safeDuration = max(0, sourceDuration)
        let start = max(0, impactTime - preRoll)
        let end = min(safeDuration, impactTime + postRoll)
        return ReviewTimeRange(start: start, duration: max(0, end - start))
    }
}

enum SwingClassificationKind: String, Codable, Sendable, Equatable {
    case unclassified
    case uncertainCandidate
    case realShot
    case practiceSwing
}

/// A classification is evidence, not a product claim. V1 analysis only produces `.uncertainCandidate`.
struct SwingClassification: Codable, Sendable, Equatable {
    var kind: SwingClassificationKind
    var confidence: Double
    var isModelBacked: Bool
    var explanation: String

    static let unclassified = SwingClassification(
        kind: .unclassified,
        confidence: 0,
        isModelBacked: false,
        explanation: "No trained swing classifier is installed."
    )

    static func provisional(confidence: Double, explanation: String) -> SwingClassification {
        SwingClassification(
            kind: .uncertainCandidate,
            confidence: min(max(confidence, 0), 1),
            isModelBacked: false,
            explanation: explanation
        )
    }
}

enum SwingEvidence: String, Codable, Sendable, Equatable {
    case trajectory
    case bodyMotion
    case audioTransient
    case manual
}

struct SwingCandidate: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let impactTime: TimeInterval
    /// True until a calibrated detector or a person confirms the impact frame.
    var impactTimingIsProvisional: Bool
    var clipWindow: ImpactClipWindow
    var classification: SwingClassification
    var evidence: Set<SwingEvidence>
    var trajectory: DetectedTrajectory?

    init(
        id: UUID = UUID(),
        impactTime: TimeInterval,
        impactTimingIsProvisional: Bool = true,
        clipWindow: ImpactClipWindow? = nil,
        classification: SwingClassification = .unclassified,
        evidence: Set<SwingEvidence> = [],
        trajectory: DetectedTrajectory? = nil
    ) {
        self.id = id
        self.impactTime = max(0, impactTime)
        self.impactTimingIsProvisional = impactTimingIsProvisional
        self.clipWindow = clipWindow ?? ImpactClipWindow(impactTime: impactTime)
        self.classification = classification
        self.evidence = evidence
        self.trajectory = trajectory
    }
}

// MARK: - Long-session real-shot contracts

/// A local signal that can nominate a time for review. A proposal is deliberately not a shot.
/// Audio, human motion and generic trajectories can all be caused by another golfer or an
/// unrelated event in a long recording.
enum ShotEventProposalSignal: String, Codable, Sendable, Equatable, Hashable {
    case impactLikeAudio
    case targetBodyMotion
    case genericMotion
    case manual
}

struct ShotEventProposal: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    /// Presentation time in the source recording. It is never derived from nominal FPS.
    let sourceTime: TimeInterval
    let signals: Set<ShotEventProposalSignal>
    let confidence: Double

    init(
        id: UUID = UUID(),
        sourceTime: TimeInterval,
        signals: Set<ShotEventProposalSignal>,
        confidence: Double
    ) {
        self.id = id
        self.sourceTime = max(0, sourceTime)
        self.signals = signals
        self.confidence = min(max(confidence, 0), 1)
    }
}

enum TargetGolferEvidenceState: String, Codable, Sendable, Equatable {
    /// A target-golfer association was established by a future, validated person association stage.
    case supported
    /// Evidence identifies a different golfer, so it must not be promoted.
    case differentGolfer
    /// The current on-device pipeline cannot establish who produced the swing.
    case unavailable
    /// The proposal does not contain a swing-like body event.
    case absent
}

/// Staged evidence for a swing and impact made by the golfer the session is reviewing. The
/// baseline body-pose service cannot currently produce `.supported`; it therefore fails closed.
struct TargetGolferSwingImpactEvidence: Codable, Sendable, Equatable {
    var state: TargetGolferEvidenceState
    var impactTime: TimeInterval?
    var confidence: Double
    var sourceDescription: String

    init(
        state: TargetGolferEvidenceState,
        impactTime: TimeInterval? = nil,
        confidence: Double = 0,
        sourceDescription: String
    ) {
        self.state = state
        self.impactTime = impactTime.map { max(0, $0) }
        self.confidence = min(max(confidence, 0), 1)
        self.sourceDescription = sourceDescription
    }
}

enum BallLaunchObservationState: String, Codable, Sendable, Equatable {
    /// Only a validated golf-ball-specific detector may emit this state.
    case verifiedGolfBall
    /// A generic Vision trajectory or motion point. Never eligible for a real shot or tracer.
    case genericMotion
    case noLaunchObserved
    case modelUnavailable
    case detectorFailed
}

/// Distinguishes an observed other golfer from an association the detector could not make.
/// A `Bool` cannot represent that distinction safely: explicit non-target evidence is rejected,
/// while unavailable association remains recoverable as uncertain.
enum BallTargetGolferAssociationState: String, Codable, Sendable, Equatable {
    case targetGolfer
    case differentGolfer
    case unavailable
}

/// A temporally stable, detector-attributed launch observation. A neighbouring golfer's ball can
/// be visible in the same source frames, so association is an explicit three-state result.
struct BallLaunchObservation: Codable, Sendable, Equatable {
    var state: BallLaunchObservationState
    var launchTime: TimeInterval?
    var confidence: Double
    var stableDetectionCount: Int
    var targetGolferAssociation: BallTargetGolferAssociationState
    var detectorDescription: String

    /// Compatibility convenience for consumers that only need a positive target association.
    var belongsToTargetGolfer: Bool { targetGolferAssociation == .targetGolfer }

    init(
        state: BallLaunchObservationState,
        launchTime: TimeInterval? = nil,
        confidence: Double = 0,
        stableDetectionCount: Int = 0,
        belongsToTargetGolfer: Bool? = nil,
        targetGolferAssociation: BallTargetGolferAssociationState = .unavailable,
        detectorDescription: String
    ) {
        self.state = state
        self.launchTime = launchTime.map { max(0, $0) }
        self.confidence = min(max(confidence, 0), 1)
        self.stableDetectionCount = max(0, stableDetectionCount)
        if let belongsToTargetGolfer {
            self.targetGolferAssociation = belongsToTargetGolfer ? .targetGolfer : .differentGolfer
        } else {
            self.targetGolferAssociation = targetGolferAssociation
        }
        self.detectorDescription = detectorDescription
    }
}

struct RealShotEvidence: Codable, Sendable, Equatable {
    var targetGolferSwing: TargetGolferSwingImpactEvidence
    var ballLaunch: BallLaunchObservation

    init(targetGolferSwing: TargetGolferSwingImpactEvidence, ballLaunch: BallLaunchObservation) {
        self.targetGolferSwing = targetGolferSwing
        self.ballLaunch = ballLaunch
    }
}

enum RealShotDecisionKind: String, Codable, Sendable, Equatable {
    case accepted
    case uncertain
    case rejected
}

struct RealShotDecision: Codable, Sendable, Equatable {
    var kind: RealShotDecisionKind
    var explanation: String
    var confidence: Double

    init(kind: RealShotDecisionKind, explanation: String, confidence: Double) {
        self.kind = kind
        self.explanation = explanation
        self.confidence = min(max(confidence, 0), 1)
    }
}

/// The non-destructive source range to export after a real shot is accepted.
struct ShotClipPlan: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let acceptedShotID: UUID
    let sourceRange: ReviewTimeRange
    let impactTime: TimeInterval

    init(id: UUID = UUID(), acceptedShotID: UUID, sourceRange: ReviewTimeRange, impactTime: TimeInterval) {
        self.id = id
        self.acceptedShotID = acceptedShotID
        self.sourceRange = sourceRange
        self.impactTime = max(0, impactTime)
    }
}

enum TracerEligibility: String, Codable, Sendable, Equatable {
    case eligible
    case ineligibleUncertainEvidence
    case ineligibleRejected
    case ineligibleModelUnavailable
}

struct AcceptedShot: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let proposal: ShotEventProposal
    let evidence: RealShotEvidence
    let decision: RealShotDecision
    let clipPlan: ShotClipPlan
    let tracerEligibility: TracerEligibility

    /// The validated target-golfer impact timestamp. It is intentionally distinct from the
    /// proposal timestamp, which may originate from a slightly early/late audio or pose signal.
    var impactTime: TimeInterval { clipPlan.impactTime }

    init(
        id: UUID = UUID(),
        proposal: ShotEventProposal,
        evidence: RealShotEvidence,
        decision: RealShotDecision,
        clipPlan: ShotClipPlan,
        tracerEligibility: TracerEligibility = .eligible
    ) {
        self.id = id
        self.proposal = proposal
        self.evidence = evidence
        self.decision = decision
        self.clipPlan = clipPlan
        self.tracerEligibility = tracerEligibility
    }
}

struct UncertainShotMoment: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let proposal: ShotEventProposal
    let evidence: RealShotEvidence
    let decision: RealShotDecision
    let tracerEligibility: TracerEligibility

    init(
        id: UUID = UUID(),
        proposal: ShotEventProposal,
        evidence: RealShotEvidence,
        decision: RealShotDecision,
        tracerEligibility: TracerEligibility
    ) {
        self.id = id
        self.proposal = proposal
        self.evidence = evidence
        self.decision = decision
        self.tracerEligibility = tracerEligibility
    }
}

struct RejectedShotEvent: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let proposal: ShotEventProposal
    let decision: RealShotDecision

    init(id: UUID = UUID(), proposal: ShotEventProposal, decision: RealShotDecision) {
        self.id = id
        self.proposal = proposal
        self.decision = decision
    }
}

/// The three collections are intentionally separate. Only `acceptedShots` may be exported
/// automatically or receive a tracer. Uncertain moments remain recoverable for human review.
struct LongSessionAnalysisResult: Codable, Sendable, Equatable {
    var acceptedShots: [AcceptedShot]
    var uncertainMoments: [UncertainShotMoment]
    var rejectedEvents: [RejectedShotEvent]

    init(
        acceptedShots: [AcceptedShot] = [],
        uncertainMoments: [UncertainShotMoment] = [],
        rejectedEvents: [RejectedShotEvent] = []
    ) {
        self.acceptedShots = acceptedShots
        self.uncertainMoments = uncertainMoments
        self.rejectedEvents = rejectedEvents
    }
}

struct NormalizedPoint: Codable, Sendable, Equatable, Hashable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
    }
}

struct DetectedTrajectory: Codable, Sendable, Equatable {
    var detectedPoints: [NormalizedPoint]
    var projectedPoints: [NormalizedPoint]
    /// Source presentation timestamps for the detected points, when the detector supplies them.
    /// Playback uses these instead of assuming a frame rate or revealing the tracer from a
    /// guessed impact offset.
    var presentationTimes: [TimeInterval]
    /// The screen-space parabola coefficients returned by Vision, not physical flight data.
    var equationCoefficients: [Float]
    var confidence: Double

    init(
        detectedPoints: [NormalizedPoint],
        projectedPoints: [NormalizedPoint],
        presentationTimes: [TimeInterval] = [],
        equationCoefficients: [Float],
        confidence: Double
    ) {
        self.detectedPoints = detectedPoints
        self.projectedPoints = projectedPoints
        self.presentationTimes = presentationTimes
        self.equationCoefficients = equationCoefficients
        self.confidence = min(max(confidence, 0), 1)
    }
}

enum BallFlightEstimateSource: String, Codable, Sendable, Equatable {
    /// No ball-specific track met the evidence threshold, so no tracer can be drawn.
    case unavailable
    /// The visible ball supplied enough points to define the displayed path.
    case observed
    /// Visible points define the launch while the missing flight is completed geometrically.
    case observedAndInferred
    /// The source did not contain a defensible ball track; the path is an adjustable estimate.
    case inferred
}

/// A display-space flight estimate produced from an uploaded video's native frames.
/// Coordinates use a top-left origin so they can be drawn directly over the oriented video.
struct BallFlightEstimate: Codable, Sendable, Equatable {
    var launch: NormalizedPoint
    var apex: NormalizedPoint
    var landing: NormalizedPoint
    var source: BallFlightEstimateSource
    var confidence: Double
    var observedPointCount: Int
    var observedTrajectory: DetectedTrajectory?

    init(
        launch: NormalizedPoint,
        apex: NormalizedPoint,
        landing: NormalizedPoint,
        source: BallFlightEstimateSource,
        confidence: Double,
        observedPointCount: Int,
        observedTrajectory: DetectedTrajectory? = nil
    ) {
        self.launch = launch
        self.apex = apex
        self.landing = landing
        self.source = source
        self.confidence = min(max(confidence, 0), 1)
        self.observedPointCount = max(0, observedPointCount)
        self.observedTrajectory = observedTrajectory
    }

    /// A trajectory is drawable only when observed ball points anchor it. Generic moving-shape
    /// observations and model-free estimates must never become an automatic tracer.
    var isDisplayable: Bool {
        switch source {
        case .observed, .observedAndInferred:
            observedPointCount >= 3 && observedTrajectory != nil
        case .unavailable, .inferred:
            false
        }
    }
}

enum ReviewAnalysisState: Codable, Sendable, Equatable {
    case idle
    case analysing(progress: Double)
    case ready(candidateCount: Int)
    case failed(message: String)

    private enum CodingKeys: String, CodingKey { case type, progress, candidateCount, message }
    private enum Kind: String, Codable { case idle, analysing, ready, failed }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .idle: self = .idle
        case .analysing: self = .analysing(progress: try container.decode(Double.self, forKey: .progress))
        case .ready: self = .ready(candidateCount: try container.decode(Int.self, forKey: .candidateCount))
        case .failed: self = .failed(message: try container.decode(String.self, forKey: .message))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try container.encode(Kind.idle, forKey: .type)
        case let .analysing(progress):
            try container.encode(Kind.analysing, forKey: .type)
            try container.encode(progress, forKey: .progress)
        case let .ready(candidateCount):
            try container.encode(Kind.ready, forKey: .type)
            try container.encode(candidateCount, forKey: .candidateCount)
        case let .failed(message):
            try container.encode(Kind.failed, forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }
}
