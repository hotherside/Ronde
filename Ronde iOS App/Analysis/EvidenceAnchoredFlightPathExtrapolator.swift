import Foundation

/// Builds a complete, image-space continuation after a verified source-frame ball track ends.
///
/// The continuation is a damped ballistic presentation curve. Its launch point and tangent come
/// from observed position, velocity and presentation timestamps; its apex and bounded landing are
/// explicitly inferred screen geometry. It never produces yards, carry, height or an assertion
/// that the ball was observed after the final tracked source frame.
struct EvidenceAnchoredFlightPathExtrapolator: Sendable {
    struct Configuration: Sendable, Equatable {
        var continuationPointCount: Int
        var minimumPresentationDuration: TimeInterval
        var maximumContinuationDuration: TimeInterval
        var minimumApexRise: Double
        var maximumApexRise: Double
        var minimumLandingDrop: Double
        var frameInset: Double
        var horizontalVelocityDamping: Double
        var horizontalDistanceDamping: Double

        static let automaticTracer = Configuration(
            continuationPointCount: 24,
            minimumPresentationDuration: 0.42,
            maximumContinuationDuration: 1.60,
            minimumApexRise: 0.055,
            maximumApexRise: 0.36,
            minimumLandingDrop: 0.13,
            frameInset: 0.035,
            horizontalVelocityDamping: 0.72,
            horizontalDistanceDamping: 0.68
        )
    }

    let configuration: Configuration

    init(configuration: Configuration = .automaticTracer) {
        self.configuration = configuration
    }

    func path(from estimate: BallFlightEstimate) -> EvidenceAnchoredFlightPath? {
        guard estimate.source == .observed || estimate.source == .observedAndInferred,
              estimate.observedPointCount >= 3,
              let trajectory = estimate.observedTrajectory,
              trajectory.detectedPoints.count >= 3 else {
            return nil
        }

        let observed = trajectory.detectedPoints
        let timestamps = Self.usableTimestamps(trajectory.presentationTimes, matching: observed.count)
        let continuation = inferContinuation(from: observed, timestamps: timestamps)
        return EvidenceAnchoredFlightPath(
            observedPoints: observed,
            inferredContinuation: continuation?.points ?? [],
            observedPresentationTimes: timestamps,
            inferredPresentationDuration: continuation?.presentationDuration ?? 0.36,
            confidence: estimate.confidence
        )
    }

