@preconcurrency import AVFoundation
import CryptoKit
import Darwin
import Foundation
import UIKit

@main
final class EdgeTAMDiagnosticApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var runTask: Task<String, Never>?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        label.text = "EdgeTAM Diagnostic\nPreparing local evidence…"
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        let window = UIWindow(frame: UIScreen.main.bounds)
        let status = EdgeTAMStatusViewController(label: label, cancelButton: cancelButton) { [weak self] in
            self?.runTask?.cancel()
            cancelButton.isEnabled = false
            label.text = "EdgeTAM Diagnostic\nCancelling…"
        }
        window.rootViewController = status
        window.makeKeyAndVisible()
        self.window = window

        let runner = EdgeTAMDiagnosticRunner()
        let task = Task.detached(priority: .userInitiated) {
            await runner.run()
        }
        runTask = task
        Task { [weak self, weak label] in
            let message = await task.value
            await MainActor.run {
                label?.text = message
                self?.runTask = nil
            }
        }
        return true
    }

    func applicationWillTerminate(_: UIApplication) {
        runTask?.cancel()
    }
}

private final class EdgeTAMStatusViewController: UIViewController {
    private let label: UILabel
    private let cancelButton: UIButton
    private let onCancel: () -> Void

    init(label: UILabel, cancelButton: UIButton, onCancel: @escaping () -> Void) {
        self.label = label
        self.cancelButton = cancelButton
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addAction(UIAction { [onCancel] _ in onCancel() }, for: .touchUpInside)
        view.addSubview(label)
        view.addSubview(cancelButton)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -28),
            cancelButton.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 24),
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }
}

private struct EdgeTAMDiagnosticConfig: Decodable {
    let schemaVersion: Int
    let sourceRevision: String
    let sourceHashes: [String: String]
    let constantsResource: String
    let constantsSHA256: String
    let modelResources: [String: String]
    let expectedCompiledModelSHA256: [String: String]?
    let expectedCompiledModelAggregateSHA256: String?
    let clips: [EdgeTAMDiagnosticClip]
}

private struct EdgeTAMDiagnosticClip: Decodable {
    let clipID: String
    let resource: String
    let sourceSHA256: String
    let rangeStart: Double
    let rangeEnd: Double
    let seedPTS: Double
    let pointX: Double
    let pointY: Double
    let expectedWidth: Int
    let expectedHeight: Int
}

private struct EdgeTAMCanonicalEvidence: Encodable {
    let intervalFrameIndex: Int
    let sourceFrameIndex: Int
    let sourcePTS: Double
    let visible: Bool
    let centroidX: Double?
    let centroidY: Double?
    let objectScoreLogit: Float
    let segmentID: Int
    let direction: String
}

private struct EdgeTAMPolicyEvidence: Encodable {
    let observerCount: Int
    let canonicalCount: Int
    let segmentCount: Int
    let transitionCount: Int
    let automaticReseedCount: Int
    let gapRecoveryCount: Int
    let terminations: [String: EdgeTAMAdaptiveTermination]
}

private struct EdgeTAMMemoryEvidence: Encodable {
    let sampledPeakResidentBytes: UInt64
    let sampledPeakFootprintBytes: UInt64
    let sampledSampleCount: Int
    let sampleIntervalMilliseconds: Int
    let processLifetimePeakResidentBytes: UInt64
    let processLifetimePeakScope: String
    let maximumThermalState: String
}

private struct EdgeTAMClipEvidence: Encodable {
    let clipID: String
    let resource: String
    let expectedSourceSHA256: String
    let observedSourceSHA256: String?
    let sourceHashVerified: Bool
    let expectedWidth: Int
    let expectedHeight: Int
    let observedWidth: Int?
    let observedHeight: Int?
    let dimensionsVerified: Bool
    let rangeStart: Double
    let rangeEnd: Double
    let actualFrameCount: Int?
    let actualFirstPTS: Double?
    let actualLastPTS: Double?
    let seedIntervalFrameIndex: Int?
    let seedSourceFrameIndex: Int?
    let seedActualPTS: Double?
    let sourceOpenSeconds: Double
    let trackSeconds: Double?
    let wallSeconds: Double
    let thermalStateAtStart: String
    let thermalStateAtEnd: String
    let outcome: String
    let error: String?
    let policy: EdgeTAMPolicyEvidence?
    let canonical: [EdgeTAMCanonicalEvidence]
    let memory: EdgeTAMMemoryEvidence?
}

