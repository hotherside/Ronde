@preconcurrency import AVFoundation
import CryptoKit
import Darwin
import Foundation

private struct Arguments {
    /// `#filePath` is embedded by Swift at compilation, so direct invocation of the generated
    /// binary retains the repository boundary even when the shell wrapper is bypassed.
    private static let sourceRepositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .resolvingSymlinksInPath()
        .standardizedFileURL

    let mediaURL: URL
    let modelURL: URL
    let outputDirectory: URL
    let impactTime: TimeInterval
    let sourceRevision: String
    let sourceHashes: [String: String]
    let mediaSHA256: String
    let modelSHA256: String
    let modelWeightSHA256: String?
    let variant: String?
    let configuration: WASBGolfBallTrackingConfiguration

    init() throws {
        var values: [String: [String]] = [:]
        var index = 1
        let commandLine = CommandLine.arguments
        while index < commandLine.count {
            let key = commandLine[index]
            guard key.hasPrefix("--"), index + 1 < commandLine.count else {
                throw HarnessError.invalidArguments
            }
            values[key, default: []].append(commandLine[index + 1])
            index += 2
        }

        func required(_ key: String) throws -> String {
            guard let value = values[key]?.last, !value.isEmpty else {
                throw HarnessError.invalidArguments
            }
            return value
        }

        let media = try required("--media")
        let model = try required("--model")
        let output = try required("--output-dir")
        guard let impact = Double(try required("--impact")), impact.isFinite, impact >= 0 else {
            throw HarnessError.invalidArguments
        }
        let cadence = values["--cadence"]?.last.flatMap(Double.init) ?? (1.0 / 30.0)
        let reacquisition = values["--reacquisition"]?.last.flatMap(Double.init) ?? 0.28
        let peaksPerTile = values["--peaks-per-tile"]?.last.flatMap(Int.init) ?? 1
        guard (1...3).contains(peaksPerTile) else {
            throw HarnessError.invalidArguments
        }
        let tileOrigins = try (values["--tile-origin"] ?? []).map { value -> NormalizedPoint in
            let parts = value.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let x = Double(parts[0]), let y = Double(parts[1]),
                  x.isFinite, y.isFinite,
                  (0...1).contains(x), (0...1).contains(y) else {
                throw HarnessError.invalidArguments
            }
            return NormalizedPoint(x: x, y: y)
        }

        mediaURL = URL(fileURLWithPath: media)
        modelURL = URL(fileURLWithPath: model)
        outputDirectory = try Self.validatedExternalOutputDirectory(output)
        impactTime = impact
        sourceRevision = try required("--source-revision")
        mediaSHA256 = try required("--media-sha256")
        modelSHA256 = try required("--model-sha256")
        modelWeightSHA256 = values["--model-weight-sha256"]?.last
        variant = values["--variant"]?.last
        sourceHashes = Dictionary(uniqueKeysWithValues: (values["--source-hash"] ?? []).compactMap { value in
            let parts = value.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]))
        })
        configuration = WASBGolfBallTrackingConfiguration(
            maximumPostImpactDuration: 4,
            minimumPeakConfidence: 0.08,
            maximumCandidatesPerFrame: 30,
            maximumPeaksPerTile: peaksPerTile,
            diagnosticTileOrigins: tileOrigins.isEmpty ? nil : tileOrigins,
            analysisCadence: cadence,
            reacquisitionInterval: reacquisition
        )
    }

    private static func validatedExternalOutputDirectory(_ path: String) throws -> URL {
        let fileManager = FileManager.default
        var unresolved = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        var absentComponents: [String] = []
        while !fileManager.fileExists(atPath: unresolved.path) {
            let component = unresolved.lastPathComponent
            guard !component.isEmpty, unresolved.path != "/" else {
                throw HarnessError.unreadableOutput
            }
            absentComponents.append(component)
            unresolved.deleteLastPathComponent()
        }
        var resolved = unresolved.resolvingSymlinksInPath().standardizedFileURL
        for component in absentComponents.reversed() {
            resolved.appendPathComponent(component, isDirectory: true)
        }
        let root = sourceRepositoryRoot.path
        let output = resolved.path
        guard output != root, !output.hasPrefix(root + "/") else {
            throw HarnessError.outputInsideSourceRepository
        }
        return resolved
    }
}

private enum HarnessError: LocalizedError {
    case invalidArguments
    case unreadableOutput
    case outputInsideSourceRepository

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            "Invalid harness arguments. Use run-tracker.sh --help."
        case .unreadableOutput:
            "The requested external output directory cannot be written."
        case .outputInsideSourceRepository:
            "The requested output directory must be outside the source repository."
        }
    }
}

private struct SourceVideo: Encodable {
    /// Encoded track dimensions, retained for compatibility with existing private manifests.
    let nativeWidth: Int
    let nativeHeight: Int
    /// Display-oriented dimensions after the track's preferred transform is applied.
    let uprightWidth: Int
    let uprightHeight: Int
    let durationSeconds: Double
    let nominalFrameRate: Double
    let preferredTransform: [Double]
}

