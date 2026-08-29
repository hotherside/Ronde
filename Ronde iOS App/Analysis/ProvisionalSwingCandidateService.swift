import Foundation

/// Adapter boundary for a future golf-ball-specific Core ML detector. Generic Vision output must
/// be represented as `.genericMotion`, never as `.verifiedGolfBall`. The baseline returns an
/// honest model-unavailable result until a detector has been validated on held-out footage.
protocol GolfBallLaunchDetecting: Sendable {
    func launchObservation(near sourceTime: TimeInterval, in url: URL) async -> BallLaunchObservation
}

/// Associates a nominated event with the golfer this session is reviewing and refines its impact
/// time. The baseline pose analyser only sees a human body; it does not identify the target
/// golfer, so the default adapter returns `.unavailable` and the decision policy fails closed.
protocol TargetGolferAssociating: Sendable {
    func swingImpactEvidence(for proposal: ShotEventProposal, in url: URL) async -> TargetGolferSwingImpactEvidence
}

struct TargetGolferAssociationUnavailable: TargetGolferAssociating {
    func swingImpactEvidence(for proposal: ShotEventProposal, in _: URL) async -> TargetGolferSwingImpactEvidence {
        TargetGolferSwingImpactEvidence(
            state: .unavailable,
            impactTime: proposal.signals.contains(.targetBodyMotion) ? proposal.sourceTime : nil,
            confidence: proposal.signals.contains(.targetBodyMotion) ? proposal.confidence : 0,
            sourceDescription: "No validated target-golfer association model is installed."
        )
    }
}

struct ModelUnavailableGolfBallLaunchDetector: GolfBallLaunchDetecting {
    func launchObservation(near sourceTime: TimeInterval, in _: URL) async -> BallLaunchObservation {
        BallLaunchObservation(
            state: .modelUnavailable,
            launchTime: nil,
            detectorDescription: "No validated golf-ball-specific model is installed."
        )
    }
}

/// Deterministically merges nearby proposal signals without turning their coincidence into a
/// real-shot claim. It preserves the source timestamp of the strongest proposal in each burst.
struct ShotEventProposalDeduplicator: Sendable {
    var mergeWindow: TimeInterval

    init(mergeWindow: TimeInterval = 0.24) {
        self.mergeWindow = max(0, mergeWindow)
    }

    func deduplicate(_ proposals: [ShotEventProposal]) -> [ShotEventProposal] {
        let usable = proposals
            .filter { $0.sourceTime.isFinite }
            .sorted { lhs, rhs in
                lhs.sourceTime == rhs.sourceTime ? lhs.confidence > rhs.confidence : lhs.sourceTime < rhs.sourceTime
            }
        guard let first = usable.first else { return [] }

        var results: [ShotEventProposal] = []
        var cluster = [first]

        for proposal in usable.dropFirst() {
            if proposal.sourceTime - (cluster.last?.sourceTime ?? proposal.sourceTime) <= mergeWindow {
                cluster.append(proposal)
            } else {
                results.append(merged(cluster))
                cluster = [proposal]
            }
        }
        results.append(merged(cluster))
        return results
    }

    private func merged(_ cluster: [ShotEventProposal]) -> ShotEventProposal {
        let representative = cluster.max { lhs, rhs in lhs.confidence < rhs.confidence }!
        return ShotEventProposal(
            sourceTime: representative.sourceTime,
            signals: cluster.reduce(into: Set<ShotEventProposalSignal>()) { $0.formUnion($1.signals) },
            confidence: cluster.map(\.confidence).max() ?? 0
        )
    }
}

struct RealShotDecisionPolicy: Sendable {
    var minimumTargetGolferConfidence: Double
    var minimumBallConfidence: Double
    var minimumStableBallDetections: Int
    var maximumImpactToLaunchOffset: TimeInterval
    var clipPreRoll: TimeInterval
    var clipPostRoll: TimeInterval

    static let defaultPolicy = RealShotDecisionPolicy(
        minimumTargetGolferConfidence: 0.70,
        minimumBallConfidence: 0.70,
        minimumStableBallDetections: 3,
        maximumImpactToLaunchOffset: 0.25,
        clipPreRoll: ImpactClipWindow.defaultPreRoll,
        clipPostRoll: ImpactClipWindow.defaultPostRoll
    )