private struct EdgeTAMDeviceEvidence: Encodable {
    let schemaVersion: Int
    let runID: String
    var runStatus: String
    let startedAt: String
    var completedAt: String?
    let bundleIdentifier: String
    let hardwareMachine: String
    let operatingSystem: String
    let sourceRevision: String
    let sourceHashes: [String: String]
    let configurationSHA256: String
    var constantsSHA256: String?
    var modelHashes: [String: String]
    let requestedComputeUnits: String
    let executionBackendEvidence: String
    let expectedCompiledModelSHA256: [String: String]?
    let expectedCompiledModelAggregateSHA256: String?
    var compiledModelVerified: Bool
    var modelLoadSeconds: Double?
    var clips: [EdgeTAMClipEvidence]
    var error: String?
}

private final class EdgeTAMMeasurements: @unchecked Sendable {
    private let lock = NSLock()
    private var peakResident: UInt64 = 0
    private var peakFootprint: UInt64 = 0
    private var sampleCount = 0
    private var maximumThermal = edgeTAMThermalState()

    func sample() {
        let memory = edgeTAMCurrentMemory()
        let thermal = edgeTAMThermalState()
        lock.lock()
        peakResident = max(peakResident, memory.resident)
        peakFootprint = max(peakFootprint, memory.footprint)
        sampleCount += 1
        if edgeTAMThermalRank(thermal) > edgeTAMThermalRank(maximumThermal) { maximumThermal = thermal }
        lock.unlock()
    }

    func snapshot() -> EdgeTAMMemoryEvidence {
        lock.lock()
        defer { lock.unlock() }
        return EdgeTAMMemoryEvidence(
            sampledPeakResidentBytes: peakResident,
            sampledPeakFootprintBytes: peakFootprint,
            sampledSampleCount: sampleCount,
            sampleIntervalMilliseconds: 20,
            processLifetimePeakResidentBytes: edgeTAMProcessLifetimePeakResidentBytes(),
            processLifetimePeakScope: "process lifetime, not this clip",
            maximumThermalState: maximumThermal
        )
    }
}

private final class EdgeTAMDiagnosticRunner: @unchecked Sendable {
    private let runID = UUID()
    private let startedAt = ISO8601DateFormatter().string(from: Date())
    private var evidence: EdgeTAMDeviceEvidence?
    private var outputURL: URL?

