import CryptoKit
import Foundation

/// Top-left upright-source coordinates, normalised to [0, 1).
struct EdgeTAMTrackingPoint: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
}

enum EdgeTAMTrackingDirection: String, Codable, Sendable {
    case forward, reverse
}

struct EdgeTAMTrackingProgress: Sendable {
    enum Stage: String, Sendable {
        case validatingResources, readingFrames, loadingModels, tracking, finished
    }
    let stage: Stage
    let completedCanonicalFrames: Int
    let totalFrames: Int?
}

struct EdgeTAMTrackingModelIdentity: Codable, Equatable, Sendable {
    let modelVersion: String
    let manifestSHA256: String
    let constantsSHA256: String
    let compiledModelSHA256: [String: String]
}

struct EdgeTAMTrackingRecord: Codable, Sendable {
    let intervalFrameIndex: Int
    let sourceFrameIndex: Int
    let sourcePTS: Double
    /// A positive model mask, not an independent claim of golf-ball identity.
    let visible: Bool
    let normalisedPoint: EdgeTAMTrackingPoint?
    let objectScoreLogit: Float
    let segmentID: Int
    let direction: EdgeTAMTrackingDirection
}

struct EdgeTAMTrackingTermination: Codable, Sendable {
    let reason: String
    let timestamp: Double?
    let firstUnprocessedTimestamp: Double?
    let lastObservedTimestamp: Double?
}

struct EdgeTAMTrackingResult: Sendable {
    enum Status: String, Sendable {
        /// The frozen stopping rules completed; this does not mean full flight.
        case completed
        case partialBudgetLimit
    }
    let status: Status
    let sourceWidth: Int
    let sourceHeight: Int
    let interval: ClosedRange<Double>
    let frameTimes: [Double]
    let sourceFrameIndices: [Int]
    let seedPTS: Double
    let seedSourceFrameIndex: Int
    let seedNormalisedPoint: EdgeTAMTrackingPoint
    /// Includes every canonical empty mask. No seed or gap point is invented.
    let records: [EdgeTAMTrackingRecord]
    let terminations: [EdgeTAMTrackingDirection: EdgeTAMTrackingTermination]
    let automaticReseedCount: Int
    let gapRecoveryCount: Int
    let modelIdentity: EdgeTAMTrackingModelIdentity
    let elapsedSeconds: Double
}

enum EdgeTAMTrackingError: LocalizedError, Sendable {
    case busy
    case unavailable
    case invalidInterval
    case invalidPoint
    case invalidSourceDimensions
    case seedUnavailable
    case resourceIdentityMismatch
    case sourceUnavailable
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .busy: "Another ball track is already being processed."
        case .unavailable: "Ball tracking resources are not included in this build."
        case .invalidInterval: "Choose a video range of up to twenty seconds."
        case .invalidPoint: "Choose a point inside the video."
        case .invalidSourceDimensions: "This video is too small for ball tracking."
        case .seedUnavailable: "The selected frame does not match the source video."
        case .resourceIdentityMismatch: "Ball tracking resources failed their integrity check."
        case .sourceUnavailable: "The selected video could not be read."
        case .processingFailed: "Tracking could not finish for this part of the video."
        }
    }
}

