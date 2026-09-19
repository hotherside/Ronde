@preconcurrency import AVFoundation
import CryptoKit
import Darwin
import Foundation
import UIKit

@main
final class TrackerDiagnosticApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.text = "Ronde Tracker Diagnostic\nPreparing local evidence…"
        window.rootViewController = StatusViewController(label: label)
        window.makeKeyAndVisible()
        self.window = window

        Task { [weak self] in
            let message = await DeviceProbe().run()
            await MainActor.run { label.text = message }
            _ = self
        }
        return true
    }
}

private final class StatusViewController: UIViewController {
    private let label: UILabel

    init(label: UILabel) {
        self.label = label
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}

private struct DiagnosticConfig: Decodable {
    let schemaVersion: Int
    let sourceRevision: String
    let sourceHashes: [String: String]
    let sourceModelBundleSHA256: String
    let sourceModelWeightSHA256: String
    let sourceModelHashScope: String
    let expectedCompiledModelSHA256: String
    let clips: [DiagnosticClip]
}

private struct DiagnosticClip: Decodable {
    let clipID: String
    let resource: String
    let impactSourcePTS: Double
    let sourceHash: String
    let expectedUprightWidth: Int
    let expectedUprightHeight: Int
}

private struct DeviceMetrics: Encodable {
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
        tileInferenceCount = metrics.tilesEvaluated
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
}

private struct MemoryMetrics: Encodable {
    let sampledPeakResidentBytes: UInt64
    let sampledPeakFootprintBytes: UInt64
    let sampledSampleCount: Int
    let sampledIntervalMilliseconds: Int
    let processLifetimePeakResidentBytes: UInt64
    let processLifetimePeakScope: String
}

private struct ClipResult: Encodable {
    let clipID: String
    let resource: String
    let impactSourcePTS: Double
    let expectedSourceHash: String
    let observedSourceHash: String?
    let sourceHashVerified: Bool
    let expectedUprightWidth: Int
    let expectedUprightHeight: Int
    let observedUprightWidth: Int?
    let observedUprightHeight: Int?
    let dimensionsVerified: Bool
    let outcome: String
    let error: String?
    let wallSeconds: Double
    let preflightSeconds: Double
    let analysisSeconds: Double?
    let thermalStateAtStart: String
    let thermalStateAtEnd: String
    let maximumThermalState: String
    let memory: MemoryMetrics?
    let metrics: DeviceMetrics?
    let selectedPositions: [SelectedPosition]
}

private struct DeviceEvidence: Encodable {
    let schemaVersion: Int
    let runID: String
    var runStatus: String
    let startedAt: String
    var completedAt: String?
    let bundleIdentifier: String
    let deviceModel: String
    let hardwareMachine: String
    let operatingSystem: String
    let sourceRevision: String
    let sourceHashes: [String: String]
    let sourceModelBundleSHA256: String
    let sourceModelWeightSHA256: String
    let sourceModelHashScope: String
    let expectedCompiledModelSHA256: String
    let compiledModelSHA256: String?
    let compiledModelWeightSHA256: String?
    let compiledModelVerified: Bool
    var clips: [ClipResult]
}

private final class Measurements: @unchecked Sendable {
    private let lock = NSLock()
    private var metrics: DeviceMetrics?
    private var sampledPeakResidentBytes: UInt64 = 0
    private var sampledPeakFootprintBytes: UInt64 = 0
    private var sampledSampleCount = 0
    private var maximumThermalState = thermalState()

    func record(_ newMetrics: WASBGolfBallTrackingMetrics) {
        lock.lock()
        metrics = DeviceMetrics(newMetrics)
        lock.unlock()
    }

    func sample() {
        let memory = currentMemory()
        let thermal = thermalState()
        lock.lock()
        sampledPeakResidentBytes = max(sampledPeakResidentBytes, memory.residentBytes)
        sampledPeakFootprintBytes = max(sampledPeakFootprintBytes, memory.footprintBytes)
        sampledSampleCount += 1
        if thermalRank(thermal) > thermalRank(maximumThermalState) { maximumThermalState = thermal }
        lock.unlock()
    }