    func run() async -> String {
        do {
            let config = try loadConfig()
            try validateConfig(config)
            outputURL = try makeOutputURL()
            let device = await MainActor.run { (UIDevice.current.systemVersion, Bundle.main.bundleIdentifier ?? "unknown") }
            evidence = EdgeTAMDeviceEvidence(
                schemaVersion: config.schemaVersion,
                runID: runID.uuidString,
                runStatus: "running",
                startedAt: startedAt,
                completedAt: nil,
                bundleIdentifier: device.1,
                hardwareMachine: edgeTAMHardwareMachine(),
                operatingSystem: device.0,
                sourceRevision: config.sourceRevision,
                sourceHashes: config.sourceHashes,
                configurationSHA256: try edgeTAMDigest(url: bundleResource("edgetam-diagnostic-config.json", defaultExtension: "json")),
                constantsSHA256: nil,
                modelHashes: [:],
                requestedComputeUnits: "all",
                executionBackendEvidence: "Selected by Core ML; per-operation hardware is not instrumented",
                expectedCompiledModelSHA256: config.expectedCompiledModelSHA256,
                expectedCompiledModelAggregateSHA256: config.expectedCompiledModelAggregateSHA256,
                compiledModelVerified: false,
                modelLoadSeconds: nil,
                clips: [],
                error: nil
            )
            try persist()

            await MainActor.run { UIApplication.shared.isIdleTimerDisabled = true }
            defer { Task { @MainActor in UIApplication.shared.isIdleTimerDisabled = false } }

            let modelStarted = edgeTAMNow()
            let (modelURLs, modelHashes) = try resolveModels(config.modelResources)
            let expectedMatch = try verifyExpectedModels(
                actual: modelHashes,
                aggregate: config.expectedCompiledModelAggregateSHA256,
                perComponent: config.expectedCompiledModelSHA256
            )
            guard expectedMatch else { throw EdgeTAMNativeError.model("Compiled model identity verification failed") }
            let components = try EdgeTAMCoreMLComponents(packageURLs: modelURLs)
            let constantsURL = try bundleResource(config.constantsResource, defaultExtension: "json")
            let constantsHash = try edgeTAMDigest(url: constantsURL)
            guard edgeTAMNormalisedHash(constantsHash) == edgeTAMNormalisedHash(config.constantsSHA256) else {
                throw EdgeTAMNativeError.model("Learned constants identity verification failed")
            }
            let constants = try loadConstants(config.constantsResource)
            try constants.validate()
            let modelSeconds = edgeTAMNow() - modelStarted
            evidence?.modelHashes = modelHashes
            evidence?.constantsSHA256 = constantsHash
            evidence?.compiledModelVerified = true
            evidence?.modelLoadSeconds = modelSeconds
            try persist()

            for clip in config.clips {
                try Task.checkCancellation()
                let measurements = EdgeTAMMeasurements()
                let sampler = edgeTAMStartMemorySampler(measurements)
                let result = await runClip(clip, components: components, constants: constants, measurements: measurements)
                sampler.cancel()
                _ = await sampler.value
                evidence?.clips.append(result)
                try persist()
                if Task.isCancelled { throw CancellationError() }
            }
            let completedStatus = evidence?.clips.allSatisfy { $0.outcome == "success" } == true ? "completed" : "completed_with_errors"
            evidence?.runStatus = completedStatus
            evidence?.completedAt = ISO8601DateFormatter().string(from: Date())
            try persist()
            return evidence?.runStatus == "completed"
                ? "EdgeTAM Diagnostic\nComplete. Evidence saved locally."
                : "EdgeTAM Diagnostic\nCompleted with local errors."
        } catch is CancellationError {
            evidence?.runStatus = "cancelled"
            evidence?.error = "Run cancelled"
            try? persist()
            return "EdgeTAM Diagnostic\nCancelled. Partial evidence retained locally."
        } catch {
            evidence?.runStatus = "error"
            evidence?.error = String(describing: error)
            do {
                try persist()
                return "EdgeTAM Diagnostic\nFailed. Evidence saved locally."
            } catch {
                return "EdgeTAM Diagnostic\nEvidence save failed; no completion claim."
            }
        }
    }

