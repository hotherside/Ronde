import Foundation

/// Selects decoded frames on presentation time rather than on a container's nominal frame rate.
///
/// The reader still decodes every source sample sequentially, but only accepted samples enter the
/// model window. This keeps the model's temporal context close to the configured cadence for
/// 24, 30, 60 and 120 fps uploads without inventing frames that were not present in the source.
struct PresentationTimestampFrameSampler: Sendable, Equatable {
    private let cadence: TimeInterval
    private var nextEligibleTime: TimeInterval

    init(startTime: TimeInterval, cadence: TimeInterval) {
        self.cadence = max(1.0 / 120.0, cadence)
        nextEligibleTime = max(0, startTime)
    }

    mutating func accepts(presentationTime: TimeInterval) -> Bool {
        let timestamp = max(0, presentationTime)
        // A small tolerance avoids excluding a sample merely because CMTime converted to Double
        // one ULP below the target time.
        guard timestamp + 0.000_001 >= nextEligibleTime else { return false }
        nextEligibleTime = timestamp + cadence
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

        let eligible = completed.compactMap { beam -> (Beam, Double)? in
            guard beam.detections.count >= minimumDetectionCount,
                  let first = beam.detections.first,
                  let last = beam.detections.last,
                  first.presentationTime <= impactTime + 0.65 else {
                return nil
            }

            let upwardTravel = first.point.y - last.point.y
            let displacement = distance(first.point, last.point)
            let duration = last.presentationTime - first.presentationTime
            let coverage = timeCoverage(of: beam.detections, duration: duration)
            guard upwardTravel >= 0.012,
                  displacement >= 0.015,
                  coverage >= 0.58,
                  duration >= Self.minimumTrackDuration else {
                return nil
            }

            let finalScore = beam.score
                + (Double(beam.detections.count) * 2)
                + (coverage * 4)
                + (upwardTravel * 18)
            return (beam, finalScore)
        }

        guard let selected = eligible.max(by: { $0.1 < $1.1 })?.0 else { return nil }
        let detections = trimmingLeadingDetectorHandoff(from: selected.detections)
        guard detections.count >= minimumDetectionCount else { return nil }
        let meanConfidence = detections.map(\.confidence).reduce(0, +)
            / Double(detections.count)
        let coverageConfidence = min(1, Double(detections.count) / 14)
        return GolfBallTrack(
            detections: detections,
            confidence: min(1, (meanConfidence * 0.72) + (coverageConfidence * 0.28))
        )
    }

    private static func extensionScore(
        for track: [GolfBallDetectionCandidate],
        with candidate: GolfBallDetectionCandidate
    ) -> Double? {
        guard let last = track.last else { return candidate.confidence }
        let elapsed = candidate.presentationTime - last.presentationTime
        guard elapsed > 0, elapsed <= maximumObservationGap else { return nil }

        let newVelocity = vector(from: last.point, to: candidate.point, dividedBy: elapsed)
        let speed = hypot(newVelocity.x, newVelocity.y)
        // Normalised image distance per second. These bounds remain stable if the same footage is
        // uploaded at 24, 30, 60 or 120 fps.
        guard speed >= 0.008, speed <= 2.4 else { return nil }

        var penalty = max(0, elapsed - coverageInterval) * 6
        if track.count >= 2 {
            let previous = track[track.count - 2]
            let previousElapsed = last.presentationTime - previous.presentationTime
            guard previousElapsed > 0 else { return nil }
            let oldVelocity = vector(from: previous.point, to: last.point, dividedBy: previousElapsed)
            let oldSpeed = hypot(oldVelocity.x, oldVelocity.y)
            guard oldSpeed > 0 else { return nil }

            let cosine = ((oldVelocity.x * newVelocity.x) + (oldVelocity.y * newVelocity.y))
                / (oldSpeed * speed)
            guard cosine >= 0.45 else { return nil }

            let predicted = NormalizedPoint(
                x: last.point.x + (oldVelocity.x * elapsed),
                y: last.point.y + (oldVelocity.y * elapsed)
            )
            let predictionError = distance(predicted, candidate.point)
            let permittedError = max(0.006, (oldSpeed * elapsed * 1.7) + 0.008)
            guard predictionError <= permittedError else { return nil }
            penalty += predictionError / 0.005
        }
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