    func evaluate(proposal: ShotEventProposal, evidence: RealShotEvidence) -> RealShotDecision {
        let target = evidence.targetGolferSwing
        let ball = evidence.ballLaunch

        if target.state == .differentGolfer {
            return .init(
                kind: .rejected,
                explanation: "The swing evidence belongs to a different golfer.",
                confidence: target.confidence
            )
        }
        if ball.state == .genericMotion {
            return .init(
                kind: .rejected,
                explanation: "Generic motion is not a golf-ball observation.",
                confidence: ball.confidence
            )
        }
        if ball.state == .modelUnavailable {
            return .init(
                kind: .uncertain,
                explanation: "A validated golf-ball detector is unavailable, so this moment cannot be accepted automatically.",
                confidence: proposal.confidence
            )
        }
        if ball.state == .verifiedGolfBall,
           ball.targetGolferAssociation == .differentGolfer {
            return .init(
                kind: .rejected,
                explanation: "The verified golf-ball launch belongs to a different golfer.",
                confidence: ball.confidence
            )
        }
        guard target.state == .supported,
              target.confidence >= minimumTargetGolferConfidence else {
            return .init(
                kind: .uncertain,
                explanation: "The target golfer's swing and impact could not be established.",
                confidence: proposal.confidence
            )
        }
        guard ball.state == .verifiedGolfBall,
              ball.targetGolferAssociation == .targetGolfer,
              ball.confidence >= minimumBallConfidence,
              ball.stableDetectionCount >= minimumStableBallDetections,
              let impactTime = target.impactTime,
              let launchTime = ball.launchTime,
              abs(launchTime - impactTime) <= maximumImpactToLaunchOffset else {
            return .init(
                kind: .uncertain,
                explanation: "A target-golfer swing was found, but a stable, time-aligned golf-ball launch was not established.",
                confidence: min(proposal.confidence, max(target.confidence, ball.confidence))
            )
        }
        return .init(
            kind: .accepted,
            explanation: "Target-golfer impact and stable golf-ball launch agree in source time.",
            confidence: min(target.confidence, ball.confidence)
        )
    }

    func clipPlan(
        forAcceptedImpact impactTime: TimeInterval,
        sourceDuration: TimeInterval,
        acceptedShotID: UUID
    ) -> ShotClipPlan {
        let window = ImpactClipWindow(
            impactTime: impactTime,
            preRoll: clipPreRoll,
            postRoll: clipPostRoll
        )
        return ShotClipPlan(
            acceptedShotID: acceptedShotID,
            sourceRange: window.clipped(to: sourceDuration),
            impactTime: impactTime
        )
    }
}