    private func runClip(
        _ clip: EdgeTAMDiagnosticClip,
        components: EdgeTAMCoreMLComponents,
        constants: EdgeTAMLearnedConstants,
        measurements: EdgeTAMMeasurements
    ) async -> EdgeTAMClipEvidence {
        let started = edgeTAMNow()
        let thermalAtStart = edgeTAMThermalState()
        do {
            let mediaURL = try bundleResource(clip.resource, defaultExtension: "mov")
            let observedHash = try edgeTAMDigest(url: mediaURL)
            let sourceHashVerified = edgeTAMNormalisedHash(observedHash) == edgeTAMNormalisedHash(clip.sourceSHA256)
            guard sourceHashVerified else { throw EdgeTAMNativeError.invalidState("Source identity verification failed") }
            guard clip.rangeEnd > clip.rangeStart else { throw EdgeTAMNativeError.invalidState("Invalid source interval") }

            let openStarted = edgeTAMNow()
            let frames = try await EdgeTAMDirectVideoFrames.open(
                url: mediaURL,
                sourceInterval: clip.rangeStart...clip.rangeEnd
            )
            defer { frames.close() }
            let sourceOpenSeconds = edgeTAMNow() - openStarted
            guard frames.sourceWidth == clip.expectedWidth, frames.sourceHeight == clip.expectedHeight else {
                throw EdgeTAMNativeError.invalidState("Upright source dimensions do not match configuration")
            }
            guard !frames.frameTimes.isEmpty,
                  frames.frameTimes.count == frames.sourceFrameIndices.count else {
                throw EdgeTAMNativeError.invalidState("Source interval returned no aligned frames")
            }
            guard let seedIndex = frames.frameTimes.indices.min(by: {
                abs(frames.frameTimes[$0] - clip.seedPTS) < abs(frames.frameTimes[$1] - clip.seedPTS)
            }) else { throw EdgeTAMNativeError.invalidState("Seed frame is unavailable") }
            let seedDelta = abs(frames.frameTimes[seedIndex] - clip.seedPTS)
            guard seedDelta <= 0.001,
                  clip.pointX >= 0, clip.pointX < Double(frames.sourceWidth),
                  clip.pointY >= 0, clip.pointY < Double(frames.sourceHeight) else {
                throw EdgeTAMNativeError.invalidState("Seed timestamp or point failed validation")
            }

            let trackStarted = edgeTAMNow()
            var observerCount = 0
            let tracker = EdgeTAMAdaptiveTracker(components: components, constants: constants)
            let result = try tracker.track(
                frameTimes: frames.frameTimes,
                sourceWidth: frames.sourceWidth,
                sourceHeight: frames.sourceHeight,
                seedIndex: seedIndex,
                point: (x: clip.pointX, y: clip.pointY),
                frameProvider: { index, crop in
                    try frames.tensor(index: index, crop: crop)
                },
                observer: { _ in observerCount += 1 }
            )
            let trackSeconds = edgeTAMNow() - trackStarted
            let canonical = result.canonical.map { record in
                EdgeTAMCanonicalEvidence(
                    intervalFrameIndex: record.index,
                    sourceFrameIndex: frames.sourceFrameIndices[record.index],
                    sourcePTS: record.timestamp,
                    visible: record.visible,
                    centroidX: record.centroidX,
                    centroidY: record.centroidY,
                    objectScoreLogit: record.objectScoreLogit,
                    segmentID: record.segmentID,
                    direction: record.direction
                )
            }
            let policy = EdgeTAMPolicyEvidence(
                observerCount: observerCount,
                canonicalCount: result.canonical.count,
                segmentCount: result.segments.count,
                transitionCount: result.transitions.count,
                automaticReseedCount: result.automaticReseedCount,
                gapRecoveryCount: result.gapRecoveryCount,
                terminations: result.terminations
            )
            let budgetLimited = result.terminations.values.contains {
                $0.reason == "propagation_time_limit" || $0.reason == "automatic_reseed_limit"
            }
            return EdgeTAMClipEvidence(
                clipID: clip.clipID, resource: clip.resource,
                expectedSourceSHA256: clip.sourceSHA256, observedSourceSHA256: observedHash,
                sourceHashVerified: true, expectedWidth: clip.expectedWidth, expectedHeight: clip.expectedHeight,
                observedWidth: frames.sourceWidth, observedHeight: frames.sourceHeight, dimensionsVerified: true,
                rangeStart: clip.rangeStart, rangeEnd: clip.rangeEnd,
                actualFrameCount: frames.frameTimes.count, actualFirstPTS: frames.frameTimes.first,
                actualLastPTS: frames.frameTimes.last, seedIntervalFrameIndex: seedIndex,
                seedSourceFrameIndex: frames.sourceFrameIndices[seedIndex], seedActualPTS: frames.frameTimes[seedIndex],
                sourceOpenSeconds: sourceOpenSeconds, trackSeconds: trackSeconds,
                wallSeconds: edgeTAMNow() - started, thermalStateAtStart: thermalAtStart,
                thermalStateAtEnd: edgeTAMThermalState(), outcome: budgetLimited ? "partial_budget_limit" : "success", error: nil,
                policy: policy, canonical: canonical,
                memory: measurements.snapshot()
            )
        } catch is CancellationError {
            return errorClip(clip, started: started, thermalAtStart: thermalAtStart, outcome: "cancelled", error: "Clip cancelled")
        } catch {
            return errorClip(clip, started: started, thermalAtStart: thermalAtStart, outcome: "error", error: String(describing: error))
        }
    }

