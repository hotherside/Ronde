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
            for (index, clip) in config.clips.enumerated() {
                try Task.checkCancellation()
                try await self.run(clip, index: index, fixtures: fixtures, output: output,
                                   configurationHash: configurationHash, service: service)
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
                     configurationHash: String, service: EdgeTAMTrackingService) async throws {
        let prefix = "clip-\(index)"
        let checkpointURL = output.appendingPathComponent(prefix + "-checkpoint.json")
        let evidenceURL = output.appendingPathComponent(prefix + "-evidence.json")
        let thermalAtStart = Self.thermalState()
        try Self.writeJSON(["clipID": clip.clipID, "status": "started"], to: checkpointURL)
        do {
            try check(clip.rangeStart.isFinite && clip.rangeEnd.isFinite && clip.rangeStart >= 0
                      && clip.rangeEnd > clip.rangeStart && clip.rangeEnd - clip.rangeStart <= 10,
                      "Invalid bounded source interval.")
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
            let clipID = clip.clipID
            let result = try await service.track(
                url: source, interval: clip.rangeStart...clip.rangeEnd, seedPTS: clip.seedPTS,
                normalisedPoint: .init(x: clip.pointX / Double(clip.expectedWidth), y: clip.pointY / Double(clip.expectedHeight)),
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
                sourceSHA256: sourceHash, sourceHashVerified: true,
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
            try check(abs(result.seedPTS - clip.seedPTS) <= 0.001, "Seed source PTS mismatch.")
            try check(!result.records.isEmpty && result.records.allSatisfy {
                $0.sourcePTS >= clip.rangeStart && $0.sourcePTS <= clip.rangeEnd
            }, "Canonical source timestamps are outside the selected interval.")

            let seeded = try XCTUnwrap(SeededModelTrace(trackingResult: result), "App trace adapter rejected the model result.")
            try check(seeded.frames.count == result.records.count, "Adapter dropped a canonical frame.")
            try check(seeded.frames.filter { $0.observation == nil }.count == result.records.filter { !$0.visible }.count,
                      "Adapter changed the empty-mask boundaries.")
            let segment = try XCTUnwrap(seeded.observedSegments.first { $0.count >= 2 }, "No observed segment can be rendered.")
            var session = ReviewFixtures.quickReviewSession
            var candidate = try XCTUnwrap(session.defaultCandidate)
            candidate.sourceDuration = sourceDuration
            candidate.seededTrace = seeded
            candidate.evidenceAnchoredPath = nil
            candidate.assistedTracer = nil
            let renderTrace = try XCTUnwrap(ShotVideoTrace(candidate: candidate, mode: .seeded))
            try check(renderTrace.isSeeded && !renderTrace.isManual, "Renderer lost point-assisted provenance.")
            let start = max(clip.rangeStart, segment[0].presentationTime)
            let end = min(clip.rangeEnd, start + 1.0)
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
            try check(restored.defaultCandidate?.seededTrace == seeded && restored.videoEdit == edit,
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
