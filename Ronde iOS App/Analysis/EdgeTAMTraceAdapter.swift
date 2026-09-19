import CryptoKit
import Foundation

extension SeededModelTrace {
    /// Preserve model observations and explicit gaps in the source pixel grid.
    /// The supplied seed remains assistance and is never inserted as a frame.
    init?(trackingResult result: EdgeTAMTrackingResult, seedOrigin: SeedOrigin = .selectedByPerson) {
        let componentNames: Set<String> = ["image", "attention", "point", "noPoint", "memory"]
        guard result.sourceWidth > 0, result.sourceHeight > 0,
              result.frameTimes.count == result.sourceFrameIndices.count,
              Set(result.modelIdentity.compiledModelSHA256.keys) == componentNames,
              let constantsHash = Self.edgeTAMBareHash(result.modelIdentity.constantsSHA256) else { return nil }
        var componentManifest = ""
        for name in componentNames.sorted() {
            guard let value = result.modelIdentity.compiledModelSHA256[name],
                  let hash = Self.edgeTAMBareHash(value) else { return nil }
            // Same aggregate grammar as the device diagnostic, independent of
            // optional prefix/case differences in an incoming identity value.
            componentManifest += "\(name)\tsha256:\(hash)\n"
        }
        let modelHash = SHA256.hash(data: Data(componentManifest.utf8))
            .map { String(format: "%02x", $0) }.joined()
        guard let model = SeededModelTraceModelIdentity(
            identifier: "EdgeTAM", version: result.modelIdentity.modelVersion,
            modelBundleSHA256: modelHash, learnedConstantsSHA256: constantsHash
        ), let seed = SeededModelTraceSeed(
            sourceFrameIndex: result.seedSourceFrameIndex, presentationTime: result.seedPTS,
            sourcePixelX: result.seedNormalisedPoint.x * Double(result.sourceWidth),
            sourcePixelY: result.seedNormalisedPoint.y * Double(result.sourceHeight)
        ), let policy = SeededModelTracePolicy(
            maximumSourceTimeGapSeconds: 0.20, automaticReseedCount: result.automaticReseedCount,
            gapRecoveryCount: result.gapRecoveryCount,
            terminationReasons: Dictionary(uniqueKeysWithValues: result.terminations.map { ($0.key.rawValue, $0.value.reason) }),
            wasBudgetLimited: result.status == .partialBudgetLimit
        ) else { return nil }

        var frames: [SeededModelTraceFrame] = []
        frames.reserveCapacity(result.records.count)
        for record in result.records {
            guard result.frameTimes.indices.contains(record.intervalFrameIndex),
                  result.frameTimes[record.intervalFrameIndex] == record.sourcePTS,
                  result.sourceFrameIndices[record.intervalFrameIndex] == record.sourceFrameIndex else { return nil }
            let observation: SeededModelTraceObservation?
            if record.visible {
                guard let point = record.normalisedPoint,
                      let value = SeededModelTraceObservation(
                        sourcePixelX: point.x * Double(result.sourceWidth),
                        sourcePixelY: point.y * Double(result.sourceHeight)
                      ) else { return nil }
                observation = value
            } else {
                guard record.normalisedPoint == nil else { return nil }
                observation = nil
            }
            guard let frame = SeededModelTraceFrame(sourceFrameIndex: record.sourceFrameIndex,
                presentationTime: record.sourcePTS, observation: observation) else { return nil }
            frames.append(frame)
        }
        self.init(sourceWidth: result.sourceWidth, sourceHeight: result.sourceHeight, seed: seed,
                  sourceInterval: ReviewTimeRange(start: result.interval.lowerBound,
                                                  duration: result.interval.upperBound - result.interval.lowerBound),
                  model: model, frames: frames, policy: policy, seedOrigin: seedOrigin)
    }

    private static func edgeTAMBareHash(_ value: String) -> String? {
        let lower = value.lowercased()
        let hash = lower.hasPrefix("sha256:") ? String(lower.dropFirst(7)) : lower
        guard hash.utf8.count == 64,
              hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        return hash
    }
}