    private func errorClip(_ clip: EdgeTAMDiagnosticClip, started: Double, thermalAtStart: String, outcome: String, error: String) -> EdgeTAMClipEvidence {
        EdgeTAMClipEvidence(
            clipID: clip.clipID, resource: clip.resource, expectedSourceSHA256: clip.sourceSHA256,
            observedSourceSHA256: nil, sourceHashVerified: false, expectedWidth: clip.expectedWidth,
            expectedHeight: clip.expectedHeight, observedWidth: nil, observedHeight: nil, dimensionsVerified: false,
            rangeStart: clip.rangeStart, rangeEnd: clip.rangeEnd, actualFrameCount: nil, actualFirstPTS: nil,
            actualLastPTS: nil, seedIntervalFrameIndex: nil, seedSourceFrameIndex: nil, seedActualPTS: nil,
            sourceOpenSeconds: 0, trackSeconds: nil, wallSeconds: edgeTAMNow() - started,
            thermalStateAtStart: thermalAtStart, thermalStateAtEnd: edgeTAMThermalState(), outcome: outcome,
            error: error, policy: nil, canonical: [], memory: nil
        )
    }

    private func loadConfig() throws -> EdgeTAMDiagnosticConfig {
        guard let url = Bundle.main.url(forResource: "edgetam-diagnostic-config", withExtension: "json") else {
            throw EdgeTAMNativeError.invalidState("Diagnostic configuration is unavailable")
        }
        return try JSONDecoder().decode(EdgeTAMDiagnosticConfig.self, from: Data(contentsOf: url))
    }

    private func validateConfig(_ config: EdgeTAMDiagnosticConfig) throws {
        guard config.schemaVersion > 0, !config.clips.isEmpty,
              Set(config.clips.map(\.clipID)).count == config.clips.count,
              Set(config.modelResources.keys) == ["image", "attention", "point", "noPoint", "memory"],
              config.clips.allSatisfy({ $0.rangeEnd > $0.rangeStart && $0.seedPTS >= $0.rangeStart && $0.seedPTS <= $0.rangeEnd }) else {
            throw EdgeTAMNativeError.invalidState("Diagnostic configuration is incomplete")
        }
    }

    private func loadConstants(_ resource: String) throws -> EdgeTAMLearnedConstants {
        let url = try bundleResource(resource, defaultExtension: "json")
        return try JSONDecoder().decode(EdgeTAMLearnedConstants.self, from: Data(contentsOf: url))
    }

    private func resolveModels(_ resources: [String: String]) throws -> ([String: URL], [String: String]) {
        var urls: [String: URL] = [:]
        var hashes: [String: String] = [:]
        for key in ["image", "attention", "point", "noPoint", "memory"] {
            let url = try bundleResource(resources[key]!, defaultExtension: "mlmodelc")
            urls[key] = url
            hashes[key] = try edgeTAMDigest(url: url)
        }
        return (urls, hashes)
    }

    private func verifyExpectedModels(actual: [String: String], aggregate: String?, perComponent: [String: String]?) throws -> Bool {
        guard aggregate != nil || perComponent != nil else { return false }
        if let perComponent {
            guard Set(perComponent.keys) == Set(actual.keys) else { return false }
            guard perComponent.keys.allSatisfy({
                guard let actualValue = actual[$0], let expectedValue = perComponent[$0] else { return false }
                return edgeTAMNormalisedHash(actualValue) == edgeTAMNormalisedHash(expectedValue)
            }) else { return false }
        }
        if let aggregate {
            let manifest = actual.keys.sorted().compactMap { key in "\(key)\t\(actual[key]!)\n" }.joined()
            guard edgeTAMNormalisedHash("sha256:" + edgeTAMHexDigest(Data(manifest.utf8))) == edgeTAMNormalisedHash(aggregate) else { return false }
        }
        return true
    }

    private func bundleResource(_ name: String, defaultExtension: String) throws -> URL {
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else {
            throw EdgeTAMNativeError.invalidState("Bundle resource name is invalid")
        }
        let file = name as NSString
        let extensionName = file.pathExtension.isEmpty ? defaultExtension : file.pathExtension
        let baseName = file.deletingPathExtension
        guard let url = Bundle.main.url(forResource: baseName, withExtension: extensionName) else {
            throw EdgeTAMNativeError.invalidState("Required diagnostic bundle resource is unavailable")
        }
        return url
    }

