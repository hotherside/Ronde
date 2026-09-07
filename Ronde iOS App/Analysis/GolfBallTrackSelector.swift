import Foundation

/// Selects decoded frames on presentation time rather than on a container's nominal frame rate.
///
/// The reader still decodes every source sample sequentially, but only accepted samples enter the
/// model window. This keeps the model's temporal context close to the configured cadence for
/// 24, 30, 60 and 120 fps uploads without inventing frames that were not present in the source.
struct PresentationTimestampFrameSampler: Sendable, Equatable {
    private let cadence: TimeInterval
    private let acceptanceTolerance: TimeInterval
    private var nextEligibleTime: TimeInterval
    private var lastAcceptedTime: TimeInterval?

    init(startTime: TimeInterval, cadence: TimeInterval) {
        self.cadence = max(1.0 / 120.0, cadence)
        // Real iPhone footage commonly reports a measured frame rate just above the nominal
        // 30 fps capture rate. Requiring the next sample to land within one microsecond of the
        // target made every second 30.08 fps frame ineligible, collapsing analysis to about
        // 15 fps. A tightly bounded tolerance keeps those source frames while still reducing
        // 50, 60, 120 and 240 fps footage to a practical analysis cadence.
        acceptanceTolerance = min(self.cadence * 0.06, 0.002)
        nextEligibleTime = max(0, startTime)
    }

    mutating func accepts(presentationTime: TimeInterval) -> Bool {
        guard presentationTime.isFinite, presentationTime >= 0,
              lastAcceptedTime.map({ presentationTime > $0 }) ?? true else { return false }
        // Follow a near-nominal source without accumulating its tiny clock difference. Otherwise
        // retain the cadence phase: resetting it to each late frame halves sources such as 32 fps.
        let followsSourceCadence = lastAcceptedTime.map {
            abs(presentationTime - $0 - cadence) <= acceptanceTolerance
        } ?? false
        guard followsSourceCadence || presentationTime + acceptanceTolerance >= nextEligibleTime else {
            return false
        }
        if followsSourceCadence {
            nextEligibleTime = presentationTime + cadence
        } else {
            let intervals = max(1, floor((presentationTime + acceptanceTolerance - nextEligibleTime) / cadence) + 1)
            nextEligibleTime += intervals * cadence
        }
        lastAcceptedTime = presentationTime
        return true
    }
}

struct GolfBallDetectionCandidate: Sendable, Equatable {
    /// A decoder-local grouping key. It is never used as a measure of elapsed time.
    let frameIndex: Int
    /// The source presentation timestamp for this observation.
    let presentationTime: TimeInterval
    let point: NormalizedPoint
    let confidence: Double

    init(
        frameIndex: Int,
        presentationTime: TimeInterval,
        point: NormalizedPoint,
        confidence: Double
    ) {
        self.frameIndex = frameIndex
        self.presentationTime = max(0, presentationTime)
        self.point = point
        self.confidence = min(max(confidence, 0), 1)
    }
}

struct GolfBallTrack: Sendable, Equatable {
    let detections: [GolfBallDetectionCandidate]
    let confidence: Double
}

/// Links detector peaks into a single, motion-consistent ball track. This is intentionally a
/// single-object tracker rather than a general multi-object tracker: a candidate must move away
/// from the strike area across consecutive source *timestamps*, maintain direction and cover
/// enough of the post-impact window to be eligible for display.
enum GolfBallTrackSelector {
    private static let maximumObservationGap: TimeInterval = 0.115
    private static let minimumTrackDuration: TimeInterval = 0.16
    private static let coverageInterval: TimeInterval = 0.05

    private struct Beam {
        var detections: [GolfBallDetectionCandidate]
        var score: Double
    }

