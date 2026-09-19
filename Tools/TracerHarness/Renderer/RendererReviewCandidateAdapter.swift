import Foundation

// Build-only adapter for the renderer oracle. The production ReviewCandidate is declared in
// Features/ReviewModels.swift, whose UI/container dependencies are intentionally not pulled into
// this external macOS build. These are only the stored fields consumed by production
// ShotVideoTrace.init(candidate:mode:); no rendering, fitting, timing or geometry is duplicated.
struct ReviewCandidate {
    let impactTime: TimeInterval
    let evidenceAnchoredPath: EvidenceAnchoredFlightPath?
    let assistedTracer: AssistedTracerPath?
    var seededTrace: SeededModelTrace? = nil
}

extension ReviewCandidate {
    init(
        ordinal: Int,
        impactTime: TimeInterval,
        sourceDuration: TimeInterval,
        classification: ShotClassification,
        confidence: ConfidenceLevel,
        evidence: [String],
        decision: CandidateDecision,
        tracerAvailable: Bool,
        evidenceAnchoredPath: EvidenceAnchoredFlightPath?,
        tracerSource: BallFlightEstimateSource,
        tracerConfidence: Double,
        observedTracerPointCount: Int,
        usesFullSourceRange: Bool
    ) {
        self.init(impactTime: impactTime, evidenceAnchoredPath: evidenceAnchoredPath, assistedTracer: nil)
    }
}

enum ShotClassification {
    case likelyShot
}

enum CandidateDecision {
    case kept
}

enum ConfidenceLevel {
    case high
}

struct AssistedTracerPath {
    struct Point { let x: Double; let y: Double }
    let launch: Point
    let apex: Point
    let landing: Point
    var drawnPoints: [Point]? = nil
}