    private func makeOutputURL() throws -> URL {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return documents.appendingPathComponent("edgetam-device-evidence-\(runID.uuidString).json")
    }

    private func persist() throws {
        guard let evidence, let outputURL else { throw EdgeTAMNativeError.invalidState("Evidence is not initialised") }
        let data = try JSONEncoder.edgetamEvidence.encode(evidence)
        let temporary = outputURL.deletingLastPathComponent().appendingPathComponent(".edgetam-\(runID.uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: outputURL)
        }
    }
}

private extension JSONEncoder {
    static var edgetamEvidence: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private func edgeTAMNow() -> Double { ProcessInfo.processInfo.systemUptime }

private func edgeTAMStartMemorySampler(_ measurements: EdgeTAMMeasurements) -> Task<Void, Never> {
    Task.detached(priority: .utility) {
        while !Task.isCancelled {
            measurements.sample()
            do { try await Task.sleep(for: .milliseconds(20)) } catch { break }
        }
        measurements.sample()
    }
}

private struct EdgeTAMMemorySnapshot { let resident: UInt64; let footprint: UInt64 }

private func edgeTAMCurrentMemory() -> EdgeTAMMemorySnapshot {
    var basic = mach_task_basic_info()
    var basicCount = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let basicResult = withUnsafeMutablePointer(to: &basic) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &basicCount) }
    }
    var vm = task_vm_info_data_t()
    var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let vmResult = withUnsafeMutablePointer(to: &vm) {
        $0.withMemoryRebound(to: natural_t.self, capacity: Int(vmCount)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount) }
    }
    return EdgeTAMMemorySnapshot(
        resident: basicResult == KERN_SUCCESS ? UInt64(basic.resident_size) : 0,
        footprint: vmResult == KERN_SUCCESS ? UInt64(vm.phys_footprint) : 0
    )
}

private func edgeTAMProcessLifetimePeakResidentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
    }
    return result == KERN_SUCCESS ? UInt64(info.resident_size_max) : 0
}

private func edgeTAMDigest(url: URL) throws -> String {
    var directory = ObjCBool(false)
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else {
        throw EdgeTAMNativeError.invalidState("Hash input is unavailable")
    }
    if !directory.boolValue { return "sha256:" + (try edgeTAMFileDigest(url)) }
    guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
        throw EdgeTAMNativeError.invalidState("Hash directory is unavailable")
    }
    let root = url.standardizedFileURL.path
    let files = try enumerator.compactMap { item -> URL? in
        guard let item = item as? URL else { return nil }
        return try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true ? nil : item
    }.sorted { $0.path < $1.path }
    var manifest = Data()
    for file in files {
        try Task.checkCancellation()
        let relative = file.standardizedFileURL.path.replacingOccurrences(of: root + "/", with: "")
        manifest.append(Data("\(relative)\t\(try edgeTAMFileDigest(file))\n".utf8))
    }
    return "sha256:" + edgeTAMHexDigest(manifest)
}

private func edgeTAMFileDigest(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var digest = SHA256()
    while true {
        try Task.checkCancellation()
        guard let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty else { break }
        digest.update(data: bytes)
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
}

private func edgeTAMHexDigest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func edgeTAMNormalisedHash(_ value: String) -> String {
    let lowercased = value.lowercased()
    return lowercased.hasPrefix("sha256:") ? lowercased : "sha256:\(lowercased)"
}

private func edgeTAMHardwareMachine() -> String {
    var value = utsname(); uname(&value)
    return withUnsafeBytes(of: &value.machine) { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .controlCharacters) }
}

private func edgeTAMThermalState() -> String {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: "nominal"
    case .fair: "fair"
    case .serious: "serious"
    case .critical: "critical"
    @unknown default: "unknown"
    }
}

private func edgeTAMThermalRank(_ state: String) -> Int {
    switch state { case "nominal": 0; case "fair": 1; case "serious": 2; case "critical": 3; default: -1 }
}
