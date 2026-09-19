@preconcurrency import AVFoundation
import Foundation

/// The observed point used to start an opt-in point-assisted track. Its timestamp and coordinate
/// remain in the original source, so a later editor never needs to rebase a long recording.
struct ShotAutomaticSeed: Sendable, Equatable {
    let presentationTime: TimeInterval
    let point: NormalizedPoint
    let impactTime: TimeInterval
    let trackingRange: ReviewTimeRange
}

enum ShotAutomaticSeedError: LocalizedError, Sendable, Equatable {
    case noDefensibleSeed

    var errorDescription: String? {
        "Ronde could not find a clear observed ball position in this selected clip."
    }
}

/// Pure selection policy separated from media and Core ML work so the evidence gates can be
/// exercised without private golf footage. The tracker itself never receives a range longer than
/// four seconds, and the returned EdgeTAM interval is at most twenty seconds.
struct ShotAutomaticSeedSelection: Sendable {
    static let maximumDiscoveryDuration: TimeInterval = 20
    static let maximumTrackerDuration: TimeInterval = 4
    static let trackerLeadIn: TimeInterval = 0.04 - (2.0 / 30.0)
    static let minimumTrackerDuration: TimeInterval = 0.8
    static let maximumAnchorAttempts = 2
    static let trackingPreRoll: TimeInterval = 5
    static let trackingPostRoll: TimeInterval = 10
    static let minimumInteriorSeedDelay: TimeInterval = 0.1
    static let maximumSequentialObservationGap: TimeInterval = 0.12

    static func boundedSourceRange(
        requested: ReviewTimeRange,
        sourceDuration: TimeInterval
    ) -> ReviewTimeRange? {
        let range = requested.clipped(to: sourceDuration)
        guard range.duration > 0, range.duration <= maximumDiscoveryDuration else { return nil }
        return range
    }

    static func anchors(
        from candidates: [SwingCandidate],
        in sourceRange: ReviewTimeRange
    ) -> [SwingCandidate] {
        let midpoint = sourceRange.start + (sourceRange.duration / 2)
        return candidates
            .filter { candidate in
                candidate.impactTime.isFinite
                    && candidate.impactTime >= sourceRange.start
                    && candidate.impactTime <= sourceRange.end
                    // WASB retains two source frames before its requested impact. Reject a
                    // boundary candidate rather than reading outside the selected clip.
                    && candidate.impactTime + trackerLeadIn >= sourceRange.start
                    && sourceRange.end - candidate.impactTime >= minimumTrackerDuration
            }
            .sorted { lhs, rhs in
                let leftConfidence = lhs.classification.confidence
                let rightConfidence = rhs.classification.confidence
                if leftConfidence != rightConfidence { return leftConfidence > rightConfidence }
                let leftDistance = abs(lhs.impactTime - midpoint)
                let rightDistance = abs(rhs.impactTime - midpoint)
                if leftDistance != rightDistance { return leftDistance < rightDistance }
                return lhs.impactTime < rhs.impactTime
            }
            .prefix(maximumAnchorAttempts)
            .map { $0 }
    }

    static func trackerDuration(for impactTime: TimeInterval, in sourceRange: ReviewTimeRange) -> TimeInterval? {
        let duration = min(maximumTrackerDuration, sourceRange.end - impactTime)
        guard duration >= minimumTrackerDuration else { return nil }
        return duration
    }

    static func seed(
        from estimate: BallFlightEstimate,
        impactTime: TimeInterval,
        in sourceRange: ReviewTimeRange
    ) -> ShotAutomaticSeed? {
        guard estimate.source == .observed,
              estimate.isDisplayable,
              let trajectory = estimate.observedTrajectory,
              trajectory.detectedPoints.count == trajectory.presentationTimes.count,
              impactTime.isFinite,
              impactTime >= sourceRange.start,
              impactTime <= sourceRange.end else {
            return nil
        }

        let observed = zip(trajectory.detectedPoints, trajectory.presentationTimes)
            .filter { _, time in
                time.isFinite && time >= sourceRange.start && time <= sourceRange.end
            }
            .sorted { lhs, rhs in lhs.1 < rhs.1 }
        guard let firstObserved = observed.first else {
            return nil
        }

        // The first accepted point can be within club/ball separation blur. Prefer an interior
        // observation after impact when both neighbours retain the source's normal cadence. The
        // support score counts the contiguous run, avoiding a seed selected from an isolated
        // late reacquisition. If no such sample exists, the first accepted ball observation is
        // still more honest than inventing a replacement point.
        let seedSample = observed.enumerated()
            .filter { index, sample in
                guard index > 0,
                      index < observed.count - 1,
                      sample.1 >= impactTime + minimumInteriorSeedDelay else {
                    return false
                }
                let previousGap = sample.1 - observed[index - 1].1
                let followingGap = observed[index + 1].1 - sample.1
                return previousGap > 0
                    && followingGap > 0
                    && previousGap <= maximumSequentialObservationGap
                    && followingGap <= maximumSequentialObservationGap
            }
            .max { lhs, rhs in
                let leftSupport = sequentialSupport(around: lhs.offset, in: observed)
                let rightSupport = sequentialSupport(around: rhs.offset, in: observed)
                if leftSupport != rightSupport { return leftSupport < rightSupport }
                return lhs.element.1 > rhs.element.1
            }?
            .element ?? firstObserved

        let trackingStart = max(sourceRange.start, seedSample.1 - trackingPreRoll)
        let trackingEnd = min(
            sourceRange.end,
            seedSample.1 + trackingPostRoll,
            trackingStart + maximumDiscoveryDuration
        )
        guard trackingEnd > trackingStart else { return nil }

        return ShotAutomaticSeed(
            presentationTime: seedSample.1,
            point: seedSample.0,
            impactTime: impactTime,
            trackingRange: ReviewTimeRange(start: trackingStart, duration: trackingEnd - trackingStart)
        )
    }

