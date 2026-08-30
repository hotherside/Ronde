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

/// One detector-attributed ball position at its original source presentation time.
struct TimedTrajectorySample: Sendable, Equatable, Hashable {
    let point: NormalizedPoint
    let presentationTime: TimeInterval
}

/// Source-time trajectory geometry shared by review playback and traced-video export.
///
/// The renderer may smooth between detector observations, but time remains authoritative: a
/// visible prefix never includes a sample after the requested source time. This prevents the
/// tracer from leading the ball when point spacing changes under perspective.
struct TimedTrajectoryPath: Sendable, Equatable {
    let samples: [TimedTrajectorySample]

    init?(points: [NormalizedPoint], presentationTimes: [TimeInterval]) {
        guard points.count >= 2,
              points.count == presentationTimes.count,
              presentationTimes.allSatisfy(\.isFinite) else {
            return nil
        }
        for index in presentationTimes.indices.dropFirst() {
            guard presentationTimes[index] > presentationTimes[index - 1] else { return nil }
        }
        samples = zip(points, presentationTimes).map {
            TimedTrajectorySample(point: $0.0, presentationTime: $0.1)
        }
    }

    var startTime: TimeInterval { samples[0].presentationTime }
    var endTime: TimeInterval { samples[samples.count - 1].presentationTime }
    var duration: TimeInterval { max(0, endTime - startTime) }

    /// Leaves the source ball unobscured by keeping the rendered stroke fractionally behind the
    /// latest detector sample. The lag follows the track's own sampling interval and is capped so
    /// high-frame-rate and sparse tracks retain the same causal, trail-like treatment.
    var suggestedTrailLag: TimeInterval {
        let intervals = samples.indices.dropFirst().map {
            samples[$0].presentationTime - samples[$0 - 1].presentationTime
        }.sorted()
        guard !intervals.isEmpty else { return 0 }
        let median: TimeInterval
        let middle = intervals.count / 2
        if intervals.count.isMultiple(of: 2) {
            median = (intervals[middle - 1] + intervals[middle]) / 2
        } else {
            median = intervals[middle]
        }
        return min(0.050, max(1.0 / 120.0, median * 0.55))
    }

    func visibleTrailSamples(
        at presentationTime: TimeInterval,
        smoothingSubdivisions: Int = 4
    ) -> [TimedTrajectorySample] {
        visibleSamples(
            at: presentationTime - suggestedTrailLag,
            smoothingSubdivisions: smoothingSubdivisions
        )
    }

    /// Returns a path that ends exactly at the requested source time. The final partial segment is
    /// interpolated in time, so no future detector point can move the visible head ahead of video.
    func visibleSamples(at presentationTime: TimeInterval, smoothingSubdivisions: Int = 4) -> [TimedTrajectorySample] {
        guard presentationTime >= startTime else { return [] }
        if presentationTime >= endTime {
            return smoothedSamples(subdivisions: smoothingSubdivisions)
        }

        var visible = samples.prefix { $0.presentationTime <= presentationTime }.map { $0 }
        guard let previous = visible.last,
              let next = samples.first(where: { $0.presentationTime > presentationTime }) else {
            return smoothed(samples: visible, subdivisions: smoothingSubdivisions)
        }
        let interval = max(0.000_001, next.presentationTime - previous.presentationTime)
        let fraction = min(1, max(0, (presentationTime - previous.presentationTime) / interval))
        visible.append(TimedTrajectorySample(
            point: Self.interpolate(from: previous.point, to: next.point, fraction: fraction),
            presentationTime: presentationTime
        ))
        return smoothed(samples: visible, subdivisions: smoothingSubdivisions)
    }

    func position(at presentationTime: TimeInterval) -> NormalizedPoint? {
        guard presentationTime >= startTime else { return nil }
        guard presentationTime < endTime else { return samples.last?.point }
        guard let nextIndex = samples.firstIndex(where: { $0.presentationTime > presentationTime }),
              nextIndex > 0 else {
            return samples.first?.point
        }
        let previous = samples[nextIndex - 1]
        let next = samples[nextIndex]
        let interval = max(0.000_001, next.presentationTime - previous.presentationTime)
        return Self.interpolate(
            from: previous.point,
            to: next.point,
            fraction: (presentationTime - previous.presentationTime) / interval
        )
    }

    func smoothedSamples(subdivisions: Int = 4) -> [TimedTrajectorySample] {
        smoothed(samples: samples, subdivisions: subdivisions)
    }

