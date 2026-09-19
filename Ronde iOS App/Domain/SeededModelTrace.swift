import Foundation

/// A point supplied by the person reviewing a shot, expressed in the original source-pixel grid.
/// It authorises an assisted model pass; it is not itself a detector observation.
struct SeededModelTraceSeed: Codable, Sendable, Equatable, Hashable {
    let sourceFrameIndex: Int
    let presentationTime: TimeInterval
    let sourcePixelX: Double
    let sourcePixelY: Double

    init?(sourceFrameIndex: Int, presentationTime: TimeInterval, sourcePixelX: Double, sourcePixelY: Double) {
        guard sourceFrameIndex >= 0,
              presentationTime.isFinite, presentationTime >= 0,
              sourcePixelX.isFinite, sourcePixelY.isFinite else {
            return nil
        }
        self.sourceFrameIndex = sourceFrameIndex
        self.presentationTime = presentationTime
        self.sourcePixelX = sourcePixelX
        self.sourcePixelY = sourcePixelY
    }
}

/// One actual model-localised point. Coordinates remain in the source pixel grid so persisted
/// evidence cannot silently acquire a different crop, orientation, or normalisation convention.
struct SeededModelTraceObservation: Codable, Sendable, Equatable, Hashable {
    let sourcePixelX: Double
    let sourcePixelY: Double

    init?(sourcePixelX: Double, sourcePixelY: Double) {
        guard sourcePixelX.isFinite, sourcePixelY.isFinite else { return nil }
        self.sourcePixelX = sourcePixelX
        self.sourcePixelY = sourcePixelY
    }
}

/// A visited source frame. `observation == nil` is a deliberate, persisted break in the observed
/// path. It must never be rendered as an interpolated or inferred ball position.
struct SeededModelTraceFrame: Codable, Sendable, Equatable, Hashable {
    let sourceFrameIndex: Int
    let presentationTime: TimeInterval
    let observation: SeededModelTraceObservation?

    init?(sourceFrameIndex: Int, presentationTime: TimeInterval, observation: SeededModelTraceObservation?) {
        guard sourceFrameIndex >= 0, presentationTime.isFinite, presentationTime >= 0 else { return nil }
        self.sourceFrameIndex = sourceFrameIndex
        self.presentationTime = presentationTime
        self.observation = observation
    }
}

/// Stable model provenance for an assisted trace. Hashes identify the exact packaged artefacts;
/// no private media name, path, or coordinate diagnostic belongs here.
struct SeededModelTraceModelIdentity: Codable, Sendable, Equatable, Hashable {
    let identifier: String
    let version: String
    let modelBundleSHA256: String
    let learnedConstantsSHA256: String

    init?(identifier: String, version: String, modelBundleSHA256: String, learnedConstantsSHA256: String) {
        let identifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelBundleSHA256 = modelBundleSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let learnedConstantsSHA256 = learnedConstantsSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !identifier.isEmpty, !version.isEmpty,
              Self.isSHA256(modelBundleSHA256), Self.isSHA256(learnedConstantsSHA256) else {
            return nil
        }
        self.identifier = identifier
        self.version = version
        self.modelBundleSHA256 = modelBundleSHA256
        self.learnedConstantsSHA256 = learnedConstantsSHA256
    }

    var isValid: Bool {
        !identifier.isEmpty && !version.isEmpty
            && Self.isSHA256(modelBundleSHA256) && Self.isSHA256(learnedConstantsSHA256)
    }

    static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit }
    }
}

/// The bounded policy that produced a point-assisted result. It records why a trace can be
/// partial without creating synthetic continuation geometry in playback or export.
struct SeededModelTracePolicy: Codable, Sendable, Equatable, Hashable {
    let maximumSourceTimeGapSeconds: Double
    let automaticReseedCount: Int
    let gapRecoveryCount: Int
    let terminationReasons: [String: String]
    let wasBudgetLimited: Bool

