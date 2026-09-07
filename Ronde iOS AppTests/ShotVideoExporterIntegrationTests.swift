@preconcurrency import AVFoundation
import CoreGraphics
import XCTest
@testable import Ronde

/// Generated, non-private portrait fixture: green field, white top-left square,
/// purple bottom-right square and a mono tone. These assertions validate media plumbing and
/// coordinate transforms, not golf-ball accuracy or physical-device performance.
final class ShotVideoExporterIntegrationTests: XCTestCase {
    func testFractionalTrimEncodesH264AACWithoutChangingOriginal() async throws {
        let source = try fixtureURL()
        let original = try Data(contentsOf: source)
        let edit = ShotVideoEdit(trimStart: 0.413, trimEnd: 1.313, format: .original, overlay: .original)
        let output = try await ShotVideoExporter().export(.init(sourceURL: source, edit: edit, trace: nil)) { _ in }
        defer { try? FileManager.default.removeItem(at: output) }
        try await assertMovie(output, size: CGSize(width: 1080, height: 1920), duration: 0.9)
        let image = try await frame(url: output, at: 0.4)
        let white = try pixel(image, x: 0.10, y: 0.07)
        XCTAssertGreaterThan(white.red, 210)
        XCTAssertGreaterThan(white.green, 210)
        XCTAssertGreaterThan(white.blue, 210)
        let purple = try pixel(image, x: 0.86, y: 0.92)
        XCTAssertGreaterThan(purple.blue, purple.green + 35)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testObservedTraceUsesSourceTimeAndAspectFitInLandscapeCanvas() async throws {
        let source = try fixtureURL()
        var candidate = try XCTUnwrap(ReviewFixtures.quickReviewSession.defaultCandidate)
        candidate.impactTime = 0.5
        candidate.evidenceAnchoredPath = EvidenceAnchoredFlightPath(
            observedPoints: [.init(x: 0.30, y: 0.65), .init(x: 0.40, y: 0.55), .init(x: 0.50, y: 0.45)],
            inferredContinuation: [.init(x: 0.90, y: 0.70)],
            observedPresentationTimes: [0.5, 0.7, 0.9],
            confidence: 0.8
        )
        let trace = try XCTUnwrap(ShotVideoTrace(candidate: candidate, mode: .automatic))
        let edit = ShotVideoEdit(trimStart: 0.413, trimEnd: 1.313, format: .landscape, overlay: .automatic)
        let output = try await ShotVideoExporter().export(.init(sourceURL: source, edit: edit, trace: trace)) { _ in }
        defer { try? FileManager.default.removeItem(at: output) }
        try await assertMovie(output, size: CGSize(width: 1920, height: 1080), duration: 0.9)
        let image = try await frame(url: output, at: 0.4)
        let fitted = ShotVideoLayout.fittedRect(sourceAspectRatio: 9.0 / 16, canvasSize: CGSize(width: 1920, height: 1080))
        let whitePoint = ShotVideoLayout.point(.init(x: 0.10, y: 0.07), in: fitted)
        let white = try pixel(image, x: whitePoint.x / 1920, y: whitePoint.y / 1080)
        XCTAssertGreaterThan(white.red, 210)
        XCTAssertGreaterThan(white.green, 210)
        let border = try pixel(image, x: 0.05, y: 0.50)
        XCTAssertLessThan(border.red, 20)
        XCTAssertLessThan(border.green, 20)
        let tracked = ShotVideoLayout.point(.init(x: 0.30, y: 0.65), in: fitted)
        XCTAssertTrue(try hasPurpleNear(image, point: tracked), "The observed stroke must align with the same fitted source coordinates as playback.")
        let extrapolated = ShotVideoLayout.point(.init(x: 0.90, y: 0.70), in: fitted)
        XCTAssertFalse(try hasPurpleNear(image, point: extrapolated), "The studio must not export the stored inferred continuation.")
    }

    func testPreferredRotationIsAppliedBeforeEncoding() async throws {
        let source = try fixtureURL()
        let rotated = try await rotatedFixture(source)
        defer { try? FileManager.default.removeItem(at: rotated) }
        let edit = ShotVideoEdit(trimStart: 0.413, trimEnd: 1.113, format: .original, overlay: .original)
        let output = try await ShotVideoExporter().export(.init(sourceURL: rotated, edit: edit, trace: nil)) { _ in }
        defer { try? FileManager.default.removeItem(at: output) }
        try await assertMovie(output, size: CGSize(width: 1920, height: 1080), duration: 0.7)
        let image = try await frame(url: output, at: 0.3)
        // Source top-left maps to display top-right under this quarter-turn transform.
        let white = try pixel(image, x: 0.93, y: 0.10)
        XCTAssertGreaterThan(white.red, 210)
        XCTAssertGreaterThan(white.green, 210)
        XCTAssertGreaterThan(white.blue, 210)
    }

    func testMidExportCancellationStopsAndDoesNotModifySource() async throws {
        let source = try fixtureURL()
        let original = try Data(contentsOf: source)
        let job = Task {
            try await ShotVideoExporter().export(.init(sourceURL: source, edit: .init(trimStart: 0, trimEnd: 6, format: .portrait, overlay: .original), trace: nil)) { value in
                if value >= 0.015 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do {
            let unexpected = try await job.value
            try? FileManager.default.removeItem(at: unexpected)
            XCTFail("Cancellation should stop the local encoder.")
        } catch is CancellationError {
            XCTAssertEqual(try Data(contentsOf: source), original)
        }
    }

    private func fixtureURL() throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: "studio-fixture", withExtension: "mp4"), "The generated, non-private studio fixture must be bundled in the unit-test target.")
    }