    func snapshot() -> (DeviceMetrics?, MemoryMetrics, String) {
        lock.lock()
        defer { lock.unlock() }
        return (
            metrics,
            MemoryMetrics(
                sampledPeakResidentBytes: sampledPeakResidentBytes,
                sampledPeakFootprintBytes: sampledPeakFootprintBytes,
                sampledSampleCount: sampledSampleCount,
                sampledIntervalMilliseconds: 20,
                processLifetimePeakResidentBytes: processLifetimePeakResidentBytes(),
                processLifetimePeakScope: "process lifetime, not this clip"
            ),
            maximumThermalState
        )
    }
}

private actor DeviceProbe {
    private let runID = UUID()
    private let startedAt = ISO8601DateFormatter().string(from: Date())
    private var evidence: DeviceEvidence?

    func run() async -> String {
        let config: DiagnosticConfig
        do {
            config = try loadConfig()
        } catch {
            return "Ronde Tracker Diagnostic\nConfiguration unavailable."
        }

        let modelURL = Bundle.main.url(forResource: "GolfBallTracker", withExtension: "mlmodelc")
        let runtimeModelHash = modelURL.flatMap { try? digest(url: $0) }
        let runtimeWeightHash = modelURL.flatMap { try? digestWeight(in: $0) }
        let device = await MainActor.run { (UIDevice.current.model, UIDevice.current.systemVersion) }
        let machine = hardwareMachine()
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "unknown"
        evidence = DeviceEvidence(
            schemaVersion: 3,
            runID: runID.uuidString,
            runStatus: "running",
            startedAt: startedAt,
            completedAt: nil,
            bundleIdentifier: bundleIdentifier,
            deviceModel: device.0,
            hardwareMachine: machine,
            operatingSystem: device.1,
            sourceRevision: config.sourceRevision,
            sourceHashes: config.sourceHashes,
            sourceModelBundleSHA256: config.sourceModelBundleSHA256,
            sourceModelWeightSHA256: config.sourceModelWeightSHA256,
            sourceModelHashScope: config.sourceModelHashScope,
            expectedCompiledModelSHA256: config.expectedCompiledModelSHA256,
            compiledModelSHA256: runtimeModelHash,
            compiledModelWeightSHA256: runtimeWeightHash,
            compiledModelVerified: runtimeModelHash == config.expectedCompiledModelSHA256,
            clips: []
        )
        do {
            try persist()
        } catch {
            return persistenceFailure(error)
        }
        guard runtimeModelHash == config.expectedCompiledModelSHA256 else {
            evidence?.runStatus = "compiled_model_verification_failed"
            do {
                try persist()
            } catch {
                return persistenceFailure(error)
            }
            return "Ronde Tracker Diagnostic\nCompiled model verification failed; no clips were analysed."
        }
        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = true }
        defer { Task { @MainActor in UIApplication.shared.isIdleTimerDisabled = false } }

        for clip in config.clips {
            let result = await runClip(clip, modelURL: modelURL)
            evidence?.clips.append(result)
            do {
                try persist()
            } catch {
                return persistenceFailure(error)
            }
        }
        evidence?.runStatus = "completed"
        evidence?.completedAt = ISO8601DateFormatter().string(from: .now)
        do {
            try persist()
        } catch {
            return persistenceFailure(error)
        }
        let allSucceeded = evidence?.clips.allSatisfy { $0.outcome == "success" } == true
        return allSucceeded
            ? "Ronde Tracker Diagnostic\nComplete. Evidence saved locally."
            : "Ronde Tracker Diagnostic\nCompleted with one or more local errors."
    }

    private func persistenceFailure(_ error: Error) -> String {
        "Ronde Tracker Diagnostic\nEvidence save failed; the last atomically completed file was retained if available. \(error.localizedDescription)"
    }