    private static func sequentialSupport(
        around index: Int,
        in samples: [(NormalizedPoint, TimeInterval)]
    ) -> Int {
        guard samples.indices.contains(index) else { return 0 }
        var lower = index
        while lower > 0,
              samples[lower].1 - samples[lower - 1].1 > 0,
              samples[lower].1 - samples[lower - 1].1 <= maximumSequentialObservationGap {
            lower -= 1
        }
        var upper = index
        while upper < samples.count - 1,
              samples[upper + 1].1 - samples[upper].1 > 0,
              samples[upper + 1].1 - samples[upper].1 <= maximumSequentialObservationGap {
            upper += 1
        }
        return upper - lower + 1
    }
}

/// Finds a source-timed observation to seed point-assisted tracking. Impact-like audio or body
/// motion only bounds the search; a seed is returned exclusively from a displayable WASB observed
/// ball track. Failure deliberately yields no guessed point for the person to correct.
actor ShotAutomaticSeedService {
    private let impactService: ImpactCandidateAnalysisService

    init(impactService: ImpactCandidateAnalysisService = .init()) {
        self.impactService = impactService
    }

    func locate(
        url: URL,
        sourceRange: ReviewTimeRange,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> ShotAutomaticSeed {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isReadable),
              let boundedRange = ShotAutomaticSeedSelection.boundedSourceRange(
                  requested: sourceRange,
                  sourceDuration: max(0, CMTimeGetSeconds(try await asset.load(.duration)))
              ) else {
            throw ShotAutomaticSeedError.noDefensibleSeed
        }

        let candidates = try await impactService.analyse(url: url, sourceRange: boundedRange) {
            progress?(min(0.35, max(0, $0) * 0.35))
        }
        try Task.checkCancellation()

        let anchors = ShotAutomaticSeedSelection.anchors(from: candidates, in: boundedRange)
        guard !anchors.isEmpty else {
            progress?(1)
            throw ShotAutomaticSeedError.noDefensibleSeed
        }

        // The heavy Core ML model must be released before the point-assisted tracker starts.
        // Keeping this instance inside the helper's scope drops its cached model as soon as
        // automatic discovery returns to ReviewModels.
        let seed = try await discoverSeed(
            url: url,
            sourceRange: boundedRange,
            anchors: anchors,
            progress: progress
        )
        if let seed {
            progress?(1)
            return seed
        }

        progress?(1)
        throw ShotAutomaticSeedError.noDefensibleSeed
    }

    private func discoverSeed(
        url: URL,
        sourceRange: ReviewTimeRange,
        anchors: [SwingCandidate],
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> ShotAutomaticSeed? {
        let tracker = WASBGolfBallTrackingService()
        for (index, anchor) in anchors.enumerated() {
            try Task.checkCancellation()
            guard let duration = ShotAutomaticSeedSelection.trackerDuration(
                for: anchor.impactTime,
                in: sourceRange
            ) else {
                continue
            }

            let configuration = WASBGolfBallTrackingConfiguration(
                maximumPostImpactDuration: duration,
                minimumPeakConfidence: 0.08,
                maximumCandidatesPerFrame: 30
            )
            do {
                let estimate = try await tracker.analyse(
                    url: url,
                    impactTime: anchor.impactTime,
                    configuration: configuration,
                    progress: { trackerProgress in
                        let attemptStart = 0.35 + (0.65 * Double(index) / Double(anchors.count))
                        let attemptSpan = 0.65 / Double(anchors.count)
                        progress?(min(1, max(0, attemptStart + (max(0, trackerProgress) * attemptSpan))))
                    }
                )
                try Task.checkCancellation()
                if let seed = ShotAutomaticSeedSelection.seed(
                    from: estimate,
                    impactTime: anchor.impactTime,
                    in: sourceRange
                ) {
                    return seed
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as WASBGolfBallTrackingError where error == .noDefensibleBallTrack {
                continue
            }
        }
        return nil
    }
}
