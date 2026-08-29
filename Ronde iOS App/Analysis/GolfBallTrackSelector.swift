import Foundation

struct GolfBallDetectionCandidate: Sendable, Equatable {
    let frameIndex: Int
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
/// from the strike area across consecutive source frames, maintain direction and cover enough of
/// the post-impact window to be eligible for display.
enum GolfBallTrackSelector {
    private struct Beam {
        var detections: [GolfBallDetectionCandidate]
        var score: Double
    }

    static func select(
        from candidates: [GolfBallDetectionCandidate],
        impactTime: TimeInterval,
        minimumDetectionCount: Int = 7
    ) -> GolfBallTrack? {
        let grouped = Dictionary(grouping: candidates, by: \.frameIndex)
        var beams: [Beam] = []
        var completed: [Beam] = []

        for frameIndex in grouped.keys.sorted() {
            guard let frameCandidates = grouped[frameIndex] else { continue }
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
                    completed.append(beam)
                } else {
                    next.append(contentsOf: extensions)
                }

                if let last = beam.detections.last, frameIndex - last.frameIndex < 2 {
                    next.append(Beam(detections: beam.detections, score: beam.score - 0.35))
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
            let span = max(1, last.frameIndex - first.frameIndex + 1)
            let coverage = Double(beam.detections.count) / Double(span)
            let duration = last.presentationTime - first.presentationTime
            guard upwardTravel >= 0.012,
                  displacement >= 0.015,
                  coverage >= 0.58,
                  duration >= 0.18 else {
                return nil
            }

            let finalScore = beam.score
                + (Double(beam.detections.count) * 2)
                + (coverage * 4)
                + (upwardTravel * 18)
            return (beam, finalScore)
        }

        guard let selected = eligible.max(by: { $0.1 < $1.1 })?.0 else { return nil }
        let meanConfidence = selected.detections.map(\.confidence).reduce(0, +)
            / Double(selected.detections.count)
        let coverageConfidence = min(1, Double(selected.detections.count) / 14)
        return GolfBallTrack(
            detections: selected.detections,
            confidence: min(1, (meanConfidence * 0.72) + (coverageConfidence * 0.28))
        )
    }

    private static func extensionScore(
        for track: [GolfBallDetectionCandidate],
        with candidate: GolfBallDetectionCandidate
    ) -> Double? {
        guard let last = track.last else { return candidate.confidence }
        let gap = candidate.frameIndex - last.frameIndex
        guard gap == 1 || gap == 2 else { return nil }

        let newVelocity = vector(from: last.point, to: candidate.point, dividedBy: Double(gap))
        let speed = hypot(newVelocity.x, newVelocity.y)
        guard speed >= 0.0006, speed <= 0.04 else { return nil }

        var penalty = Double(gap - 1) * 0.8
        if track.count >= 2 {
            let previous = track[track.count - 2]
            let oldGap = max(1, last.frameIndex - previous.frameIndex)
            let oldVelocity = vector(from: previous.point, to: last.point, dividedBy: Double(oldGap))
            let oldSpeed = hypot(oldVelocity.x, oldVelocity.y)
            guard oldSpeed > 0 else { return nil }

            let cosine = ((oldVelocity.x * newVelocity.x) + (oldVelocity.y * newVelocity.y))
                / (oldSpeed * speed)
            guard cosine >= 0.45 else { return nil }

            let predicted = NormalizedPoint(
                x: last.point.x + (oldVelocity.x * Double(gap)),
                y: last.point.y + (oldVelocity.y * Double(gap))
            )
            let predictionError = distance(predicted, candidate.point)
            guard predictionError <= max(0.006, oldSpeed * 1.4) else { return nil }
            penalty += predictionError / 0.005
        }
        return 1.2 + candidate.confidence - penalty
    }

    private static func rank(_ beam: Beam) -> Double {
        beam.score + (Double(beam.detections.count) * 2)
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
