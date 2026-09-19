@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Darwin

// This executable is deliberately a thin oracle harness. It constructs the production
// ReviewCandidate/ShotVideoTrace types and calls the production ShotVideoExporter. It does not
// copy, fit, smooth, retime or otherwise reimplement the renderer.

private struct ReferenceRoot: Decodable {
    let schemaVersion: String
    let clipId: String
    let sourceHash: String
    let width: Int
    let height: Int
    let coordinateOrigin: String
    let coordinateSpace: String
    let annotationVersion: String
    let annotationMethod: String
    let frames: [ReferenceFrame]
}

private struct ReferenceFrame: Decodable {
    let timestamp: Double
    let sourceFrameIndex: Int?
    let x: Double?
    let y: Double?
    let visibility: String
    let reviewStatus: String
    let uncertaintyPx: Double?
}

private struct PredictionRoot: Decodable {
    let schemaVersion: String
    let clipId: String
    let sourceHash: String
    let width: Int
    let height: Int
    let coordinateOrigin: String
    let coordinateSpace: String
    let mode: String
    let promptCount: Int
    let pointPromptCount: Int
    let timingPromptCount: Int
    let correctionCount: Int
    let automaticReseedCount: Int?
    let parameters: [String: JSONValue]?
    let maximumSourceTimeGapSeconds: Double?
    let gapPolicy: JSONValue?
    let samples: [PredictionFrame]
    let assistance: [String: JSONValue]
    let model: JSONValue
    let upstream_commit: String?
    let checkpoint_sha256: String?
    let adapterCodeSHA256: String?
    let configurationSHA256: String?
    let fixedAdapterHelperSHA256: String?

    var modelProvenance: [String: JSONValue] {
        var result: [String: JSONValue]
        switch model {
        case let .object(value): result = value
        case let .string(name) where !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            result = ["name": .string(name)]
        default: return [:]
        }
        for (key, value) in [
            ("upstreamCommit", upstream_commit),
            ("checkpointSHA256", checkpoint_sha256),
            ("adapterCodeSHA256", adapterCodeSHA256),
            ("configurationSHA256", configurationSHA256),
            ("fixedAdapterHelperSHA256", fixedAdapterHelperSHA256)
        ] {
            if let value { result[key] = .string(value) }
        }
        return result
    }

    var algorithmParameters: [String: JSONValue]? {
        guard var result = parameters else { return nil }
        if let maximumSourceTimeGapSeconds {
            result["maximumSourceTimeGapSeconds"] = .number(maximumSourceTimeGapSeconds)
            // Early gap experiments retain a stale default-policy string in
            // their frozen input. Preserve it, and expose the explicit active policy.
            if let gapPolicy { result["activeGapPolicy"] = gapPolicy }
        }
        return result
    }
}

private struct PredictionFrame: Decodable {
    let timestamp: Double
    let sourceFrameIndex: Int
    let x: Double?
    let y: Double?
    let visible: Bool
}

private enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

private struct RenderFrame {
    let timestamp: Double
    let sourceFrameIndex: Int
    let x: Double
    let y: Double
}

/// One frame in complete source decode order. The index is the ordinal used by
/// `EdgeTAMDirectVideoFrames`, including frames before a selected interval.
private struct SourceFramePresentation {
    let sourceFrameIndex: Int
    let timestamp: Double
}

private struct SourceOutput: Encodable {
    let clipId: String
    let sourceHash: String
    let width: Int
    let height: Int
    let trimStart: Double
    let trimEnd: Double
    let sourceFrameStart: Int
    let sourceFrameEnd: Int
}

private struct SampleOutput: Encodable {
    let sourceTimestamp: Double
    let outputRequestedTimestamp: Double
    let outputActualTimestamp: Double
    let outputActualSourceTimestamp: Double
    let sourceTimestampDelta: Double
    let sourceFrameIndex: Int
    let normalizedX: Double
    let normalizedY: Double
    let canvasX: Double
    let canvasY: Double
    let image: String
}