    private func inferContinuation(
        from points: [NormalizedPoint],
        timestamps: [TimeInterval]
    ) -> InferredContinuation? {
        guard points.count >= 3,
              timestamps.count == points.count,
              let last = points.last else { return nil }

        let launch = points[0]
        let p1 = points[points.count - 2]
        let p2 = last
        let interval1 = Self.interval(from: timestamps, at: points.count - 2)
        let interval2 = Self.interval(from: timestamps, at: points.count - 1)
        let referenceInterval = max(0.001, (interval1 + interval2) / 2)
        let observedSpan = max(referenceInterval, timestamps[timestamps.count - 1] - timestamps[0])
        let velocity2 = Vector(
            x: (p2.x - p1.x) / interval2,
            y: (p2.y - p1.y) / interval2
        )
        let observedVerticalVelocity = (p2.y - launch.y) / observedSpan
        // The current direction must still be rising in top-left screen coordinates. If a track
        // loses the ball after it has already descended, Ronde retains the observed stroke rather
        // than inventing a second apex or a landing from stale motion.
        let verticalVelocity = (velocity2.y * 0.72) + (observedVerticalVelocity * 0.28)
        guard velocity2.magnitude > 0.001, verticalVelocity < -0.012 else { return nil }

        let observedRise = max(0, launch.y - p2.y)
        let landingY = boundedLandingY(from: launch, current: p2, observedRise: observedRise)
        let landingDrop = landingY - p2.y
        guard landingDrop > 0.02 else { return nil }

        let desiredRise = min(
            max(configuration.minimumApexRise, max(observedRise * 0.86, abs(verticalVelocity) * observedSpan * 0.9)),
            min(configuration.maximumApexRise, p2.y - configuration.frameInset)
        )
        guard desiredRise > 0.012 else { return nil }

        // A parabola with y(0) = current point, y(1) = bounded landing and a vertex whose rise
        // follows the observed segment. Solving for the vertex parameter preserves a true later
        // apex. The PTS-derived vertical velocity determines presentation duration and tangent.
        let apexProgress = vertexProgress(apexRise: desiredRise, landingDrop: landingDrop)
        let verticalAcceleration = landingDrop / max(0.001, 1 - (2 * apexProgress))
        let verticalSlope = -2 * verticalAcceleration * apexProgress
        let rawDuration = verticalSlope / verticalVelocity
        let duration = min(
            configuration.maximumContinuationDuration,
            max(configuration.minimumPresentationDuration, rawDuration)
        )

        let dampedHorizontalSlope = velocity2.x
            * duration
            * configuration.horizontalVelocityDamping
        let landingX = bounded(
            p2.x + (dampedHorizontalSlope * configuration.horizontalDistanceDamping),
            lower: configuration.frameInset,
            upper: 1 - configuration.frameInset
        )
        let horizontalAcceleration = landingX - p2.x - dampedHorizontalSlope

        let count = max(8, configuration.continuationPointCount)
        var progressValues = (1...count).map { Double($0) / Double(count) }
        // Include the mathematically exact apex so renderers and tests never rely on sampling luck.
        progressValues.append(apexProgress)
        progressValues.sort()

        var result: [NormalizedPoint] = []
        result.reserveCapacity(progressValues.count)
        for progress in progressValues {
            let rawX = p2.x + (dampedHorizontalSlope * progress) + (horizontalAcceleration * progress * progress)
            let rawY = p2.y + (verticalSlope * progress) + (verticalAcceleration * progress * progress)
            result.append(NormalizedPoint(
                x: bounded(rawX, lower: configuration.frameInset, upper: 1 - configuration.frameInset),
                y: bounded(rawY, lower: configuration.frameInset, upper: 1 - configuration.frameInset)
            ))
        }
        return InferredContinuation(points: result, presentationDuration: duration)
    }

    private func boundedLandingY(
        from launch: NormalizedPoint,
        current: NormalizedPoint,
        observedRise: Double
    ) -> Double {
        let candidate = max(
            launch.y,
            current.y + max(configuration.minimumLandingDrop, observedRise * 1.08)
        )
        return bounded(candidate, lower: current.y + 0.02, upper: 1 - configuration.frameInset)
    }

    private func vertexProgress(apexRise: Double, landingDrop: Double) -> Double {
        // For y(t) = at² + bt + c, this solves apexRise / landingDrop = t² / (1 - 2t).
        let ratio = max(0.001, apexRise / max(0.001, landingDrop))
        return min(0.46, max(0.12, sqrt((ratio * ratio) + ratio) - ratio))
    }

    private func bounded(_ value: Double, lower: Double, upper: Double) -> Double {
        min(upper, max(lower, value))
    }

    private static func usableTimestamps(_ timestamps: [TimeInterval], matching count: Int) -> [TimeInterval] {
        guard timestamps.count == count,
              timestamps.allSatisfy(\.isFinite),
              zip(timestamps, timestamps.dropFirst()).allSatisfy({ $0 <= $1 }) else {
            return []
        }
        return timestamps
    }

    private static func interval(from timestamps: [TimeInterval], at index: Int) -> TimeInterval {
        guard index > 0, timestamps.count > index else { return 0 }
        return max(0.001, timestamps[index] - timestamps[index - 1])
    }

    private struct InferredContinuation: Sendable {
        let points: [NormalizedPoint]
        let presentationDuration: TimeInterval
    }
}

private struct Vector: Sendable {
    var x: Double
    var y: Double

    var magnitude: Double { hypot(x, y) }

}