    static func select(
        from candidates: [GolfBallDetectionCandidate],
        impactTime: TimeInterval,
        minimumDetectionCount: Int = 5
    ) -> GolfBallTrack? {
        // frameIndex exists only to keep all peaks from one decoded frame together. Every
        // acceptance and quality threshold below uses the source PTS, not frame-number gaps.
        let grouped = Dictionary(grouping: candidates, by: \.frameIndex)
        var beams: [Beam] = []
        var completed: [Beam] = []

        let orderedGroups = grouped.values.sorted { lhs, rhs in
            let leftTime = lhs.map(\.presentationTime).min() ?? 0
            let rightTime = rhs.map(\.presentationTime).min() ?? 0
            if leftTime == rightTime {
                return (lhs.first?.frameIndex ?? 0) < (rhs.first?.frameIndex ?? 0)
            }
            return leftTime < rightTime
        }

        for frameCandidates in orderedGroups {
            let groupTime = frameCandidates.map(\.presentationTime).min() ?? 0
            var next = frameCandidates.map { Beam(detections: [$0], score: $0.confidence) }

            for beam in beams {
                let extensions = frameCandidates.compactMap { candidate -> Beam? in
                    guard let increment = extensionScore(for: beam.detections, with: candidate) else {
                        return nil
                    }
                    return Beam(
                        detections: beam.detections + [candidate],
                        score: beam.score + increment
                    )
                }
                if extensions.isEmpty {
                    // Keep a beam alive through a dropped detector observation when its elapsed
                    // source time is still plausible. This is deliberately independent of source
                    // FPS. When a plausible extension exists, retaining the old beam would only
                    // create exponential duplicate paths.
                    if let last = beam.detections.last {
                        let elapsed = groupTime - last.presentationTime
                        if elapsed > 0, elapsed <= Self.maximumObservationGap {
                            next.append(Beam(detections: beam.detections, score: beam.score - 0.18))
                        } else {
                            completed.append(beam)
                        }
                    }
                } else {
                    next.append(contentsOf: extensions)
                }
            }

            next.sort { rank($0) > rank($1) }
            beams = Array(next.prefix(5_000))
        }
        completed.append(contentsOf: beams)

        let eligible = completed.compactMap { beam -> (GolfBallTrack, Double)? in
            // Trimming changes the evidence. Revalidate every trimmed hypothesis before ranking,
            // rather than selecting first and checking only its remaining point count.
            let detections = trimmingLeadingDetectorHandoff(from: beam.detections)
            guard let track = validatedTrack(
                detections: detections,
                impactTime: impactTime,
                minimumDetectionCount: minimumDetectionCount
            ), let first = detections.first, let last = detections.last else { return nil }
            let rise = first.point.y - (detections.map(\.point.y).min() ?? first.point.y)
            let coverage = timeCoverage(of: detections, duration: last.presentationTime - first.presentationTime)
            return (track, beam.score + Double(detections.count) * 2 + coverage * 4 + rise * 18)
        }
        return eligible.max(by: { $0.1 < $1.1 })?.0
    }

    /// Final display may extend the committed identity, but cannot substitute an unrelated path
    /// from the original full-frame candidate pool. Reacquisition supplies actual observations only.
    static func finalise(
        committedTrack: GolfBallTrack,
        linkedDetections: [GolfBallDetectionCandidate],
        impactTime: TimeInterval
    ) -> GolfBallTrack? {
        guard committedTrack.detections.count >= 8,
              linkedDetections.starts(with: committedTrack.detections),
              zip(linkedDetections, linkedDetections.dropFirst()).allSatisfy({
                  $1.presentationTime - $0.presentationTime <= 0.4
              }) else { return nil }
        return validatedTrack(detections: linkedDetections, impactTime: impactTime, minimumDetectionCount: 8)
    }