private struct RunManifest: Encodable {
    let schemaVersion: Int
    let coordinateSystem: String
    let sourceRevision: String
    let sourceHashes: [String: String]
    let sourceSHA256: String
    /// Deterministic SHA-256 over sorted relative file paths and per-file SHA-256 values.
    let modelSHA256: String
    let modelHashScope: String
    let sourceModelBundleSHA256: String
    let sourceModelWeightSHA256: String?
    let sourceVideo: SourceVideo
    let controlledImpactTime: Double
    let configuration: Configuration
    let variant: String?

    struct Configuration: Encodable {
        let maximumPostImpactDuration: Double
        let minimumPeakConfidence: Double
        let maximumCandidatesPerFrame: Int
        let maximumPeaksPerTile: Int
        let analysisCadence: Double
        let reacquisitionInterval: Double
        let diagnosticTileOrigins: [[Double]]?
    }
}

private struct CandidateOutput: Encodable {
    let sourceTime: Double
    let normalizedX: Double
    let normalizedY: Double
    let confidence: Double

    init(_ candidate: WASBGolfBallTrackingDiagnosticCandidate) {
        sourceTime = candidate.presentationTime
        normalizedX = candidate.normalizedX
        normalizedY = candidate.normalizedY
        confidence = candidate.confidence
    }
}

private struct RegionOutput: Encodable {
    let normalizedX: Double
    let normalizedY: Double
    let normalizedWidth: Double
    let normalizedHeight: Double

    init(_ region: WASBGolfBallTrackingDiagnosticRegion) {
        normalizedX = region.normalizedX
        normalizedY = region.normalizedY
        normalizedWidth = region.normalizedWidth
        normalizedHeight = region.normalizedHeight
    }
}

private struct FrameOutput: Encodable {
    let kind = "frame"
    let sourceTime: Double
    let analysisWidth: Int
    let analysisHeight: Int
    let searchKind: String
    let searchRegion: RegionOutput?
    let gateState: String
    let candidates: [CandidateOutput]
    let selectedCandidate: CandidateOutput?

    init(_ event: WASBGolfBallTrackingDiagnosticFrame) {
        sourceTime = event.presentationTime
        analysisWidth = event.analysisWidth
        analysisHeight = event.analysisHeight
        searchKind = event.searchKind.rawValue
        searchRegion = event.searchRegion.map(RegionOutput.init)
        gateState = event.gateState.rawValue
        candidates = event.candidates.map(CandidateOutput.init)
        selectedCandidate = event.selectedCandidate.map(CandidateOutput.init)
    }
}

private struct MetricsOutput: Encodable {
    let kind = "metrics"
    let analysedDuration: Double
    let sourceSamplesDecoded: Int
    let sourceSamplesSkippedForCadence: Int
    let sampledFrameCount: Int
    let modelWindowCount: Int
    let inputBufferAllocationCount: Int
    let tileInferenceCount: Int
    let acquisitionSearchCount: Int
    let localSearchCount: Int
    let reacquisitionSearchCount: Int
    let candidateCount: Int
    let selectedTrackPointCount: Int

    init(_ metrics: WASBGolfBallTrackingMetrics) {
        analysedDuration = metrics.analysedDuration
        sourceSamplesDecoded = metrics.sourceSamplesDecoded
        sourceSamplesSkippedForCadence = metrics.sourceSamplesSkippedForCadence
        sampledFrameCount = metrics.sampledFrameCount
        modelWindowCount = metrics.modelWindowCount
        inputBufferAllocationCount = metrics.inputBufferAllocationCount
        tileInferenceCount = metrics.tileInferenceCount
        acquisitionSearchCount = metrics.acquisitionSearchCount
        localSearchCount = metrics.localSearchCount
        reacquisitionSearchCount = metrics.reacquisitionSearchCount
        candidateCount = metrics.candidateCount
        selectedTrackPointCount = metrics.selectedTrackPointCount
    }
}

private struct SelectedPosition: Encodable {
    let sourceTime: Double
    let normalizedX: Double
    let normalizedY: Double
    /// Track-level confidence repeated for provenance, not a per-point detector score.
    let trackConfidence: Double
}

private struct ResultOutput: Encodable {
    let schemaVersion = 1
    let coordinateSystem = "normalised top-left origin; sourceTime is absolute source presentation time in seconds"
    let outcome: String
    let error: String?
    let trackerSource: String?
    let displayable: Bool?
    let confidence: Double?
    let selectedPositions: [SelectedPosition]
    let metrics: MetricsOutput?
}

private final class NDJSONWriter: @unchecked Sendable {
    private let handle: FileHandle
    private let encoder: JSONEncoder
    private let lock = NSLock()

    init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            throw HarnessError.unreadableOutput
        }
        self.handle = handle
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
    }

    deinit { try? handle.close() }

    func append<T: Encodable>(_ value: T) {
        guard let data = try? encoder.encode(value) else { return }
        lock.lock()
        defer { lock.unlock() }
        handle.write(data)
        handle.write(Data([0x0A]))
    }
}

