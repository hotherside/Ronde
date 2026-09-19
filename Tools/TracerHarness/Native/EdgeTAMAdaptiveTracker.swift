import Foundation

struct EdgeTAMAdaptiveRecord: Codable, Sendable {
    let index: Int
    let timestamp: Double
    let crop: EdgeTAMSourceCrop
    let segmentID: Int
    let direction: String
    let visible: Bool
    let centroidX: Double?
    let centroidY: Double?
    let objectScoreLogit: Float
}

struct EdgeTAMAdaptiveObservation: Sendable {
    let index: Int
    let timestamp: Double
    let crop: EdgeTAMSourceCrop
    let segmentID: Int
    let direction: String
    let mask: EdgeTAMMaskObservation
    let objectScoreLogit: Float
    /// A reset/duplicate seed is diagnostic and never replaces a canonical sample.
    let kind: String
}

struct EdgeTAMAdaptiveSegment: Codable, Sendable {
    let segmentID: Int
    let direction: String
    let crop: EdgeTAMSourceCrop
    let anchorIndex: Int
    let anchorTimestamp: Double
    let pointSource: String
}

struct EdgeTAMAdaptiveTransition: Codable, Sendable {
    let index: Int
    let timestamp: Double
    let direction: String
    let oldCrop: EdgeTAMSourceCrop
    let newCrop: EdgeTAMSourceCrop
    let modelDerivedPointX: Double
    let modelDerivedPointY: Double
}

struct EdgeTAMAdaptiveTermination: Codable, Sendable {
    let reason: String
    var timestamp: Double? = nil
    var firstUnprocessedTimestamp: Double? = nil
    var lastObservedTimestamp: Double? = nil
}

struct EdgeTAMAdaptiveResult: Codable, Sendable {
    let canonical: [EdgeTAMAdaptiveRecord]
    let segments: [EdgeTAMAdaptiveSegment]
    let transitions: [EdgeTAMAdaptiveTransition]
    let terminations: [String: EdgeTAMAdaptiveTermination]
    let automaticReseedCount: Int
    let gapRecoveryCount: Int
}

/// Native implementation of the frozen one-point development policy. All
/// recentring points are actual mask centroids. Empty masks retain state for a
/// bounded source-time gap, emit no point and cannot cause a crop reset.
///
/// The frame provider must return the exact requested source frame/crop. Keeping
/// it separate allows bounded video decoding without retaining all RGB images.
final class EdgeTAMAdaptiveTracker {
    private let components: any EdgeTAMComponents
    private let constants: EdgeTAMLearnedConstants

    init(components: any EdgeTAMComponents, constants: EdgeTAMLearnedConstants) {
        self.components = components
        self.constants = constants
    }