    private func assertMovie(_ url: URL, size: CGSize, duration: TimeInterval) async throws {
        XCTAssertEqual(url.pathExtension, "mp4")
        let asset = AVURLAsset(url: url)
        let actualDuration = try await asset.load(.duration).seconds
        XCTAssertEqual(actualDuration, duration, accuracy: 0.002)
        let videos = try await asset.loadTracks(withMediaType: .video)
        let audios = try await asset.loadTracks(withMediaType: .audio)
        let video = try XCTUnwrap(videos.first)
        let audio = try XCTUnwrap(audios.first)
        let actualSize = try await video.load(.naturalSize)
        XCTAssertEqual(actualSize, size)
        let videoDescriptions = try await video.load(.formatDescriptions)
        let audioDescriptions = try await audio.load(.formatDescriptions)
        XCTAssertTrue(videoDescriptions.contains { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 })
        XCTAssertTrue(audioDescriptions.contains { CMFormatDescriptionGetMediaSubType($0) == kAudioFormatMPEG4AAC })
    }

    private func frame(url: URL, at time: TimeInterval) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
    }

    private struct Pixel { let red: Int; let green: Int; let blue: Int }
    private func pixel(_ image: CGImage, x: Double, y: Double) throws -> Pixel {
        let crop = try XCTUnwrap(image.cropping(to: CGRect(x: floor(x * Double(image.width)), y: floor(y * Double(image.height)), width: 1, height: 1)))
        var values = [UInt8](repeating: 0, count: 4)
        try values.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Pixel(red: Int(values[0]), green: Int(values[1]), blue: Int(values[2]))
    }

    private func hasPurpleNear(_ image: CGImage, point: CGPoint) throws -> Bool {
        for dy in -3...3 {
            for dx in -3...3 {
                let colour = try pixel(image, x: (point.x + Double(dx)) / Double(image.width), y: (point.y + Double(dy)) / Double(image.height))
                if colour.blue > colour.green + 45, colour.red > colour.green + 15 { return true }
            }
        }
        return false
    }

    private func rotatedFixture(_ source: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let sourceVideos = try await asset.loadTracks(withMediaType: .video)
        let sourceVideo = try XCTUnwrap(sourceVideos.first)
        let size = try await sourceVideo.load(.naturalSize)
        let composition = AVMutableComposition()
        let video = try XCTUnwrap(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        let range = CMTimeRange(start: .zero, duration: duration)
        try video.insertTimeRange(range, of: sourceVideo, at: .zero)
        video.preferredTransform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: size.height, ty: 0)
        if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
           let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try audio.insertTimeRange(range, of: sourceAudio, at: .zero)
        }
        let exporter = try XCTUnwrap(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        let box = FixtureExportBox(exporter)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("ronde-rotated-fixture-\(UUID().uuidString).mov")
        exporter.outputURL = destination
        exporter.outputFileType = .mov
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            box.session.exportAsynchronously {
                if box.session.status == .completed { continuation.resume() }
                else { continuation.resume(throwing: box.session.error ?? ShotVideoExportError.cannotWrite) }
            }
        }
        return destination
    }
}

private final class FixtureExportBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}