private struct OutputTiming: Encodable {
    let frameCount: Int
    let durationSeconds: Double
    let firstPresentationTimestamp: Double?
    let lastPresentationTimestamp: Double?
}

private struct RendererManifest: Encodable {
    let schemaVersion: String
    let artifactType: String
    let referenceDriven: Bool
    let automaticPrediction: Bool
    let detectorPrediction: Bool
    let assisted: Bool
    let autonomousAcquisition: Bool
    let inputKind: String
    let clipId: String
    let sourceHash: String
    let referenceHash: String?
    let predictionHash: String?
    let rendererHash: String
    let annotationVersion: String
    let annotationMethod: String
    let annotationProvenance: String
    let assistance: [String: JSONValue]?
    let modelProvenance: [String: JSONValue]?
    let promptCount: Int?
    let pointPromptCount: Int?
    let timingPromptCount: Int?
    let correctionCount: Int?
    let automaticReseedCount: Int?
    let algorithmParameters: [String: JSONValue]?
    let source: SourceOutput
    let format: String
    let canvasWidth: Int
    let canvasHeight: Int
    let fittedRect: [Double]
    let burnedLabel: String
    let burnedLabelInterpretation: String
    let selectedFrameCount: Int
    let selectedTimestampStart: Double
    let selectedTimestampEnd: Double
    let output: String
    let outputTiming: OutputTiming
    let samples: [SampleOutput]
}

private enum OracleError: LocalizedError {
    case invalidArguments(String)
    case invalidReference(String)
    case exportFailed(String)
    case outputOutsideRepository

    var errorDescription: String? {
        switch self {
        case let .invalidArguments(message): message
        case let .invalidReference(message): message
        case let .exportFailed(message): message
        case .outputOutsideRepository: "Renderer output must be outside the repository."
        }
    }
}

private struct Arguments {
    let sourceURL: URL
    let referenceURL: URL?
    let predictionURL: URL?
    let outputDirectory: URL
    let repoRoot: URL
    let sourceHash: String
    let inputHash: String
    let rendererHash: String

