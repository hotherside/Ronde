import Foundation

/// Produces human-reviewable markers only. Audio and body motion are peers: either may nominate
/// a moment, and nearby signals are merged. Neither an audio-only nor a body-only marker can be
/// promoted to an automatic real shot, clip, or tracer.
actor ImpactCandidateAnalysisService {
    private let audioService: AudioImpactAnalysisService
    private let bodyMotionService: BodyMotionAnalysisService

    init(
        audioService: AudioImpactAnalysisService = .init(),
        bodyMotionService: BodyMotionAnalysisService = .init()
    ) {
        self.audioService = audioService
        self.bodyMotionService = bodyMotionService
    }

    func analyse(
        url: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [SwingCandidate] {
        let audioCandidates: [SwingCandidate]
        do {
            audioCandidates = try await audioService.analyse(url: url) { audioProgress in
                progress?(audioProgress * 0.5)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            audioCandidates = []
        }

        let bodyCandidates: [SwingCandidate]
        do {
            bodyCandidates = try await bodyMotionService.analyse(url: url) { bodyProgress in
                progress?(0.5 + (bodyProgress * 0.5))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            bodyCandidates = []
        }

        let proposals = ShotEventProposalDeduplicator().deduplicate(
            audioCandidates.map {
                ShotEventProposal(
                    sourceTime: $0.impactTime,
                    signals: [.impactLikeAudio],
                    confidence: $0.classification.confidence
                )
            } + bodyCandidates.map {
                ShotEventProposal(
                    sourceTime: $0.impactTime,
                    signals: [.targetBodyMotion],
                    confidence: $0.classification.confidence
                )
            }
        )
        progress?(1)
        return proposals.map { proposal in
            SwingCandidate(
                impactTime: proposal.sourceTime,
                classification: .provisional(
                    confidence: proposal.confidence,
                    explanation: "This is a review moment only. A validated target-golfer swing and golf-ball launch are required before automatic clipping or tracer creation."
                ),
                evidence: Set(proposal.signals.compactMap { signal in
                    switch signal {
                    case .impactLikeAudio: .audioTransient
                    case .targetBodyMotion: .bodyMotion
                    case .genericMotion: .trajectory
                    case .manual: .manual
                    }
                })
            )
        }
    }
}