    init?(
        maximumSourceTimeGapSeconds: Double,
        automaticReseedCount: Int,
        gapRecoveryCount: Int,
        terminationReasons: [String: String] = [:],
        wasBudgetLimited: Bool = false
    ) {
        guard maximumSourceTimeGapSeconds.isFinite,
              maximumSourceTimeGapSeconds >= 0,
              maximumSourceTimeGapSeconds <= 0.20,
              automaticReseedCount >= 0,
              gapRecoveryCount >= 0,
              terminationReasons.allSatisfy({ !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return nil
        }
        self.maximumSourceTimeGapSeconds = maximumSourceTimeGapSeconds
        self.automaticReseedCount = automaticReseedCount
        self.gapRecoveryCount = gapRecoveryCount
        self.terminationReasons = terminationReasons
        self.wasBudgetLimited = wasBudgetLimited
    }

    var isValid: Bool {
        maximumSourceTimeGapSeconds.isFinite
            && maximumSourceTimeGapSeconds >= 0
            && maximumSourceTimeGapSeconds <= 0.20
            && automaticReseedCount >= 0
            && gapRecoveryCount >= 0
            && terminationReasons.allSatisfy {
                !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }
}

/// A local, point-assisted model result. Only source-frame observations are retained. Gaps,
/// termination and failure remain visible as absent observations rather than invented geometry.
struct SeededModelTrace: Codable, Sendable, Equatable {
    enum SeedOrigin: String, Codable, Sendable {
        case selectedByPerson, detectedBall
    }
    let sourceWidth: Int
    let sourceHeight: Int
    let seed: SeededModelTraceSeed
    let sourceInterval: ReviewTimeRange
    let model: SeededModelTraceModelIdentity
    let frames: [SeededModelTraceFrame]
    /// Missing in archives created before policy provenance was persisted.
    let policy: SeededModelTracePolicy?
    /// Nil in older archives means a point selected by the person reviewing the shot.
    let seedOrigin: SeedOrigin?

    init?(
        sourceWidth: Int,
        sourceHeight: Int,
        seed: SeededModelTraceSeed,
        sourceInterval: ReviewTimeRange,
        model: SeededModelTraceModelIdentity,
        frames: [SeededModelTraceFrame],
        policy: SeededModelTracePolicy? = nil,
        seedOrigin: SeedOrigin? = nil
    ) {
        guard Self.isValid(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            seed: seed,
            sourceInterval: sourceInterval,
            model: model,
            frames: frames,
            policy: policy
        ) else { return nil }
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.seed = seed
        self.sourceInterval = sourceInterval
        self.model = model
        self.frames = frames
        self.policy = policy
        self.seedOrigin = seedOrigin
    }

    private static func isValid(
        sourceWidth: Int,
        sourceHeight: Int,
        seed: SeededModelTraceSeed,
        sourceInterval: ReviewTimeRange,
        model: SeededModelTraceModelIdentity,
        frames: [SeededModelTraceFrame],
        policy: SeededModelTracePolicy?
    ) -> Bool {
        guard sourceWidth > 0, sourceHeight > 0,
              model.isValid,
              policy?.isValid ?? true,
              seed.sourceFrameIndex >= 0,
              sourceInterval.start.isFinite, sourceInterval.duration.isFinite, sourceInterval.duration > 0,
              seed.presentationTime >= sourceInterval.start - 0.000_001,
              seed.presentationTime <= sourceInterval.end + 0.000_001,
              contains(sourcePixelX: seed.sourcePixelX, sourcePixelY: seed.sourcePixelY, width: sourceWidth, height: sourceHeight),
              !frames.isEmpty else { return false }
        var previousIndex: Int?
        var previousTime: TimeInterval?
        for frame in frames {
            guard frame.sourceFrameIndex >= 0,
                  frame.presentationTime >= sourceInterval.start - 0.000_001,
                  frame.presentationTime <= sourceInterval.end + 0.000_001,
                  previousIndex.map({ frame.sourceFrameIndex > $0 }) ?? true,
                  previousTime.map({ frame.presentationTime > $0 }) ?? true else { return false }
            if let observation = frame.observation,
               !contains(sourcePixelX: observation.sourcePixelX, sourcePixelY: observation.sourcePixelY, width: sourceWidth, height: sourceHeight) {
                return false
            }
            previousIndex = frame.sourceFrameIndex
            previousTime = frame.presentationTime
        }
        return true
    }

    private static func contains(sourcePixelX: Double, sourcePixelY: Double, width: Int, height: Int) -> Bool {
        sourcePixelX.isFinite && sourcePixelY.isFinite
            && sourcePixelX >= 0 && sourcePixelY >= 0
            && sourcePixelX < Double(width) && sourcePixelY < Double(height)
    }

    /// Observed source-time segments. A nil observation or skipped source index ends a segment.
    var observedSegments: [[TimedTrajectorySample]] {
        var result: [[TimedTrajectorySample]] = []
        var current: [TimedTrajectorySample] = []
        var previousIndex: Int?
        for frame in frames {
            guard let observation = frame.observation else {
                if !current.isEmpty { result.append(current); current = [] }
                previousIndex = frame.sourceFrameIndex
                continue
            }
            if let previousIndex, frame.sourceFrameIndex != previousIndex + 1, !current.isEmpty {
                result.append(current)
                current = []
            }
            current.append(TimedTrajectorySample(
                point: NormalizedPoint(
                    x: observation.sourcePixelX / Double(sourceWidth),
                    y: observation.sourcePixelY / Double(sourceHeight)
                ),
                presentationTime: frame.presentationTime
            ))
            previousIndex = frame.sourceFrameIndex
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    var observedPointCount: Int { frames.reduce(into: 0) { if $1.observation != nil { $0 += 1 } } }

    private enum CodingKeys: String, CodingKey {
        case sourceWidth, sourceHeight, seed, sourceInterval, model, frames, policy, seedOrigin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sourceWidth = try container.decode(Int.self, forKey: .sourceWidth)
        let sourceHeight = try container.decode(Int.self, forKey: .sourceHeight)
        let seed = try container.decode(SeededModelTraceSeed.self, forKey: .seed)
        let sourceInterval = try container.decode(ReviewTimeRange.self, forKey: .sourceInterval)
        let model = try container.decode(SeededModelTraceModelIdentity.self, forKey: .model)
        let frames = try container.decode([SeededModelTraceFrame].self, forKey: .frames)
        let policy = try container.decodeIfPresent(SeededModelTracePolicy.self, forKey: .policy)
        let seedOrigin = try container.decodeIfPresent(SeedOrigin.self, forKey: .seedOrigin)
        guard let trace = Self(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            seed: seed,
            sourceInterval: sourceInterval,
            model: model,
            frames: frames,
            policy: policy,
            seedOrigin: seedOrigin
        ) else {
            throw DecodingError.dataCorruptedError(forKey: .frames, in: container, debugDescription: "Invalid seeded model trace.")
        }
        self = trace
    }
}