    private static func validatedTrack(
        detections: [GolfBallDetectionCandidate],
        impactTime: TimeInterval,
        minimumDetectionCount: Int
    ) -> GolfBallTrack? {
        guard detections.count >= minimumDetectionCount,
              let first = detections.first, let last = detections.last,
              first.presentationTime >= impactTime,
              first.presentationTime <= impactTime + 0.65,
              detections.allSatisfy({
                  $0.presentationTime.isFinite && $0.point.x.isFinite && $0.point.y.isFinite && $0.confidence.isFinite
              }),
              zip(detections, detections.dropFirst()).allSatisfy({ $1.presentationTime > $0.presentationTime }) else {
            return nil
        }
        let duration = last.presentationTime - first.presentationTime
        // Keep the launch-rise requirement after a supported apex and descent. Endpoint-only rise
        // incorrectly discards the same observed ball once it returns towards its starting height.
        let upwardTravel = first.point.y - (detections.map(\.point.y).min() ?? first.point.y)
        let displacement = detections.map { distance(first.point, $0.point) }.max() ?? 0
        guard upwardTravel >= 0.012, displacement >= 0.015,
              duration >= minimumTrackDuration,
              timeCoverage(of: detections, duration: duration) >= 0.58 else { return nil }
        let meanConfidence = detections.map(\.confidence).reduce(0, +) / Double(detections.count)
        return GolfBallTrack(
            detections: detections,
            confidence: min(1, meanConfidence * 0.72 + min(1, Double(detections.count) / 14) * 0.28)
        )
    }

    private static func extensionScore(
        for track: [GolfBallDetectionCandidate],
        with candidate: GolfBallDetectionCandidate
    ) -> Double? {
        guard let penalty = GolfBallTrackMotion.linkPenalty(history: track, candidate: candidate) else { return nil }
        return 1.2 + candidate.confidence - penalty
    }

    private static func timeCoverage(
        of detections: [GolfBallDetectionCandidate],
        duration: TimeInterval
    ) -> Double {
        guard duration > 0, detections.count >= 2 else { return 0 }
        let occupied = zip(detections, detections.dropFirst()).reduce(0.0) { partial, pair in
            partial + min(max(0, pair.1.presentationTime - pair.0.presentationTime), coverageInterval)
        }
        return min(1, occupied / duration)
    }

    private static func rank(_ beam: Beam) -> Double {
        beam.score + (Double(beam.detections.count) * 2)
    }

    static func trimmingLeadingDetectorHandoff(
        from detections: [GolfBallDetectionCandidate]
    ) -> [GolfBallDetectionCandidate] {
        guard detections.count >= 5 else { return detections }
        let lastTransition = min(detections.count - 1, 6)
        for index in 2...lastTransition {
            let previous = detections[index - 2]
            let pivot = detections[index - 1]
            let current = detections[index]
            let oldElapsed = pivot.presentationTime - previous.presentationTime
            let newElapsed = current.presentationTime - pivot.presentationTime
            guard oldElapsed > 0, newElapsed > 0 else { continue }

            let oldVelocity = vector(from: previous.point, to: pivot.point, dividedBy: oldElapsed)
            let newVelocity = vector(from: pivot.point, to: current.point, dividedBy: newElapsed)
            let oldSpeed = hypot(oldVelocity.x, oldVelocity.y)
            let newSpeed = hypot(newVelocity.x, newVelocity.y)
            guard oldSpeed > 0, newSpeed > 0 else { continue }
            let directionCosine = ((oldVelocity.x * newVelocity.x) + (oldVelocity.y * newVelocity.y))
                / (oldSpeed * newSpeed)
            let speedRatio = newSpeed / oldSpeed
            if directionCosine < 0.78, speedRatio < 0.4 {
                return Array(detections[(index - 1)...])
            }
        }
        return detections
    }

    private static func vector(
        from start: NormalizedPoint,
        to end: NormalizedPoint,
        dividedBy divisor: Double
    ) -> (x: Double, y: Double) {
        ((end.x - start.x) / divisor, (end.y - start.y) / divisor)
    }

    private static func distance(_ first: NormalizedPoint, _ second: NormalizedPoint) -> Double {
        hypot(second.x - first.x, second.y - first.y)
    }
}

/// Shared association checks for acquisition and continuation. A direction reversal is permitted
/// only near a previously observed launch apex and when three source-timed points predict it.
enum GolfBallTrackMotion {
    static let maximumObservationGap: TimeInterval = 0.115