    private func runClip(_ clip: DiagnosticClip, modelURL: URL?) async -> ClipResult {
        let started = DispatchTime.now().uptimeNanoseconds
        let thermalAtStart = thermalState()
        let expectedHash = clip.sourceHash
        guard let mediaURL = Bundle.main.url(forResource: clip.resource, withExtension: "mov") else {
            return errorResult(clip, started: started, thermalAtStart: thermalAtStart, message: "Diagnostic media is unavailable.")
        }
        let observedHash = try? digest(url: mediaURL)
        let sourceVerified = observedHash == expectedHash
        let dimensions = try? await uprightDimensions(url: mediaURL)
        let dimensionsVerified = dimensions?.width == clip.expectedUprightWidth && dimensions?.height == clip.expectedUprightHeight
        let preflightSeconds = elapsedSeconds(since: started)
        guard sourceVerified, dimensionsVerified, let modelURL else {
            return ClipResult(
                clipID: clip.clipID, resource: clip.resource, impactSourcePTS: clip.impactSourcePTS,
                expectedSourceHash: expectedHash, observedSourceHash: observedHash, sourceHashVerified: sourceVerified,
                expectedUprightWidth: clip.expectedUprightWidth, expectedUprightHeight: clip.expectedUprightHeight,
                observedUprightWidth: dimensions?.width, observedUprightHeight: dimensions?.height,
                dimensionsVerified: dimensionsVerified, outcome: "error",
                error: modelURL == nil ? "Compiled tracker model is unavailable." : "Source identity or upright dimensions failed verification.",
                wallSeconds: elapsedSeconds(since: started), preflightSeconds: preflightSeconds, analysisSeconds: nil,
                thermalStateAtStart: thermalAtStart,
                thermalStateAtEnd: thermalState(), maximumThermalState: thermalAtStart, memory: nil, metrics: nil,
                selectedPositions: []
            )
        }

        let measurements = Measurements()
        let sampler = startMemorySampler(measurements)
        let analysisStarted = DispatchTime.now().uptimeNanoseconds
        do {
            let estimate = try await WASBGolfBallTrackingService(diagnosticModelURL: modelURL).analyse(
                url: mediaURL,
                impactTime: clip.impactSourcePTS,
                instrumentation: { measurements.record($0) }
            )
            sampler.cancel()
            _ = await sampler.value
            let snapshot = measurements.snapshot()
            let positions = zip(
                estimate.observedTrajectory?.presentationTimes ?? [],
                estimate.observedTrajectory?.detectedPoints ?? []
            ).map { SelectedPosition(sourceTime: $0.0, normalizedX: $0.1.x, normalizedY: $0.1.y) }
            let analysisSeconds = elapsedSeconds(since: analysisStarted)
            return ClipResult(
                clipID: clip.clipID, resource: clip.resource, impactSourcePTS: clip.impactSourcePTS,
                expectedSourceHash: expectedHash, observedSourceHash: observedHash, sourceHashVerified: sourceVerified,
                expectedUprightWidth: clip.expectedUprightWidth, expectedUprightHeight: clip.expectedUprightHeight,
                observedUprightWidth: dimensions?.width, observedUprightHeight: dimensions?.height,
                dimensionsVerified: dimensionsVerified, outcome: "success", error: nil,
                wallSeconds: elapsedSeconds(since: started), preflightSeconds: preflightSeconds, analysisSeconds: analysisSeconds,
                thermalStateAtStart: thermalAtStart,
                thermalStateAtEnd: thermalState(), maximumThermalState: snapshot.2, memory: snapshot.1,
                metrics: snapshot.0, selectedPositions: positions
            )
        } catch {
            sampler.cancel()
            _ = await sampler.value
            let snapshot = measurements.snapshot()
            let analysisSeconds = elapsedSeconds(since: analysisStarted)
            return ClipResult(
                clipID: clip.clipID, resource: clip.resource, impactSourcePTS: clip.impactSourcePTS,
                expectedSourceHash: expectedHash, observedSourceHash: observedHash, sourceHashVerified: sourceVerified,
                expectedUprightWidth: clip.expectedUprightWidth, expectedUprightHeight: clip.expectedUprightHeight,
                observedUprightWidth: dimensions?.width, observedUprightHeight: dimensions?.height,
                dimensionsVerified: dimensionsVerified, outcome: "error", error: String(describing: error),
                wallSeconds: elapsedSeconds(since: started), preflightSeconds: preflightSeconds, analysisSeconds: analysisSeconds,
                thermalStateAtStart: thermalAtStart,
                thermalStateAtEnd: thermalState(), maximumThermalState: snapshot.2, memory: snapshot.1,
                metrics: snapshot.0, selectedPositions: []
            )
        }
    }

    private func errorResult(_ clip: DiagnosticClip, started: UInt64, thermalAtStart: String, message: String) -> ClipResult {
        ClipResult(
            clipID: clip.clipID, resource: clip.resource, impactSourcePTS: clip.impactSourcePTS,
            expectedSourceHash: clip.sourceHash, observedSourceHash: nil, sourceHashVerified: false,
            expectedUprightWidth: clip.expectedUprightWidth, expectedUprightHeight: clip.expectedUprightHeight,
            observedUprightWidth: nil, observedUprightHeight: nil, dimensionsVerified: false,
            outcome: "error", error: message, wallSeconds: elapsedSeconds(since: started),
            preflightSeconds: elapsedSeconds(since: started), analysisSeconds: nil,
            thermalStateAtStart: thermalAtStart, thermalStateAtEnd: thermalState(), maximumThermalState: thermalAtStart,
            memory: nil, metrics: nil, selectedPositions: []
        )
    }