/// Long-recording coordinator. It records raw events as proposals, then makes a fail-closed
/// decision. Its production baseline deliberately has no ball model, so it can return uncertain
/// moments but cannot silently create a shot clip or enable a tracer.
actor LongSessionAnalysisService {
    private let audioService: AudioImpactAnalysisService
    private let bodyMotionService: BodyMotionAnalysisService
    private let targetGolferAssociator: any TargetGolferAssociating
    private let ballDetector: any GolfBallLaunchDetecting
    private let deduplicator: ShotEventProposalDeduplicator
    private let decisionPolicy: RealShotDecisionPolicy

    init(
        audioService: AudioImpactAnalysisService = .init(),
        bodyMotionService: BodyMotionAnalysisService = .init(),
        targetGolferAssociator: any TargetGolferAssociating = TargetGolferAssociationUnavailable(),
        ballDetector: any GolfBallLaunchDetecting = ModelUnavailableGolfBallLaunchDetector(),
        deduplicator: ShotEventProposalDeduplicator = .init(),
        decisionPolicy: RealShotDecisionPolicy = .defaultPolicy
    ) {
        self.audioService = audioService
        self.bodyMotionService = bodyMotionService
        self.targetGolferAssociator = targetGolferAssociator
        self.ballDetector = ballDetector
        self.deduplicator = deduplicator
        self.decisionPolicy = decisionPolicy
    }

    func analyse(
        url: URL,
        sourceDuration: TimeInterval,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async -> LongSessionAnalysisResult {
        let audio = (try? await audioService.analyse(url: url) { progress?($0 * 0.45) }) ?? []
        let body = (try? await bodyMotionService.analyse(url: url) { progress?(0.45 + ($0 * 0.45)) }) ?? []
        let proposals = deduplicator.deduplicate(
            audio.map {
                ShotEventProposal(sourceTime: $0.impactTime, signals: [.impactLikeAudio], confidence: $0.classification.confidence)
            } + body.map {
                ShotEventProposal(sourceTime: $0.impactTime, signals: [.targetBodyMotion], confidence: $0.classification.confidence)
            }
        )
        let associator = targetGolferAssociator
        let detector = ballDetector
        let result = await classify(proposals: proposals, sourceDuration: sourceDuration) { proposal in
            let target = await associator.swingImpactEvidence(for: proposal, in: url)
            let ball = await detector.launchObservation(near: proposal.sourceTime, in: url)
            return RealShotEvidence(targetGolferSwing: target, ballLaunch: ball)
        }
        progress?(1)
        return result
    }

    func classify(
        proposals: [ShotEventProposal],
        sourceDuration: TimeInterval,
        evidenceForProposal: @Sendable (ShotEventProposal) async -> RealShotEvidence
    ) async -> LongSessionAnalysisResult {
        var result = LongSessionAnalysisResult()
        for proposal in deduplicator.deduplicate(proposals) {
            let evidence = await evidenceForProposal(proposal)
            let decision = decisionPolicy.evaluate(proposal: proposal, evidence: evidence)
            switch decision.kind {
            case .accepted:
                guard let acceptedImpactTime = evidence.targetGolferSwing.impactTime else {
                    result.uncertainMoments.append(UncertainShotMoment(
                        proposal: proposal,
                        evidence: evidence,
                        decision: .init(
                            kind: .uncertain,
                            explanation: "The accepted decision did not contain a validated impact timestamp.",
                            confidence: decision.confidence
                        ),
                        tracerEligibility: .ineligibleUncertainEvidence
                    ))
                    continue
                }
                let acceptedID = UUID()
                let plan = decisionPolicy.clipPlan(
                    forAcceptedImpact: acceptedImpactTime,
                    sourceDuration: sourceDuration,
                    acceptedShotID: acceptedID
                )
                result.acceptedShots.append(AcceptedShot(
                    id: acceptedID,
                    proposal: proposal,
                    evidence: evidence,
                    decision: decision,
                    clipPlan: plan
                ))
            case .uncertain:
                let eligibility: TracerEligibility = evidence.ballLaunch.state == .modelUnavailable
                    ? .ineligibleModelUnavailable
                    : .ineligibleUncertainEvidence
                result.uncertainMoments.append(UncertainShotMoment(
                    proposal: proposal,
                    evidence: evidence,
                    decision: decision,
                    tracerEligibility: eligibility
                ))
            case .rejected:
                result.rejectedEvents.append(RejectedShotEvent(proposal: proposal, decision: decision))
            }
        }
        return result
    }
}

/// Evidence fusion used before a trained golf action model exists.
/// It can only produce a reviewable uncertain candidate, never a real-shot/practice-swing claim.
struct ProvisionalSwingCandidateService: Sendable {
    struct EvidenceInput: Sendable, Equatable {
        var impactTime: TimeInterval
        var hasTrajectory: Bool
        var hasBodyMotion: Bool
        var hasAudioTransient: Bool
        var trajectory: DetectedTrajectory?
    }

    func candidate(from input: EvidenceInput) -> SwingCandidate? {
        let evidence = Set([
            input.hasTrajectory ? SwingEvidence.trajectory : nil,
            input.hasBodyMotion ? SwingEvidence.bodyMotion : nil,
            input.hasAudioTransient ? SwingEvidence.audioTransient : nil
        ].compactMap { $0 })

        // A trajectory alone can be another golfer, a bird, or visual noise; body motion alone is a practice swing.
        // Require two independent sources before creating an automatic candidate.
        guard evidence.count >= 2 else { return nil }
        let confidence = min(0.85, 0.30 + (Double(evidence.count) * 0.20))
        return SwingCandidate(
            impactTime: input.impactTime,
            classification: .provisional(
                confidence: confidence,
                explanation: "Multiple on-device signals suggest a swing event. Confirm before treating it as a shot."
            ),
            evidence: evidence,
            trajectory: input.trajectory
        )
    }
}
