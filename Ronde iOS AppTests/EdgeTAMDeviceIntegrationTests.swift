@preconcurrency import AVFoundation
import CryptoKit
import Darwin
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Ronde

/// Opt-in private-media check of the real app service, archive and renderer.
/// Supply the configuration and both movies only in the external device-test
/// bundle. This file contains no media, labels or supplied-point coordinates.
@MainActor
final class EdgeTAMDeviceIntegrationTests: XCTestCase {
    func testPrivateClipsThroughAppTrackingExportAndArchive() async throws {
        try await runPrivateClips(acquisitionMode: .suppliedSeed)
    }

    func testPrivateClipsThroughAutomaticSeedTrackingExportAndArchive() async throws {
        try await runPrivateClips(acquisitionMode: .automaticSeed)
    }

    private func runPrivateClips(acquisitionMode: AcquisitionMode) async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("EdgeTAM integration evidence requires a physical iPhone.")
        #else
        let fixtures = Bundle(for: Self.self)
        guard let configURL = fixtures.url(forResource: "edgetam-device-test-config", withExtension: "json") else {
            throw XCTSkip("Private EdgeTAM device-test resources are not installed.")
        }
        executionTimeAllowance = 480
        let configData = try Data(contentsOf: configURL)
        let config = try JSONDecoder().decode(Configuration.self, from: configData)
        try check(config.schemaVersion > 0 && config.clips.count == 2, "Expected exactly two configured private clips.")
        try check(Set(config.clips.map(\.clipID)).count == 2, "Clip identifiers must be distinct.")
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        let output = documents.appendingPathComponent("EdgeTAMDeviceIntegration", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let configurationHash = "sha256:" + Self.digest(configData)
        let operation = Task {
            let service = EdgeTAMTrackingService(bundle: .main)
            let automaticSeedService = ShotAutomaticSeedService()
            for (index, clip) in config.clips.enumerated() {
                try Task.checkCancellation()
                try await self.run(clip, index: index, fixtures: fixtures, output: output,
                                   configurationHash: configurationHash, service: service,
                                   acquisitionMode: acquisitionMode, automaticSeedService: automaticSeedService)
            }
        }
        // Leave ten seconds for cooperative cancellation and evidence cleanup.
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(470)) } catch { return }
            operation.cancel()
        }
        defer { timeout.cancel() }
        try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
        #endif
    }

    private enum AcquisitionMode: String {
        case suppliedSeed
        case automaticSeed
    }

    private struct Configuration: Decodable { let schemaVersion: Int; let clips: [Clip] }
    private struct Clip: Decodable {
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

    private struct Evidence: Encodable {
        let schemaVersion = 1
        let clipID: String
        let configurationSHA256: String
        let sourceSHA256: String
        let sourceHashVerified: Bool
        let acquisitionMode: String
        let acquisitionElapsedSeconds: Double?
        let seedOrigin: String?
        let operatingSystem: String
        let hardwareMachine: String
        let sourceWidth: Int
        let sourceHeight: Int
        let intervalStart: Double
        let intervalEnd: Double
        let frameTimes: [Double]
        let sourceFrameIndices: [Int]
        let seedPTS: Double
        let seedSourceFrameIndex: Int
        let seedNormalisedPoint: EdgeTAMTrackingPoint
        let modelIdentity: EdgeTAMTrackingModelIdentity
        let canonical: [EdgeTAMTrackingRecord]
        let automaticReseedCount: Int
        let gapRecoveryCount: Int
        let terminations: [String: EdgeTAMTrackingTermination]
        let serviceStatus: String
        let serviceElapsedSeconds: Double
        let thermalStateAtStart: String
        var thermalStateAtEnd: String
        var exportSeconds: Double?
        var exportedDuration: Double?
        var archiveRoundTripPassed = false
        var outcome = "tracking_completed"
    }

    private enum ValidationFailure: Error { case failed }

    private func run(_ clip: Clip, index: Int, fixtures: Bundle, output: URL,
                     configurationHash: String, service: EdgeTAMTrackingService,
                     acquisitionMode: AcquisitionMode,
                     automaticSeedService: ShotAutomaticSeedService) async throws {
        let prefix = "clip-\(index)"
        let checkpointURL = output.appendingPathComponent(prefix + "-checkpoint.json")
        let evidenceURL = output.appendingPathComponent(prefix + "-evidence.json")
        let thermalAtStart = Self.thermalState()
        try Self.writeJSON(["clipID": clip.clipID, "status": "started"], to: checkpointURL)
        do {
            try check(clip.expectedWidth >= 512 && clip.expectedHeight >= 512, "Invalid expected source dimensions.")
            let file = clip.resource as NSString
            try check(!clip.resource.contains("/") && !clip.resource.contains("\\") && !file.pathExtension.isEmpty,
                      "Fixture resource must be one bundled movie.")
            let source = try XCTUnwrap(fixtures.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension),
                                      "Configured private movie is missing from the XCTest bundle.")
            let sourceHash = try Self.fileDigest(source)
            try check(sourceHash == Self.normalisedHash(clip.sourceSHA256), "Private source identity does not match configuration.")
            let asset = AVURLAsset(url: source)
            let sourceDuration = try await asset.load(.duration).seconds
            let sourceTracks = try await asset.loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(sourceTracks.first)
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let extent = CGRect(origin: .zero, size: size).applying(transform).standardized
            try check(Int(extent.width.rounded()) == clip.expectedWidth && Int(extent.height.rounded()) == clip.expectedHeight,
                      "Upright source dimensions do not match configuration.")
            let acquisitionStarted = ProcessInfo.processInfo.systemUptime
            let acquisition: AcquiredSeed
            switch acquisitionMode {
            case .suppliedSeed:
                try check(clip.rangeStart.isFinite && clip.rangeEnd.isFinite && clip.rangeStart >= 0
                          && clip.rangeEnd > clip.rangeStart && clip.rangeEnd - clip.rangeStart <= 10,
                          "Invalid bounded source interval.")
                acquisition = AcquiredSeed(
                    interval: clip.rangeStart...clip.rangeEnd,
                    seedPTS: clip.seedPTS,
                    point: .init(
                        x: clip.pointX / Double(clip.expectedWidth),
                        y: clip.pointY / Double(clip.expectedHeight)
                    ),
                    seedOrigin: nil
                )
            case .automaticSeed:
                try check(sourceDuration.isFinite && sourceDuration > 0 && sourceDuration < 20,
                          "Automatic seed acquisition requires a private source shorter than twenty seconds.")
                let automatic = try await automaticSeedService.locate(
                    url: source,
                    sourceRange: ReviewTimeRange(start: 0, duration: sourceDuration)
                )
                acquisition = AcquiredSeed(
                    interval: automatic.trackingRange.start...automatic.trackingRange.end,
                    seedPTS: automatic.presentationTime,
                    point: .init(x: automatic.point.x, y: automatic.point.y),
                    seedOrigin: .detectedBall
                )
            }
            let acquisitionElapsedSeconds = ProcessInfo.processInfo.systemUptime - acquisitionStarted
            try check(acquisition.interval.upperBound - acquisition.interval.lowerBound <= 20,
                      "Acquisition returned an interval longer than twenty seconds.")
            let clipID = clip.clipID
            let result = try await service.track(
                url: source, interval: acquisition.interval, seedPTS: acquisition.seedPTS,
                normalisedPoint: acquisition.point,
                progress: { value in
                    if value.stage != .tracking || value.completedCanonicalFrames.isMultiple(of: 10) {
                        let checkpoint: [String: Any] = ["clipID": clipID, "status": value.stage.rawValue,
                            "canonicalFramesProcessed": value.completedCanonicalFrames, "sourceFrameCount": value.totalFrames ?? 0]
                        if let data = try? JSONSerialization.data(withJSONObject: checkpoint, options: [.sortedKeys]) {
                            try? data.write(to: checkpointURL, options: [.atomic])
                        }
                    }
                }
            )
            var evidence = Evidence(clipID: clip.clipID, configurationSHA256: configurationHash,
                sourceSHA256: sourceHash, sourceHashVerified: true, acquisitionMode: acquisitionMode.rawValue,
                acquisitionElapsedSeconds: acquisitionMode == .automaticSeed ? acquisitionElapsedSeconds : nil,
                seedOrigin: acquisition.seedOrigin?.rawValue,
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString, hardwareMachine: Self.hardwareMachine(),
                sourceWidth: result.sourceWidth, sourceHeight: result.sourceHeight,
                intervalStart: result.interval.lowerBound, intervalEnd: result.interval.upperBound,
                frameTimes: result.frameTimes, sourceFrameIndices: result.sourceFrameIndices,
                seedPTS: result.seedPTS, seedSourceFrameIndex: result.seedSourceFrameIndex,
                seedNormalisedPoint: result.seedNormalisedPoint, modelIdentity: result.modelIdentity,
                canonical: result.records, automaticReseedCount: result.automaticReseedCount,
                gapRecoveryCount: result.gapRecoveryCount,
                terminations: Dictionary(uniqueKeysWithValues: result.terminations.map { ($0.key.rawValue, $0.value) }),
                serviceStatus: result.status.rawValue, serviceElapsedSeconds: result.elapsedSeconds,
                thermalStateAtStart: thermalAtStart, thermalStateAtEnd: Self.thermalState())
            // Persist actual observations before export/assertions so a later
            // failure cannot erase the tracking result needed for offline scoring.
            try persist(evidence, to: evidenceURL, attachmentName: prefix + "-tracking.json")
            try check(result.status == .completed, "Tracking reached a budget limit.")
            try check(result.sourceWidth == clip.expectedWidth && result.sourceHeight == clip.expectedHeight,
                      "Service dimensions differ from the verified source.")
            try check(abs(result.seedPTS - acquisition.seedPTS) <= 0.001, "Seed source PTS mismatch.")
            try check(!result.records.isEmpty && result.records.allSatisfy {
                $0.sourcePTS >= acquisition.interval.lowerBound && $0.sourcePTS <= acquisition.interval.upperBound
            }, "Canonical source timestamps are outside the selected interval.")

            let seeded: SeededModelTrace?
            if let seedOrigin = acquisition.seedOrigin {
                seeded = SeededModelTrace(trackingResult: result, seedOrigin: seedOrigin)
            } else {
                // Preserve the historical supplied-seed archive representation.
                seeded = SeededModelTrace(trackingResult: result)
            }
            let trace = try XCTUnwrap(seeded, "App trace adapter rejected the model result.")
            try check(trace.frames.count == result.records.count, "Adapter dropped a canonical frame.")
            try check(trace.frames.filter { $0.observation == nil }.count == result.records.filter { !$0.visible }.count,
                      "Adapter changed the empty-mask boundaries.")
            let segment = try XCTUnwrap(trace.observedSegments.first { $0.count >= 2 }, "No observed segment can be rendered.")
            var session = ReviewFixtures.quickReviewSession
            var candidate = try XCTUnwrap(session.defaultCandidate)
            candidate.sourceDuration = sourceDuration
            candidate.seededTrace = trace
            candidate.evidenceAnchoredPath = nil
            candidate.assistedTracer = nil
            let renderTrace = try XCTUnwrap(ShotVideoTrace(candidate: candidate, mode: .seeded))
            try check(renderTrace.isSeeded && !renderTrace.isManual, "Renderer lost point-assisted provenance.")
            let start = max(acquisition.interval.lowerBound, segment[0].presentationTime)
            let end = min(acquisition.interval.upperBound, start + 1.0)
            try check(end > start, "No bounded export interval remains.")
            let edit = ShotVideoEdit(trimStart: start, trimEnd: end, format: .original, overlay: .seeded)
            let exportStart = ProcessInfo.processInfo.systemUptime
            let temporaryExport = try await ShotVideoExporter().export(.init(sourceURL: source, edit: edit, trace: renderTrace)) { _ in }
            defer { try? FileManager.default.removeItem(at: temporaryExport) }
            let exported = output.appendingPathComponent(prefix + "-export.mp4")
            try FileManager.default.copyItem(at: temporaryExport, to: exported)
            evidence.exportSeconds = ProcessInfo.processInfo.systemUptime - exportStart
            let movie = AVURLAsset(url: exported)
            let readable = try await movie.load(.isReadable)
            let exportedDuration = try await movie.load(.duration).seconds
            evidence.exportedDuration = exportedDuration
            try check(readable && abs(exportedDuration - edit.duration) <= 0.05, "Export is unreadable or has the wrong duration.")
            let exportedTracks = try await movie.loadTracks(withMediaType: .video)
            let exportedTrack = try XCTUnwrap(exportedTracks.first)
            let reader = try AVAssetReader(asset: movie)
            let decoded = AVAssetReaderTrackOutput(track: exportedTrack,
                outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            try check(reader.canAdd(decoded), "Export decoder rejected the video track.")
            reader.add(decoded)
            try check(reader.startReading(), "Export decoding could not start.")
            let firstFrame = decoded.copyNextSampleBuffer()
            reader.cancelReading()
            try check(firstFrame.flatMap(CMSampleBufferGetImageBuffer) != nil, "Export contains no decodable video frame.")
            let movieAttachment = XCTAttachment(contentsOfFile: exported)
            movieAttachment.name = prefix + "-export.mp4"
            movieAttachment.lifetime = .keepAlways
            add(movieAttachment)

            session.title = "Device tracking validation"
            session.sourceName = nil
            session.sourceURL = nil
            session.duration = sourceDuration
            session.sourceAspectRatio = Double(result.sourceWidth) / Double(result.sourceHeight)
            session.candidates = [candidate]
            session.videoEdit = edit
            let archiveRoot = output.appendingPathComponent(prefix + "-archive", isDirectory: true)
            let archive = try ReviewSessionArchive(rootURL: archiveRoot)
            try archive.save([session])
            let restored = try XCTUnwrap(ReviewSessionArchive(rootURL: archiveRoot).load().first)
            try check(restored.defaultCandidate?.seededTrace == trace && restored.videoEdit == edit,
                      "Archive round-trip changed the assisted trace or edit.")
            try check(try Self.fileDigest(source) == sourceHash, "Source movie changed during processing.")
            evidence.archiveRoundTripPassed = true
            evidence.thermalStateAtEnd = Self.thermalState()
            evidence.outcome = "completed"
            try persist(evidence, to: evidenceURL, attachmentName: prefix + "-completed.json")
            try Self.writeJSON(["clipID": clip.clipID, "status": "completed"], to: checkpointURL)
        } catch {
            try? Self.writeJSON(["clipID": clip.clipID, "status": error is CancellationError ? "cancelled" : "failed",
                                "error": error.localizedDescription, "thermalState": Self.thermalState()], to: checkpointURL)
            let attachment = XCTAttachment(contentsOfFile: checkpointURL)
            attachment.name = prefix + "-failure.json"
            attachment.lifetime = .keepAlways
            add(attachment)
            throw error
        }
    }

    private struct AcquiredSeed {
        let interval: ClosedRange<Double>
        let seedPTS: Double
        let point: EdgeTAMTrackingPoint
        let seedOrigin: SeededModelTrace.SeedOrigin?
    }

    private func check(_ condition: Bool, _ message: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(condition, message, file: file, line: line)
        guard condition else { throw ValidationFailure.failed }
    }

    private func persist(_ evidence: Evidence, to url: URL, attachmentName: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(evidence)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: UTType.json.identifier)
        attachment.name = attachmentName
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func writeJSON(_ value: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            .write(to: url, options: [.atomic, .completeFileProtection])
    }

    private static func normalisedHash(_ value: String) -> String {
        let value = value.lowercased()
        return value.hasPrefix("sha256:") ? value : "sha256:" + value
    }

    private static func fileDigest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while true {
            try Task.checkCancellation()
            guard let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty else { break }
            digest.update(data: bytes)
        }
        return "sha256:" + digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func thermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private static func hardwareMachine() -> String {
        var value = utsname()
        uname(&value)
        return withUnsafeBytes(of: &value.machine) { bytes in
            String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }
}