    private func loadConfig() throws -> DiagnosticConfig {
        guard let url = Bundle.main.url(forResource: "diagnostic-config", withExtension: "json") else {
            throw NSError(domain: "TrackerDiagnostic", code: 1)
        }
        return try JSONDecoder().decode(DiagnosticConfig.self, from: Data(contentsOf: url))
    }

    private func persist() throws {
        guard let evidence else {
            throw NSError(domain: "TrackerDiagnostic", code: 3, userInfo: [NSLocalizedDescriptionKey: "Evidence was not initialised."])
        }
        let output = try outputURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(evidence).write(to: output, options: .atomic)
    }

    private func outputURL() throws -> URL {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return documents.appendingPathComponent("tracker-device-evidence-\(runID.uuidString).json")
    }
}

private func startMemorySampler(_ measurements: Measurements) -> Task<Void, Never> {
    Task.detached(priority: .utility) {
        while !Task.isCancelled {
            measurements.sample()
            do { try await Task.sleep(for: .milliseconds(20)) } catch { break }
        }
        measurements.sample()
    }
}

private func elapsedSeconds(since start: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
}

private struct MemorySnapshot {
    let residentBytes: UInt64
    let footprintBytes: UInt64
}

private func currentMemory() -> MemorySnapshot {
    var basic = mach_task_basic_info()
    var basicCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let basicResult = withUnsafeMutablePointer(to: &basic) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &basicCount)
        }
    }
    var vm = task_vm_info_data_t()
    var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let vmResult = withUnsafeMutablePointer(to: &vm) {
        $0.withMemoryRebound(to: natural_t.self, capacity: Int(vmCount)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
        }
    }
    return MemorySnapshot(
        residentBytes: basicResult == KERN_SUCCESS ? UInt64(basic.resident_size) : 0,
        footprintBytes: vmResult == KERN_SUCCESS ? UInt64(vm.phys_footprint) : 0
    )
}

private func processLifetimePeakResidentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? UInt64(info.resident_size_max) : 0
}

private func digest(url: URL) throws -> String {
    var isDirectory = ObjCBool(false)
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        throw NSError(domain: "TrackerDiagnostic", code: 4, userInfo: [NSLocalizedDescriptionKey: "Hash input is unavailable."])
    }
    return isDirectory.boolValue ? try digestDirectory(url) : try digestFile(url)
}

private func digestFile(_ url: URL) throws -> String {
    "sha256:" + hexDigest(try Data(contentsOf: url))
}

private func digestDirectory(_ url: URL) throws -> String {
    guard let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        throw NSError(domain: "TrackerDiagnostic", code: 5, userInfo: [NSLocalizedDescriptionKey: "Directory contents are unavailable."])
    }
    let root = url.standardizedFileURL
    let files = try enumerator.compactMap { item -> URL? in
        guard let item = item as? URL else { return nil }
        let values = try item.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true ? nil : item
    }.sorted { $0.path < $1.path }
    var manifest = Data()
    for file in files {
        let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
        let perFileSHA = hexDigest(try Data(contentsOf: file))
        manifest.append(Data("\(relative)\t\(perFileSHA)\n".utf8))
    }
    return "sha256:" + hexDigest(manifest)
}

private func hexDigest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func digestWeight(in modelURL: URL) throws -> String? {
    guard let enumerator = FileManager.default.enumerator(at: modelURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return nil }
    let weights = try enumerator.compactMap { item -> URL? in
        guard let item = item as? URL, item.lastPathComponent == "weight.bin" || item.lastPathComponent == "weights.bin" else { return nil }
        let values = try item.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true ? nil : item
    }.sorted { $0.path < $1.path }
    return try weights.first.map(digest)
}

private func uprightDimensions(url: URL) async throws -> (width: Int, height: Int) {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw NSError(domain: "TrackerDiagnostic", code: 2) }
    let size = try await track.load(.naturalSize)
    let transform = try await track.load(.preferredTransform)
    let rect = CGRect(origin: .zero, size: size).applying(transform)
    return (Int(abs(rect.width).rounded()), Int(abs(rect.height).rounded()))
}

private func hardwareMachine() -> String {
    var value = utsname()
    uname(&value)
    return withUnsafeBytes(of: &value.machine) { raw in
        String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .controlCharacters)
    }
}

private func thermalState() -> String {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: "nominal"
    case .fair: "fair"
    case .serious: "serious"
    case .critical: "critical"
    @unknown default: "unknown"
    }
}

private func thermalRank(_ state: String) -> Int {
    switch state {
    case "nominal": 0
    case "fair": 1
    case "serious": 2
    case "critical": 3
    default: -1
    }
}