    static func predictedPoint(history: [GolfBallDetectionCandidate], at time: TimeInterval) -> NormalizedPoint? {
        guard let last = history.last else { return nil }
        guard history.count >= 2 else { return last.point }
        let previous = history[history.count - 2]
        let interval = last.presentationTime - previous.presentationTime
        guard interval > 0 else { return last.point }
        let elapsed = max(0, time - last.presentationTime)
        let vx = (last.point.x - previous.point.x) / interval
        let vy = (last.point.y - previous.point.y) / interval
        if let acceleration = apexAcceleration(history: history) {
            return NormalizedPoint(
                x: last.point.x + vx * elapsed + 0.5 * acceleration.x * elapsed * (interval + elapsed),
                y: last.point.y + vy * elapsed + 0.5 * acceleration.y * elapsed * (interval + elapsed)
            )
        }
        return NormalizedPoint(x: last.point.x + vx * elapsed, y: last.point.y + vy * elapsed)
    }

    static func linkPenalty(history: [GolfBallDetectionCandidate], candidate: GolfBallDetectionCandidate) -> Double? {
        guard let last = history.last else { return 0 }
        let elapsed = candidate.presentationTime - last.presentationTime
        guard elapsed > 0, elapsed <= maximumObservationGap else { return nil }
        let vx = (candidate.point.x - last.point.x) / elapsed
        let vy = (candidate.point.y - last.point.y) / elapsed
        let speed = hypot(vx, vy)
        guard speed <= 2.4 else { return nil }
        guard history.count >= 2 else { return speed >= 0.008 ? 0 : nil }
        let previous = history[history.count - 2]
        let interval = last.presentationTime - previous.presentationTime
        guard interval > 0 else { return nil }
        let oldVX = (last.point.x - previous.point.x) / interval
        let oldVY = (last.point.y - previous.point.y) / interval
        let oldSpeed = hypot(oldVX, oldVY)
        let cosine = oldSpeed > 0 && speed > 0 ? (oldVX * vx + oldVY * vy) / (oldSpeed * speed) : -1
        let linear = NormalizedPoint(x: last.point.x + oldVX * elapsed, y: last.point.y + oldVY * elapsed)
        let linearError = hypot(candidate.point.x - linear.x, candidate.point.y - linear.y)
        if speed >= 0.008, oldSpeed > 0, cosine >= 0.45,
           linearError <= max(0.006, oldSpeed * elapsed * 1.7 + 0.008) {
            return max(0, elapsed - 0.05) * 6 + linearError / 0.005
        }
        guard max(speed, oldSpeed) <= 0.15,
              apexAcceleration(history: history) != nil,
              let predicted = predictedPoint(history: history, at: candidate.presentationTime) else { return nil }
        let error = hypot(candidate.point.x - predicted.x, candidate.point.y - predicted.y)
        guard error <= 0.004 else { return nil }
        return max(0, elapsed - 0.05) * 6 + error / 0.005
    }

    private static func apexAcceleration(history: [GolfBallDetectionCandidate]) -> (x: Double, y: Double)? {
        guard history.count >= 3, let first = history.first, let last = history.last,
              first.point.y - last.point.y >= 0.012 else { return nil }
        let middle = history[history.count - 2]
        let previous = history[history.count - 3]
        let recentInterval = last.presentationTime - middle.presentationTime
        let earlierInterval = middle.presentationTime - previous.presentationTime
        guard recentInterval > 0, earlierInterval > 0,
              recentInterval <= maximumObservationGap, earlierInterval <= maximumObservationGap else { return nil }
        let vx = (last.point.x - middle.point.x) / recentInterval
        let vy = (last.point.y - middle.point.y) / recentInterval
        guard hypot(vx, vy) <= 0.15 else { return nil }
        let duration = (recentInterval + earlierInterval) / 2
        let ax = (vx - (middle.point.x - previous.point.x) / earlierInterval) / duration
        let ay = (vy - (middle.point.y - previous.point.y) / earlierInterval) / duration
        guard ay > 0, ay <= 3, abs(ax) <= 1 else { return nil }
        return (ax, ay)
    }
}