    func track(
        frameTimes: [Double], sourceWidth: Int, sourceHeight: Int, seedIndex: Int,
        point: (x: Double, y: Double), maximumSourceTimeGapSeconds: Double = 0.20,
        frameProvider: (Int, EdgeTAMSourceCrop) throws -> EdgeTAMTensor,
        observer: (EdgeTAMAdaptiveObservation) throws -> Void = { _ in }
    ) throws -> EdgeTAMAdaptiveResult {
        guard sourceWidth >= 512, sourceHeight >= 512, !frameTimes.isEmpty,
              frameTimes.allSatisfy({ $0.isFinite && $0 >= 0 }),
              zip(frameTimes, frameTimes.dropFirst()).allSatisfy({ $0 < $1 }),
              (0..<frameTimes.count).contains(seedIndex), point.x.isFinite, point.y.isFinite,
              (0..<Double(sourceWidth)).contains(point.x), (0..<Double(sourceHeight)).contains(point.y),
              maximumSourceTimeGapSeconds == 0 || maximumSourceTimeGapSeconds == 0.20 else {
            throw EdgeTAMNativeError.invalidState("Invalid adaptive source interval, point or frozen policy")
        }
        try constants.validate()
        let started = ProcessInfo.processInfo.systemUptime
        var canonical: [Int: EdgeTAMAdaptiveRecord] = [:]
        var segments: [EdgeTAMAdaptiveSegment] = []
        var transitions: [EdgeTAMAdaptiveTransition] = []
        var terminations: [String: EdgeTAMAdaptiveTermination] = [:]
        var reseeds = 0
        var recoveries = 0

        func cropFor(_ p: (x: Double, y: Double)) -> EdgeTAMSourceCrop {
            EdgeTAMSourceCrop(x: min(max(0, Int(floor(p.x + 0.5)) - 256), sourceWidth - 512),
                              y: min(max(0, Int(floor(p.y + 0.5)) - 256), sourceHeight - 512),
                              width: 512, height: 512)
        }
        func gapAllowed(last: Double?, current: Double) -> Bool {
            guard maximumSourceTimeGapSeconds > 0, let last else { return false }
            return abs(current - last) <= maximumSourceTimeGapSeconds + 1e-9
        }

        directionLoop: for reverse in [false, true] {
            let direction = reverse ? "reverse" : "forward"
            let step = reverse ? -1 : 1
            var anchor = seedIndex
            var anchorPoint = point
            var crop = cropFor(point)
            var resetSeed = false
            var lastObserved: Double?
            var activeGap = false

            segmentLoop: while true {
                try Task.checkCancellation()
                if ProcessInfo.processInfo.systemUptime - started >= 240 {
                    terminations[direction] = EdgeTAMAdaptiveTermination(reason: "propagation_time_limit")
                    break directionLoop
                }
                if resetSeed { reseeds += 1 }
                let segmentID = segments.count
                segments.append(EdgeTAMAdaptiveSegment(
                    segmentID: segmentID, direction: direction, crop: crop, anchorIndex: anchor,
                    anchorTimestamp: frameTimes[anchor], pointSource: resetSeed ? "model_centroid" : "single_user_point"))
                let tracker = try EdgeTAMSegmentTracker(components: components, constants: constants,
                                                       frameCount: frameTimes.count, reverse: reverse)
                var index = anchor
                while (0..<frameTimes.count).contains(index) {
                    try Task.checkCancellation()
                    if ProcessInfo.processInfo.systemUptime - started >= 240 {
                        terminations[direction] = EdgeTAMAdaptiveTermination(reason: "propagation_time_limit")
                        break directionLoop
                    }
                    let timestamp = frameTimes[index]
                    if activeGap && !gapAllowed(last: lastObserved, current: timestamp) {
                        terminations[direction] = EdgeTAMAdaptiveTermination(
                            reason: "source_time_gap_limit", firstUnprocessedTimestamp: timestamp,
                            lastObservedTimestamp: lastObserved)
                        break segmentLoop
                    }
                    let isAnchor = index == anchor
                    let isTransition = isAnchor && resetSeed
                    let duplicateInitial = reverse && index == seedIndex && !resetSeed
                    let modelPoint: (x: Float, y: Float)? = isAnchor
                        ? (Float(anchorPoint.x - Double(crop.x)) * 2,
                           Float(anchorPoint.y - Double(crop.y)) * 2) : nil
                    let (mask, score): (EdgeTAMMaskObservation, Float) = try autoreleasepool {
                        let input = try frameProvider(index, crop)
                        let result = try tracker.process(imageNormalised: input, frameIndex: index,
                                                         sourceTime: timestamp, point: modelPoint)
                        return (try EdgeTAMMaskObservation.extract(lowMask: result.masks.lowMask, width: 512, height: 512),
                                result.masks.objectScore.values[0])
                    }
                    let kind = isTransition ? "transition" : duplicateInitial ? "initial-reverse" : "canonical"
                    try observer(EdgeTAMAdaptiveObservation(index: index, timestamp: timestamp, crop: crop,
                                                           segmentID: segmentID, direction: direction,
                                                           mask: mask, objectScoreLogit: score, kind: kind))
                    if isTransition {
                        guard mask.selectedArea > 0 else {
                            terminations[direction] = EdgeTAMAdaptiveTermination(reason: "empty_reseed_mask", timestamp: timestamp)
                            break segmentLoop
                        }
                        // The previous crop's observation is already canonical.
                        // This mask only establishes the new segment's memory.
                        index += step
                        continue
                    }
                    if !duplicateInitial {
                        guard canonical[index] == nil else {
                            throw EdgeTAMNativeError.invalidState("A canonical source observation would be replaced")
                        }
                        canonical[index] = EdgeTAMAdaptiveRecord(
                            index: index, timestamp: timestamp, crop: crop, segmentID: segmentID, direction: direction,
                            visible: mask.selectedArea > 0,
                            centroidX: mask.centroidX.map { $0 + Double(crop.x) },
                            centroidY: mask.centroidY.map { $0 + Double(crop.y) }, objectScoreLogit: score)
                    }
                    guard let localX = mask.centroidX, let localY = mask.centroidY else {
                        if gapAllowed(last: lastObserved, current: timestamp) {
                            activeGap = true
                            if !(0..<frameTimes.count).contains(index + step) {
                                terminations[direction] = EdgeTAMAdaptiveTermination(reason: "interval_boundary_after_empty", timestamp: timestamp)
                                break segmentLoop
                            }
                            index += step
                            continue
                        }
                        terminations[direction] = EdgeTAMAdaptiveTermination(reason: "first_empty_mask", timestamp: timestamp)
                        break segmentLoop
                    }
                    if activeGap { recoveries += 1; activeGap = false }
                    lastObserved = timestamp
                    if !(0..<frameTimes.count).contains(index + step) {
                        terminations[direction] = EdgeTAMAdaptiveTermination(reason: "interval_boundary", timestamp: timestamp)
                        break segmentLoop
                    }
                    let observed = (x: localX + Double(crop.x), y: localY + Double(crop.y))
                    guard (0..<Double(sourceWidth)).contains(observed.x), (0..<Double(sourceHeight)).contains(observed.y) else {
                        throw EdgeTAMNativeError.invalidState("Mask centroid is outside the upright source")
                    }
                    let xViolates = !(128..<384).contains(localX)
                    let yViolates = !(128..<384).contains(localY)
                    if xViolates || yViolates {
                        let nextCrop = cropFor(observed)
                        if (xViolates && nextCrop.x != crop.x) || (yViolates && nextCrop.y != crop.y) {
                            guard reseeds < 32 else {
                                terminations[direction] = EdgeTAMAdaptiveTermination(reason: "automatic_reseed_limit", timestamp: timestamp)
                                break segmentLoop
                            }
                            transitions.append(EdgeTAMAdaptiveTransition(index: index, timestamp: timestamp, direction: direction,
                                oldCrop: crop, newCrop: nextCrop, modelDerivedPointX: observed.x, modelDerivedPointY: observed.y))
                            anchor = index
                            anchorPoint = observed
                            crop = nextCrop
                            resetSeed = true
                            continue segmentLoop
                        }
                    }
                    index += step
                }
                break segmentLoop
            }
        }
        return EdgeTAMAdaptiveResult(canonical: canonical.sorted { $0.key < $1.key }.map(\.value),
            segments: segments, transitions: transitions, terminations: terminations,
            automaticReseedCount: reseeds, gapRecoveryCount: recoveries)
    }
}