private final class MetricsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: MetricsOutput?

    func store(_ metrics: WASBGolfBallTrackingMetrics) {
        lock.lock()
        value = MetricsOutput(metrics)
        lock.unlock()
    }

    func load() -> MetricsOutput? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@main
struct TracerHarness {
    static func main() async {
        do {
            let arguments = try Arguments()
            try FileManager.default.createDirectory(at: arguments.outputDirectory, withIntermediateDirectories: true)
            let video = try await sourceVideo(for: arguments.mediaURL)
            let manifest = RunManifest(
                schemaVersion: 2,
                coordinateSystem: "normalised top-left origin; sourceTime is absolute source presentation time in seconds",
                sourceRevision: arguments.sourceRevision,
                sourceHashes: arguments.sourceHashes,
                sourceSHA256: arguments.mediaSHA256,
                modelSHA256: arguments.modelSHA256,
                modelHashScope: "bundle-tree-sha256-v1(sorted relative paths + file SHA-256)",
                sourceModelBundleSHA256: arguments.modelSHA256,
                sourceModelWeightSHA256: arguments.modelWeightSHA256,
                sourceVideo: video,
                controlledImpactTime: arguments.impactTime,
                configuration: .init(
                    maximumPostImpactDuration: arguments.configuration.maximumPostImpactDuration,
                    minimumPeakConfidence: arguments.configuration.minimumPeakConfidence,
                    maximumCandidatesPerFrame: arguments.configuration.maximumCandidatesPerFrame,
                    maximumPeaksPerTile: arguments.configuration.maximumPeaksPerTile,
                    analysisCadence: arguments.configuration.analysisCadence,
                    reacquisitionInterval: arguments.configuration.reacquisitionInterval,
                    diagnosticTileOrigins: arguments.configuration.diagnosticTileOrigins?.map { [$0.x, $0.y] }
                ),
                variant: arguments.variant
            )
            try write(manifest, to: arguments.outputDirectory.appendingPathComponent("manifest.json"))

            let events = try NDJSONWriter(url: arguments.outputDirectory.appendingPathComponent("frames.ndjson"))
            let metrics = MetricsBox()
            let tracker = WASBGolfBallTrackingService(diagnosticModelURL: arguments.modelURL)
            do {
                let estimate = try await tracker.analyse(
                    url: arguments.mediaURL,
                    impactTime: arguments.impactTime,
                    configuration: arguments.configuration,
                    instrumentation: { metrics.store($0) },
                    diagnostics: { events.append(FrameOutput($0)) }
                )
                let positions = zip(
                    estimate.observedTrajectory?.presentationTimes ?? [],
                    estimate.observedTrajectory?.detectedPoints ?? []
                ).map {
                    SelectedPosition(
                        sourceTime: $0.0,
                        normalizedX: $0.1.x,
                        normalizedY: $0.1.y,
                        trackConfidence: estimate.confidence
                    )
                }
                try write(ResultOutput(
                    outcome: "success",
                    error: nil,
                    trackerSource: estimate.source.rawValue,
                    displayable: estimate.isDisplayable,
                    confidence: estimate.confidence,
                    selectedPositions: positions,
                    metrics: metrics.load()
                ), to: arguments.outputDirectory.appendingPathComponent("result.json"))
            } catch {
                try write(ResultOutput(
                    outcome: "error",
                    error: String(describing: error),
                    trackerSource: nil,
                    displayable: nil,
                    confidence: nil,
                    selectedPositions: [],
                    metrics: metrics.load()
                ), to: arguments.outputDirectory.appendingPathComponent("result.json"))
            }
            print("Tracker evidence written: manifest.json, frames.ndjson, result.json")
        } catch {
            FileHandle.standardError.write(Data("Tracker harness failed: \(error.localizedDescription)\n".utf8))
            exit(2)
        }
    }

    private static func sourceVideo(for url: URL) async throws -> SourceVideo {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw WASBGolfBallTrackingError.noVideoTrack
        }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let uprightWidth = abs(Double(transform.a)) * Double(size.width)
            + abs(Double(transform.c)) * Double(size.height)
        let uprightHeight = abs(Double(transform.b)) * Double(size.width)
            + abs(Double(transform.d)) * Double(size.height)
        return SourceVideo(
            nativeWidth: Int(size.width.rounded()),
            nativeHeight: Int(size.height.rounded()),
            uprightWidth: Int(uprightWidth.rounded()),
            uprightHeight: Int(uprightHeight.rounded()),
            durationSeconds: max(0, CMTimeGetSeconds(try await asset.load(.duration))),
            nominalFrameRate: Double(try await track.load(.nominalFrameRate)),
            preferredTransform: [Double(transform.a), Double(transform.b), Double(transform.c), Double(transform.d), Double(transform.tx), Double(transform.ty)]
        )
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