    init() throws {
        var values: [String: String] = [:]
        var index = 1
        while index < CommandLine.arguments.count {
            let key = CommandLine.arguments[index]
            guard key.hasPrefix("--"), index + 1 < CommandLine.arguments.count else {
                throw OracleError.invalidArguments("Expected --key value arguments.")
            }
            values[key] = CommandLine.arguments[index + 1]
            index += 2
        }
        func required(_ key: String) throws -> String {
            guard let value = values[key], !value.isEmpty else {
                throw OracleError.invalidArguments("Missing \(key).")
            }
            return value
        }
        sourceURL = URL(fileURLWithPath: try required("--source"), isDirectory: false).standardizedFileURL.resolvingSymlinksInPath()
        referenceURL = values["--reference"].map { URL(fileURLWithPath: $0, isDirectory: false).standardizedFileURL.resolvingSymlinksInPath() }
        predictionURL = values["--prediction"].map { URL(fileURLWithPath: $0, isDirectory: false).standardizedFileURL.resolvingSymlinksInPath() }
        outputDirectory = URL(fileURLWithPath: try required("--output-dir"), isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        repoRoot = URL(fileURLWithPath: try required("--repo-root"), isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        sourceHash = try required("--source-hash")
        let referenceHash = values["--reference-hash"]
        let predictionHash = values["--prediction-hash"]
        let hasMatchedReference = referenceURL != nil && referenceHash != nil
            && predictionURL == nil && predictionHash == nil
        let hasMatchedPrediction = predictionURL != nil && predictionHash != nil
            && referenceURL == nil && referenceHash == nil
        guard hasMatchedReference != hasMatchedPrediction else {
            throw OracleError.invalidArguments("Pass exactly one of --reference/--prediction and its matching hash.")
        }
        inputHash = hasMatchedReference ? referenceHash! : predictionHash!
        rendererHash = try required("--renderer-hash")
        guard sourceHash.hasPrefix("sha256:"), inputHash.hasPrefix("sha256:"), rendererHash.hasPrefix("sha256:") else {
            throw OracleError.invalidArguments("All hashes must use the sha256: prefix.")
        }
    }
}

private struct SelectedBlock {
    let frames: [RenderFrame]

    var points: [NormalizedPoint] {
        frames.map { NormalizedPoint(x: $0.x, y: $0.y) }
    }

    var times: [Double] { frames.map(\.timestamp) }
}

@main
struct RendererOracle {
    static func main() async {
        do {
            let arguments = try Arguments()
            let manifest = try await run(arguments)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: arguments.outputDirectory.appendingPathComponent("manifest.json"), options: .atomic)
            print("Renderer oracle written: \(arguments.outputDirectory.path)")
        } catch {
            FileHandle.standardError.write(Data("Renderer oracle failed: \(error.localizedDescription)\n".utf8))
            exit(2)
        }
    }

    private static func run(_ arguments: Arguments) async throws -> RendererManifest {
        let compiledRepoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard arguments.repoRoot == compiledRepoRoot else {
            throw OracleError.invalidArguments("Caller repository root does not match the compiled harness repository.")
        }
        func isInsideRepository(_ url: URL) -> Bool {
            url == compiledRepoRoot || url.path.hasPrefix(compiledRepoRoot.path + "/")
        }
        let inputURL = arguments.referenceURL ?? arguments.predictionURL!
        guard !isInsideRepository(arguments.sourceURL),
              !isInsideRepository(inputURL),
              !isInsideRepository(arguments.outputDirectory) else {
            throw OracleError.outputOutsideRepository
        }
        guard FileManager.default.fileExists(atPath: arguments.sourceURL.path) else {
            throw OracleError.invalidArguments("Source video is not readable.")
        }
        let sourceAsset = AVURLAsset(url: arguments.sourceURL)
        let sourceDuration = try await sourceAsset.load(.duration).seconds
        let sourceTrack = try await sourceAsset.loadTracks(withMediaType: .video).first
        guard let sourceTrack else { throw OracleError.invalidReference("Source video track is unavailable.") }
        let naturalSize = try await sourceTrack.load(.naturalSize)
        let transform = try await sourceTrack.load(.preferredTransform)
        let display = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let sourceWidth = Int(abs(display.width).rounded())
        let sourceHeight = Int(abs(display.height).rounded())
        let sourceTimeline = try await presentationTimes(of: sourceAsset, track: sourceTrack)

        let inputData = try Data(contentsOf: inputURL)
        let reference: ReferenceRoot?
        let prediction: PredictionRoot?
        if arguments.referenceURL != nil {
            reference = try JSONDecoder().decode(ReferenceRoot.self, from: inputData)
            prediction = nil
        } else {
            reference = nil
            prediction = try JSONDecoder().decode(PredictionRoot.self, from: inputData)
        }
        let clipId = reference?.clipId ?? prediction!.clipId
        let isPrediction = prediction != nil
        let inputWidth = reference?.width ?? prediction!.width
        let inputHeight = reference?.height ?? prediction!.height
        let inputSourceHash = reference?.sourceHash ?? prediction!.sourceHash
        guard clipId.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", options: .regularExpression) != nil,
              inputWidth > 0, inputHeight > 0,
              inputSourceHash == arguments.sourceHash,
              inputWidth == sourceWidth, inputHeight == sourceHeight else {
            throw OracleError.invalidReference("Input metadata does not match the source identity or upright dimensions.")
        }
        let block: SelectedBlock
        let assistance: [String: JSONValue]?
        let modelProvenance: [String: JSONValue]?
        let annotationVersion: String
        let annotationMethod: String
        let annotationProvenance: String
        if let reference {
            guard reference.schemaVersion == "1.0", reference.coordinateOrigin == "top-left", reference.coordinateSpace == "normalized" else {
                throw OracleError.invalidReference("Reference coordinate contract is invalid.")
            }
            guard reference.frames.allSatisfy({ frame in
                guard let sourceFrameIndex = frame.sourceFrameIndex else { return true }
                return sourceFrameMatches(
                    sourceFrameIndex: sourceFrameIndex,
                    timestamp: frame.timestamp,
                    timeline: sourceTimeline
                )
            }) else {
                throw OracleError.invalidReference("Reference frame indices do not match the source PTS manifest within 1 ms.")
            }
            block = try longestReviewedVisibleBlock(reference.frames.map { frame in
                let valid = frame.visibility == "visible"
                    && (frame.reviewStatus == "agent-reviewed" || frame.reviewStatus == "human-verified")
                    && frame.sourceFrameIndex != nil
                    && frame.x.map({ $0.isFinite && (0...1).contains($0) }) == true
                    && frame.y.map({ $0.isFinite && (0...1).contains($0) }) == true
                return RenderFrame(
                    timestamp: frame.timestamp,
                    sourceFrameIndex: valid ? frame.sourceFrameIndex! : -1,
                    x: valid ? frame.x! : .nan,
                    y: valid ? frame.y! : .nan
                )
            })
            guard block.points.count >= 3 else { throw OracleError.invalidReference("Reference does not contain three contiguous reviewed visible points.") }
            assistance = nil
            modelProvenance = nil
            annotationVersion = reference.annotationVersion
            annotationMethod = reference.annotationMethod
            annotationProvenance = "Agent-reviewed reference points; independent human verification remains outstanding."
        } else {
            guard let prediction else { throw OracleError.invalidReference("Prediction input is unavailable.") }
            guard prediction.schemaVersion == "1.0", prediction.coordinateOrigin == "top-left", prediction.coordinateSpace == "normalized",
                  prediction.mode == "assisted", prediction.promptCount >= 1,
                  prediction.pointPromptCount >= 1, prediction.timingPromptCount >= 0,
                  prediction.promptCount == prediction.pointPromptCount + prediction.timingPromptCount,
                  prediction.correctionCount >= 0, !prediction.assistance.isEmpty,
                  !prediction.modelProvenance.isEmpty else {
                throw OracleError.invalidReference("Prediction assistance or provenance metadata is incomplete.")
            }
            guard prediction.samples.enumerated().allSatisfy({ offset, frame in
                let previousTimestamp = offset > 0 ? prediction.samples[offset - 1].timestamp : -.infinity
                let previousIndex = offset > 0 ? prediction.samples[offset - 1].sourceFrameIndex : -1
                let validPoint = !frame.visible || (
                    frame.x.map { $0.isFinite && (0...1).contains($0) } == true
                    && frame.y.map { $0.isFinite && (0...1).contains($0) } == true
                )
                return frame.timestamp.isFinite && frame.timestamp > previousTimestamp
                    && frame.sourceFrameIndex > previousIndex && validPoint
                    && sourceFrameMatches(
                        sourceFrameIndex: frame.sourceFrameIndex,
                        timestamp: frame.timestamp,
                        timeline: sourceTimeline
                    )
            }) else {
                throw OracleError.invalidReference("Prediction samples do not match the source PTS manifest within 1 ms.")
            }
            block = try longestPredictionVisibleBlock(prediction.samples)
            guard block.points.count >= 3 else { throw OracleError.invalidReference("Prediction does not contain three contiguous nonempty visible points.") }
            assistance = prediction.assistance
            modelProvenance = prediction.modelProvenance
            annotationVersion = prediction.schemaVersion
            annotationMethod = "detector-prediction"
            annotationProvenance = "Assisted detector prediction; supplied point, crop, and interval metadata are retained. This is not fully automatic and is not human-ground-truth evidence."
        }

        guard sourceDuration.isFinite, sourceDuration > block.times.last! else {
            throw OracleError.invalidReference("Input block ends after the source duration.")
        }
        let medianStep = medianStep(block.times)
        let trimStart = block.times.first!
        let trimEnd = min(sourceDuration, block.times.last! + max(0.033, medianStep))
        guard trimEnd > trimStart else { throw OracleError.invalidReference("Reference block has no exportable duration.") }

        guard let path = EvidenceAnchoredFlightPath(
            observedPoints: block.points,
            observedPresentationTimes: block.times,
            confidence: 1
        ) else {
            throw OracleError.invalidReference("Production timed path rejected the input block.")
        }
        let candidate = ReviewCandidate(
            ordinal: 1,
            impactTime: trimStart,
            sourceDuration: sourceDuration,
            classification: .likelyShot,
            confidence: .high,
            evidence: ["reference-oracle"],
            decision: .kept,
            tracerAvailable: true,
            evidenceAnchoredPath: path,
            tracerSource: .observed,
            tracerConfidence: 1,
            observedTracerPointCount: block.points.count,
            usesFullSourceRange: false
        )
        guard let trace = ShotVideoTrace(candidate: candidate, mode: .automatic) else {
            throw OracleError.invalidReference("Production ShotVideoTrace rejected the input block.")
        }
        let edit = ShotVideoEdit(trimStart: trimStart, trimEnd: trimEnd, format: .original, overlay: .automatic)
        let request = ShotVideoExportRequest(sourceURL: arguments.sourceURL, edit: edit, trace: trace)
        let exporter = ShotVideoExporter()
        let exportedURL: URL
        do {
            exportedURL = try await exporter.export(request) { _ in }
        } catch {
            throw OracleError.exportFailed(String(describing: error))
        }

        try FileManager.default.createDirectory(at: arguments.outputDirectory, withIntermediateDirectories: true)
        let outputName = "\(clipId).\(isPrediction ? "assisted-prediction" : "reference-oracle").mp4"
        let outputURL = arguments.outputDirectory.appendingPathComponent(outputName)
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.copyItem(at: exportedURL, to: outputURL)
        try? FileManager.default.removeItem(at: exportedURL)

        let sourceAspectRatio = abs(display.width / display.height)
        let canvas = edit.format.renderSize(sourceAspectRatio: sourceAspectRatio)
        let fitted = ShotVideoLayout.fittedRect(sourceAspectRatio: sourceAspectRatio, canvasSize: canvas)

        let outputAsset = AVURLAsset(url: outputURL)
        let outputTiming = try await timing(of: outputAsset)
        let samples = try extractSamples(
            outputAsset: outputAsset,
            outputDirectory: arguments.outputDirectory,
            renderFrames: block.frames,
            trimStart: trimStart,
            sourceRect: fitted
        )
        return RendererManifest(
            schemaVersion: "1.0",
            artifactType: isPrediction ? "assisted-detector-production-render" : "reference-driven-production-render-oracle",
            referenceDriven: !isPrediction,
            automaticPrediction: false,
            detectorPrediction: isPrediction,
            assisted: isPrediction,
            autonomousAcquisition: false,
            inputKind: isPrediction ? "canonical-model-prediction" : "reviewed-reference",
            clipId: clipId,
            sourceHash: arguments.sourceHash,
            referenceHash: reference != nil ? arguments.inputHash : nil,
            predictionHash: prediction != nil ? arguments.inputHash : nil,
            rendererHash: arguments.rendererHash,
            annotationVersion: annotationVersion,
            annotationMethod: annotationMethod,
            annotationProvenance: annotationProvenance,
            assistance: assistance,
            modelProvenance: modelProvenance,
            promptCount: prediction?.promptCount,
            pointPromptCount: prediction?.pointPromptCount,
            timingPromptCount: prediction?.timingPromptCount,
            correctionCount: prediction?.correctionCount,
            automaticReseedCount: prediction?.automaticReseedCount,
            algorithmParameters: prediction?.algorithmParameters,
            source: SourceOutput(
                clipId: clipId,
                sourceHash: arguments.sourceHash,
                width: inputWidth,
                height: inputHeight,
                trimStart: trimStart,
                trimEnd: trimEnd,
                sourceFrameStart: block.frames.first?.sourceFrameIndex ?? -1,
                sourceFrameEnd: block.frames.last?.sourceFrameIndex ?? -1
            ),
            format: edit.format.rawValue,
            canvasWidth: Int(canvas.width),
            canvasHeight: Int(canvas.height),
            fittedRect: [fitted.minX, fitted.minY, fitted.width, fitted.height],
            burnedLabel: trace.label,
            burnedLabelInterpretation: isPrediction
                ? "Production exporter label retained unchanged; this file contains assisted detector predictions with supplied point/crop/interval metadata and is not fully automatic."
                : "Production exporter label retained for renderer verification; this file is reference-driven and is not an automatic prediction.",
            selectedFrameCount: block.frames.count,
            selectedTimestampStart: block.times.first!,
            selectedTimestampEnd: block.times.last!,
            output: outputName,
            outputTiming: outputTiming,
            samples: samples
        )
    }

    private static func longestReviewedVisibleBlock(_ frames: [RenderFrame]) throws -> SelectedBlock {
        try longestContiguousBlock(frames, error: "No contiguous reviewed visible reference block found.")
    }

    private static func longestPredictionVisibleBlock(_ frames: [PredictionFrame]) throws -> SelectedBlock {
        let renderFrames = frames.map { frame in
            let valid = frame.visible
                && frame.x.map({ $0.isFinite && (0...1).contains($0) }) == true
                && frame.y.map({ $0.isFinite && (0...1).contains($0) }) == true
            return RenderFrame(
                timestamp: frame.timestamp,
                sourceFrameIndex: valid ? frame.sourceFrameIndex : -1,
                x: valid ? frame.x! : .nan,
                y: valid ? frame.y! : .nan
            )
        }
        return try longestContiguousBlock(renderFrames, error: "No contiguous nonempty prediction block found.")
    }

    private static func longestContiguousBlock(_ frames: [RenderFrame], error: String) throws -> SelectedBlock {
        var runs: [[RenderFrame]] = []
        var current: [RenderFrame] = []
        for frame in frames {
            let valid = frame.timestamp.isFinite && frame.sourceFrameIndex >= 0
                && frame.x.isFinite && (0...1).contains(frame.x)
                && frame.y.isFinite && (0...1).contains(frame.y)
            let adjacent = current.last.map { frame.sourceFrameIndex == $0.sourceFrameIndex + 1 } ?? true
            if valid && adjacent {
                current.append(frame)
            } else {
                if !current.isEmpty { runs.append(current) }
                current = valid ? [frame] : []
            }
        }
        if !current.isEmpty { runs.append(current) }
        guard let best = runs.max(by: { $0.count < $1.count }) else { throw OracleError.invalidReference(error) }
        return SelectedBlock(frames: best)
    }

    private static func medianStep(_ times: [Double]) -> Double {
        let steps = zip(times, times.dropFirst()).map { $1 - $0 }.filter { $0 > 0 }
        guard !steps.isEmpty else { return 1.0 / 30.0 }
        let sorted = steps.sorted()
        return sorted.count.isMultiple(of: 2)
            ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
            : sorted[sorted.count / 2]
    }

    private static let sourcePTSTolerance = 0.001

    private static func sourceFrameMatches(
        sourceFrameIndex: Int,
        timestamp: Double,
        timeline: [SourceFramePresentation]
    ) -> Bool {
        guard timestamp.isFinite, timeline.indices.contains(sourceFrameIndex) else { return false }
        let sourceFrame = timeline[sourceFrameIndex]
        return sourceFrame.sourceFrameIndex == sourceFrameIndex
            && abs(sourceFrame.timestamp - timestamp) <= sourcePTSTolerance
    }

    private static func presentationTimes(
        of asset: AVAsset,
        track: AVAssetTrack
    ) async throws -> [SourceFramePresentation] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        guard reader.canAdd(output) else { throw OracleError.invalidReference("Cannot inspect source PTS.") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? OracleError.invalidReference("Cannot read source PTS.") }
        var timeline: [SourceFramePresentation] = []
        var sourceFrameIndex = 0
        var previousPTS: Double?
        while let sample = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            guard CMSampleBufferGetImageBuffer(sample) != nil else {
                throw OracleError.invalidReference("Source frame decode returned no image buffer.")
            }
            guard pts.isFinite, previousPTS.map({ pts > $0 }) ?? true else {
                throw OracleError.invalidReference("Source PTS decode order is not finite and strictly increasing.")
            }
            timeline.append(SourceFramePresentation(sourceFrameIndex: sourceFrameIndex, timestamp: pts))
            previousPTS = pts
            sourceFrameIndex += 1
        }
        guard reader.status != .failed else { throw reader.error ?? OracleError.invalidReference("Source PTS inspection failed.") }
        guard !timeline.isEmpty else { throw OracleError.invalidReference("Source video contains no decoded frames.") }
        return timeline
    }

    private static func timing(of asset: AVAsset) async throws -> OutputTiming {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw OracleError.exportFailed("Output video track is unavailable.")
        }
        let duration = try await asset.load(.duration).seconds
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 60_000))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        guard reader.canAdd(output) else { throw OracleError.exportFailed("Cannot inspect output frames.") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? OracleError.exportFailed("Cannot read output frames.") }
        var timestamps: [Double] = []
        while let sample = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if pts.isFinite, pts >= -0.001, pts <= duration + 0.001 { timestamps.append(max(0, pts)) }
        }
        guard reader.status != .failed else { throw reader.error ?? OracleError.exportFailed("Output frame inspection failed.") }
        let sorted = timestamps.sorted()
        return OutputTiming(frameCount: sorted.count, durationSeconds: duration, firstPresentationTimestamp: sorted.first, lastPresentationTimestamp: sorted.last)
    }

    private static func extractSamples(
        outputAsset: AVAsset,
        outputDirectory: URL,
        renderFrames: [RenderFrame],
        trimStart: Double,
        sourceRect: CGRect
    ) throws -> [SampleOutput] {
        let generator = AVAssetImageGenerator(asset: outputAsset)
        generator.appliesPreferredTrackTransform = true
        let halfFrame = CMTime(value: 1, timescale: 60)
        generator.requestedTimeToleranceBefore = halfFrame
        generator.requestedTimeToleranceAfter = halfFrame
        let selected = [renderFrames.first, renderFrames[renderFrames.count / 2], renderFrames.last].compactMap { $0 }
        var results: [SampleOutput] = []
        for (index, frame) in selected.enumerated() {
            let x = frame.x
            let y = frame.y
            let requested = max(0, frame.timestamp - trimStart)
            var actual = CMTime.zero
            let image = try generator.copyCGImage(at: CMTime(seconds: requested, preferredTimescale: 60_000), actualTime: &actual)
            let filename = String(format: "sample-%02d-%.6f.png", index, frame.timestamp)
            let url = outputDirectory.appendingPathComponent(filename)
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw OracleError.exportFailed("Cannot create sample image.")
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw OracleError.exportFailed("Cannot write sample image.") }
            let canvasPoint = ShotVideoLayout.point(NormalizedPoint(x: x, y: y), in: sourceRect)
            results.append(SampleOutput(
                sourceTimestamp: frame.timestamp,
                outputRequestedTimestamp: requested,
                outputActualTimestamp: actual.seconds,
                outputActualSourceTimestamp: trimStart + actual.seconds,
                sourceTimestampDelta: (trimStart + actual.seconds) - frame.timestamp,
                sourceFrameIndex: frame.sourceFrameIndex,
                normalizedX: x,
                normalizedY: y,
                canvasX: canvasPoint.x,
                canvasY: canvasPoint.y,
                image: filename
            ))
        }
        return results
    }
}