    /// Values for a Core Animation `strokeEnd` keyframe. Key times are source-time fractions;
    /// values are cumulative screen-path fractions. Their non-linear mapping is what keeps a
    /// constant media clock attached to a perspective-compressed ball path.
    func strokeRevealKeyframes(subdivisions: Int = 4) -> (samples: [TimedTrajectorySample], keyTimes: [Double], strokeValues: [Double]) {
        let rendered = smoothedSamples(subdivisions: subdivisions)
        guard rendered.count >= 2,
              let first = rendered.first,
              let last = rendered.last,
              last.presentationTime > first.presentationTime else {
            return (rendered, [0, 1], [0, 1])
        }

        var cumulative = [Double](repeating: 0, count: rendered.count)
        for index in 1..<rendered.count {
            let dx = rendered[index].point.x - rendered[index - 1].point.x
            let dy = rendered[index].point.y - rendered[index - 1].point.y
            cumulative[index] = cumulative[index - 1] + hypot(dx, dy)
        }
        let totalLength = max(0.000_001, cumulative.last ?? 0)
        let timeDuration = last.presentationTime - first.presentationTime
        return (
            rendered,
            rendered.map { ($0.presentationTime - first.presentationTime) / timeDuration },
            cumulative.map { $0 / totalLength }
        )
    }

    func presentationTime(for point: NormalizedPoint) -> TimeInterval? {
        samples.first(where: { $0.point == point })?.presentationTime
    }

    private func smoothed(
        samples input: [TimedTrajectorySample],
        subdivisions: Int
    ) -> [TimedTrajectorySample] {
        guard input.count >= 3 else { return input }
        let steps = max(1, subdivisions)
        var result: [TimedTrajectorySample] = [input[0]]
        result.reserveCapacity(((input.count - 1) * steps) + 1)

        for segment in 0..<(input.count - 1) {
            let p0 = input[max(0, segment - 1)].point
            let p1 = input[segment].point
            let p2 = input[segment + 1].point
            let p3 = input[min(input.count - 1, segment + 2)].point
            let startTime = input[segment].presentationTime
            let endTime = input[segment + 1].presentationTime

            for step in 1...steps {
                let fraction = Double(step) / Double(steps)
                let point = Self.boundedCatmullRom(
                    p0: p0,
                    p1: p1,
                    p2: p2,
                    p3: p3,
                    fraction: fraction
                )
                result.append(TimedTrajectorySample(
                    point: point,
                    presentationTime: startTime + ((endTime - startTime) * fraction)
                ))
            }
        }
        return result
    }

    private static func interpolate(
        from start: NormalizedPoint,
        to end: NormalizedPoint,
        fraction: Double
    ) -> NormalizedPoint {
        let t = min(1, max(0, fraction))
        return NormalizedPoint(
            x: start.x + ((end.x - start.x) * t),
            y: start.y + ((end.y - start.y) * t)
        )
    }

    /// A modest, renderer-only Catmull-Rom interpolation. Bounding each interval prevents sparse
    /// detector points from creating loops or overshoot that would look like invented evidence.
    private static func boundedCatmullRom(
        p0: NormalizedPoint,
        p1: NormalizedPoint,
        p2: NormalizedPoint,
        p3: NormalizedPoint,
        fraction: Double
    ) -> NormalizedPoint {
        let t = min(1, max(0, fraction))
        let t2 = t * t
        let t3 = t2 * t
        func coordinate(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
            0.5 * (
                (2 * b)
                    + ((-a + c) * t)
                    + (((2 * a) - (5 * b) + (4 * c) - d) * t2)
                    + ((-a + (3 * b) - (3 * c) + d) * t3)
            )
        }
        let padding = 0.006
        let minimumX = max(0, min(p1.x, p2.x) - padding)
        let maximumX = min(1, max(p1.x, p2.x) + padding)
        let minimumY = max(0, min(p1.y, p2.y) - padding)
        let maximumY = min(1, max(p1.y, p2.y) + padding)
        return NormalizedPoint(
            x: min(maximumX, max(minimumX, coordinate(p0.x, p1.x, p2.x, p3.x))),
            y: min(maximumY, max(minimumY, coordinate(p0.y, p1.y, p2.y, p3.y)))
        )
    }
}

/// A deliberately broad carry estimate from an uncalibrated single-camera fit.
///
/// A range is used instead of a precise value because multiple launch speeds, camera distances
/// and elevations can explain the same short two-dimensional track. It is presentation guidance,
/// not launch-monitor measurement.
struct EstimatedCarryDistance: Codable, Sendable, Equatable, Hashable {
    let lowerMetres: Int
    let upperMetres: Int

    init(lowerMetres: Int, upperMetres: Int) {
        let lower = max(0, min(lowerMetres, upperMetres))
        let upper = max(lower, max(lowerMetres, upperMetres))
        self.lowerMetres = lower
        self.upperMetres = upper
    }

    var displayText: String {
        lowerMetres == upperMetres
            ? "~\(lowerMetres) m"
            : "\(lowerMetres)–\(upperMetres) m"
    }
}