/// One serial, off-main-actor operation. Models are local variables and are
/// released after the operation; the service never retains media or predictions.
actor EdgeTAMTrackingService {
    private let bundle: Bundle
    private var operationInProgress = false

    init(bundle: Bundle = .main) { self.bundle = bundle }

    func track(
        url: URL,
        interval: ClosedRange<Double>,
        seedPTS: Double,
        normalisedPoint: EdgeTAMTrackingPoint,
        progress: (@Sendable (EdgeTAMTrackingProgress) -> Void)? = nil
    ) async throws -> EdgeTAMTrackingResult {
        guard !operationInProgress else { throw EdgeTAMTrackingError.busy }
        guard interval.lowerBound.isFinite, interval.upperBound.isFinite,
              interval.lowerBound >= 0, interval.upperBound > interval.lowerBound,
              interval.upperBound - interval.lowerBound <= 20 else {
            throw EdgeTAMTrackingError.invalidInterval
        }
        guard normalisedPoint.x.isFinite, normalisedPoint.y.isFinite,
              (0..<1).contains(normalisedPoint.x), (0..<1).contains(normalisedPoint.y) else {
            throw EdgeTAMTrackingError.invalidPoint
        }
        guard seedPTS.isFinite, interval.contains(seedPTS) else { throw EdgeTAMTrackingError.seedUnavailable }
        guard url.isFileURL else { throw EdgeTAMTrackingError.sourceUnavailable }
        operationInProgress = true
        defer { operationInProgress = false }
        let started = ProcessInfo.processInfo.systemUptime
        do {
            try Task.checkCancellation()
            progress?(.init(stage: .validatingResources, completedCanonicalFrames: 0, totalFrames: nil))
            let resources = try resolveResources()
            progress?(.init(stage: .readingFrames, completedCanonicalFrames: 0, totalFrames: nil))
            let frames: EdgeTAMDirectVideoFrames
            do { frames = try await EdgeTAMDirectVideoFrames.open(url: url, sourceInterval: interval) }
            catch is CancellationError { throw CancellationError() }
            catch { throw EdgeTAMTrackingError.sourceUnavailable }
            defer { frames.close() }
            guard frames.sourceWidth >= 512, frames.sourceHeight >= 512,
                  !frames.frameTimes.isEmpty,
                  frames.frameTimes.count == frames.sourceFrameIndices.count,
                  frames.frameTimes.allSatisfy({ $0.isFinite && interval.contains($0) }),
                  zip(frames.frameTimes, frames.frameTimes.dropFirst()).allSatisfy({ $0 < $1 }) else {
                throw EdgeTAMTrackingError.invalidSourceDimensions
            }
            guard let seedIndex = frames.frameTimes.indices.min(by: {
                abs(frames.frameTimes[$0] - seedPTS) < abs(frames.frameTimes[$1] - seedPTS)
            }), abs(frames.frameTimes[seedIndex] - seedPTS) <= 0.001 else {
                throw EdgeTAMTrackingError.seedUnavailable
            }
            try Task.checkCancellation()
            progress?(.init(stage: .loadingModels, completedCanonicalFrames: 0, totalFrames: frames.frameTimes.count))
            let components = try EdgeTAMCoreMLComponents(packageURLs: resources.modelURLs)
            let tracker = EdgeTAMAdaptiveTracker(components: components, constants: resources.constants)
            var canonicalIndices = Set<Int>()
            progress?(.init(stage: .tracking, completedCanonicalFrames: 0, totalFrames: frames.frameTimes.count))
            let result = try tracker.track(
                frameTimes: frames.frameTimes, sourceWidth: frames.sourceWidth, sourceHeight: frames.sourceHeight,
                seedIndex: seedIndex,
                point: (normalisedPoint.x * Double(frames.sourceWidth), normalisedPoint.y * Double(frames.sourceHeight)),
                maximumSourceTimeGapSeconds: 0.20,
                frameProvider: { index, crop in
                    defer { frames.discardCachedFrame() }
                    return try frames.tensor(index: index, crop: crop)
                },
                observer: { observation in
                    try Task.checkCancellation()
                    if observation.kind == "canonical", canonicalIndices.insert(observation.index).inserted {
                        progress?(.init(stage: .tracking, completedCanonicalFrames: canonicalIndices.count,
                                        totalFrames: frames.frameTimes.count))
                    }
                }
            )
            try Task.checkCancellation()
            let records = try result.canonical.map { record -> EdgeTAMTrackingRecord in
                guard frames.frameTimes.indices.contains(record.index),
                      record.timestamp == frames.frameTimes[record.index],
                      let direction = EdgeTAMTrackingDirection(rawValue: record.direction) else {
                    throw EdgeTAMTrackingError.processingFailed
                }
                let point: EdgeTAMTrackingPoint?
                if record.visible {
                    guard let x = record.centroidX, let y = record.centroidY, x.isFinite, y.isFinite,
                          (0..<Double(frames.sourceWidth)).contains(x),
                          (0..<Double(frames.sourceHeight)).contains(y) else {
                        throw EdgeTAMTrackingError.processingFailed
                    }
                    point = .init(x: x / Double(frames.sourceWidth), y: y / Double(frames.sourceHeight))
                } else {
                    guard record.centroidX == nil, record.centroidY == nil else {
                        throw EdgeTAMTrackingError.processingFailed
                    }
                    point = nil
                }
                return .init(intervalFrameIndex: record.index, sourceFrameIndex: frames.sourceFrameIndices[record.index],
                             sourcePTS: record.timestamp, visible: record.visible, normalisedPoint: point,
                             objectScoreLogit: record.objectScoreLogit, segmentID: record.segmentID, direction: direction)
            }
            var terminations: [EdgeTAMTrackingDirection: EdgeTAMTrackingTermination] = [:]
            for (key, value) in result.terminations {
                guard let direction = EdgeTAMTrackingDirection(rawValue: key) else {
                    throw EdgeTAMTrackingError.processingFailed
                }
                terminations[direction] = .init(reason: value.reason, timestamp: value.timestamp,
                    firstUnprocessedTimestamp: value.firstUnprocessedTimestamp, lastObservedTimestamp: value.lastObservedTimestamp)
            }
            let budgetLimited = terminations.values.contains {
                $0.reason == "propagation_time_limit" || $0.reason == "automatic_reseed_limit"
            }
            progress?(.init(stage: .finished, completedCanonicalFrames: records.count, totalFrames: frames.frameTimes.count))
            return .init(status: budgetLimited ? .partialBudgetLimit : .completed,
                         sourceWidth: frames.sourceWidth, sourceHeight: frames.sourceHeight, interval: interval,
                         frameTimes: frames.frameTimes, sourceFrameIndices: frames.sourceFrameIndices,
                         seedPTS: frames.frameTimes[seedIndex], seedSourceFrameIndex: frames.sourceFrameIndices[seedIndex],
                         seedNormalisedPoint: normalisedPoint, records: records, terminations: terminations,
                         automaticReseedCount: result.automaticReseedCount, gapRecoveryCount: result.gapRecoveryCount,
                         modelIdentity: resources.identity, elapsedSeconds: ProcessInfo.processInfo.systemUptime - started)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as EdgeTAMTrackingError {
            throw error
        } catch {
            throw EdgeTAMTrackingError.processingFailed
        }
    }

    /// The build may omit all resources. Their absence is a normal unavailable
    /// state; resources are never fetched or compiled at runtime on the phone.
    private struct IdentityManifest: Decodable {
        let schemaVersion: Int
        let modelVersion: String
        let constantsResource: String
        let constantsSHA256: String
        let modelResources: [String: String]
        let expectedCompiledModelSHA256: [String: String]
    }

    private struct Resources {
        let modelURLs: [String: URL]
        let constants: EdgeTAMLearnedConstants
        let identity: EdgeTAMTrackingModelIdentity
    }

    private func resolveResources() throws -> Resources {
        let manifestURL = try resource("edgetam-model-identity.json", extension: "json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest: IdentityManifest
        do { manifest = try JSONDecoder().decode(IdentityManifest.self, from: manifestData) }
        catch { throw EdgeTAMTrackingError.resourceIdentityMismatch }
        let keys: Set<String> = ["image", "attention", "point", "noPoint", "memory"]
        guard manifest.schemaVersion == 1, !manifest.modelVersion.isEmpty,
              manifest.constantsResource == "edgetam-constants.json",
              Set(manifest.modelResources.keys) == keys,
              Set(manifest.expectedCompiledModelSHA256.keys) == keys else {
            throw EdgeTAMTrackingError.resourceIdentityMismatch
        }
        var urls: [String: URL] = [:]
        var hashes: [String: String] = [:]
        for key in keys.sorted() {
            try Task.checkCancellation()
            let url = try resource(manifest.modelResources[key]!, extension: "mlmodelc")
            let actual = try Self.digest(url)
            guard actual == Self.normalisedHash(manifest.expectedCompiledModelSHA256[key]!) else {
                throw EdgeTAMTrackingError.resourceIdentityMismatch
            }
            urls[key] = url
            hashes[key] = actual
        }
        let constantsURL = try resource(manifest.constantsResource, extension: "json")
        let constantsHash = try Self.digest(constantsURL)
        guard constantsHash == Self.normalisedHash(manifest.constantsSHA256) else {
            throw EdgeTAMTrackingError.resourceIdentityMismatch
        }
        let constants = try JSONDecoder().decode(EdgeTAMLearnedConstants.self, from: Data(contentsOf: constantsURL))
        try constants.validate()
        return Resources(modelURLs: urls, constants: constants,
            identity: .init(modelVersion: manifest.modelVersion,
                manifestSHA256: "sha256:" + Self.hex(SHA256.hash(data: manifestData)),
                constantsSHA256: constantsHash, compiledModelSHA256: hashes))
    }

    private func resource(_ name: String, extension requiredExtension: String) throws -> URL {
        let file = name as NSString
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\"),
              file.pathExtension == requiredExtension else {
            throw EdgeTAMTrackingError.resourceIdentityMismatch
        }
        guard let url = bundle.url(forResource: file.deletingPathExtension, withExtension: requiredExtension) else {
            throw EdgeTAMTrackingError.unavailable
        }
        return url
    }

    /// Matches the diagnostic tree digest: sorted non-hidden relative paths,
    /// a tab, streaming file SHA256, then newline. The manifest is streamed too.
    private static func digest(_ url: URL) throws -> String {
        var directory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else {
            throw EdgeTAMTrackingError.unavailable
        }
        if !directory.boolValue { return "sha256:" + (try fileDigest(url)) }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            throw EdgeTAMTrackingError.resourceIdentityMismatch
        }
        let root = url.standardizedFileURL.path + "/"
        let files = try enumerator.compactMap { item -> URL? in
            guard let file = item as? URL else { return nil }
            return try file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true ? nil : file
        }.sorted { $0.path < $1.path }
        guard !files.isEmpty else { throw EdgeTAMTrackingError.resourceIdentityMismatch }
        var treeDigest = SHA256()
        for file in files {
            try Task.checkCancellation()
            let path = file.standardizedFileURL.path
            guard path.hasPrefix(root) else { throw EdgeTAMTrackingError.resourceIdentityMismatch }
            let relative = String(path.dropFirst(root.count))
            treeDigest.update(data: Data("\(relative)\t\(try fileDigest(file))\n".utf8))
        }
        return "sha256:" + hex(treeDigest.finalize())
    }

    private static func fileDigest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while true {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { break }
            digest.update(data: data)
        }
        return hex(digest.finalize())
    }

    private static func normalisedHash(_ value: String) -> String {
        let value = value.lowercased()
        return value.hasPrefix("sha256:") ? value : "sha256:" + value
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