/// A drawable automatic tracer split into the evidence that was actually seen in source frames
/// and distinctly styled estimated geometry before and after it. A verified mid-air fragment may
/// be fitted back to impact and forward through apex and landing, but none of those inferred
/// positions become observed evidence.
struct EvidenceAnchoredFlightPath: Codable, Sendable, Equatable, Hashable {
    /// Estimated geometry from impact to the first detector-attributed point.
    let inferredLaunchConnector: [NormalizedPoint]
    /// Screen-space points from detector-attributed source frames, in chronological order.
    let observedPoints: [NormalizedPoint]
    /// Presentation geometry after `observedPoints.last`. The shared endpoint is exposed through
    /// `inferredSegmentPoints`, so renderers can use a different visual treatment without a seam.
    let inferredContinuation: [NormalizedPoint]
    /// Source presentation timestamps matching `observedPoints`, when supplied by the tracker.
    /// The value is empty rather than guessed when an older detector does not provide them.
    let observedPresentationTimes: [TimeInterval]
    /// Source-time span from impact to the first observed point.
    let inferredLaunchPresentationDuration: TimeInterval
    /// Animation-only duration of the inferred segment. It is not a physical flight-time claim.
    let inferredPresentationDuration: TimeInterval
    /// Estimated total time from impact to the modelled landing.
    let estimatedFlightDuration: TimeInterval?
    /// Broad, uncalibrated carry range derived from similarly plausible model fits.
    let estimatedCarry: EstimatedCarryDistance?
    /// Normalised image-space fit error for diagnostics and confidence presentation.
    let fitError: Double?
    let confidence: Double

    init?(
        inferredLaunchConnector: [NormalizedPoint] = [],
        observedPoints: [NormalizedPoint],
        inferredContinuation: [NormalizedPoint] = [],
        observedPresentationTimes: [TimeInterval] = [],
        inferredLaunchPresentationDuration: TimeInterval = 0,
        inferredPresentationDuration: TimeInterval = 0.36,
        estimatedFlightDuration: TimeInterval? = nil,
        estimatedCarry: EstimatedCarryDistance? = nil,
        fitError: Double? = nil,
        confidence: Double
    ) {
        guard observedPoints.count >= 3,
              inferredLaunchConnector.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              observedPoints.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              inferredContinuation.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              (observedPresentationTimes.isEmpty || observedPresentationTimes.count == observedPoints.count),
              observedPresentationTimes.allSatisfy(\.isFinite),
              estimatedFlightDuration.map({ $0.isFinite && $0 > 0 }) ?? true,
              fitError.map({ $0.isFinite && $0 >= 0 }) ?? true else {
            return nil
        }
        self.inferredLaunchConnector = inferredLaunchConnector
        self.observedPoints = observedPoints
        self.inferredContinuation = inferredContinuation
        self.observedPresentationTimes = observedPresentationTimes
        self.inferredLaunchPresentationDuration = max(0, inferredLaunchPresentationDuration)
        self.inferredPresentationDuration = max(0.01, inferredPresentationDuration)
        self.estimatedFlightDuration = estimatedFlightDuration
        self.estimatedCarry = estimatedCarry
        self.fitError = fitError
        self.confidence = min(max(confidence, 0), 1)
    }

    var source: BallFlightEstimateSource {
        inferredLaunchConnector.isEmpty && inferredContinuation.isEmpty ? .observed : .observedAndInferred
    }

    var hasInferredGeometry: Bool { !inferredLaunchConnector.isEmpty || !inferredContinuation.isEmpty }

    var inferredLaunchSegmentPoints: [NormalizedPoint] {
        guard let firstObserved = observedPoints.first, !inferredLaunchConnector.isEmpty else { return [] }
        return inferredLaunchConnector + [firstObserved]
    }

    /// The inferred segment includes the final observed point solely to connect the strokes. That
    /// shared point remains observed evidence and must not be counted as inferred flight.
    var inferredSegmentPoints: [NormalizedPoint] {
        guard let lastObserved = observedPoints.last, !inferredContinuation.isEmpty else { return [] }
        return [lastObserved] + inferredContinuation
    }

    var allDisplayPoints: [NormalizedPoint] {
        inferredLaunchConnector + observedPoints + inferredContinuation
    }

    /// Highest point of the complete displayed path. This is an estimated image-space apex when
    /// it lies outside the observed segment.
    var apexPoint: NormalizedPoint? {
        allDisplayPoints.min { $0.y < $1.y }
    }

    /// The highest point of the inferred presentation curve. In top-left video coordinates a
    /// smaller `y` is higher. It is explicitly inference, never a measured physical apex.
    var inferredApex: NormalizedPoint? {
        inferredContinuation.min { $0.y < $1.y }
    }

    /// The final bounded image-space point of the inferred presentation curve. It is not a
    /// measured landing location. A separate broad, uncalibrated carry range may come from the
    /// perspective fit, but this normalised screen point is never a distance measurement.
    var inferredLanding: NormalizedPoint? {
        inferredContinuation.last
    }

    var observedDuration: TimeInterval? {
        guard let first = observedPresentationTimes.first,
              let last = observedPresentationTimes.last,
              last >= first else {
            return nil
        }
        return last - first
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
