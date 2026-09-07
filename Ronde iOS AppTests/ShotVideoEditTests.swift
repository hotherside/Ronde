import CoreGraphics
import XCTest
@testable import Ronde

final class ShotVideoEditTests: XCTestCase {
    func testTrimNeverCrossesSourceOrMinimumCut() {
        let edit = ShotVideoEdit(trimStart: 9.9, trimEnd: 2).normalised(sourceDuration: 10)
        XCTAssertEqual(edit.trimStart, 9.5)
        XCTAssertEqual(edit.trimEnd, 10)
        XCTAssertEqual(edit.duration, 0.5)
        let short = ShotVideoEdit(trimStart: 5, trimEnd: -.infinity).normalised(sourceDuration: 0.2)
        XCTAssertEqual(short.trimStart, 0)
        XCTAssertEqual(short.trimEnd, 0.2)
        let invalid = ShotVideoEdit(trimStart: .nan, trimEnd: .infinity).normalised(sourceDuration: 7)
        XCTAssertEqual(invalid.trimStart, 0)
        XCTAssertEqual(invalid.trimEnd, 7)
    }

    func testEditRoundTripsWithoutChangingSourceEvidence() throws {
        var session = ReviewFixtures.quickReviewSession
        let candidate = try XCTUnwrap(session.defaultCandidate)
        session.videoEdit = ShotVideoEdit(trimStart: 0.5, trimEnd: 4.75, format: .portrait, overlay: .original)
        let restored = try JSONDecoder().decode(ReviewSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored.videoEdit, session.videoEdit)
        XCTAssertEqual(restored.defaultCandidate?.evidenceAnchoredPath, candidate.evidenceAnchoredPath)
        XCTAssertEqual(restored.defaultCandidate?.impactTime, candidate.impactTime)
    }

    func testOldArchiveWithoutEditStillDecodes() throws {
        let data = try JSONEncoder().encode(ReviewFixtures.quickReviewSession)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "videoEdit")
        let restored = try JSONDecoder().decode(ReviewSession.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(restored.videoEdit)
    }

    func testSocialCanvasesHaveExactEvenFullHDDimensions() {
        XCTAssertEqual(ShotVideoExportFormat.portrait.renderSize(sourceAspectRatio: 16.0 / 9), CGSize(width: 1080, height: 1920))
        XCTAssertEqual(ShotVideoExportFormat.square.renderSize(sourceAspectRatio: 16.0 / 9), CGSize(width: 1080, height: 1080))
        XCTAssertEqual(ShotVideoExportFormat.landscape.renderSize(sourceAspectRatio: 9.0 / 16), CGSize(width: 1920, height: 1080))
        XCTAssertEqual(ShotVideoExportFormat.original.renderSize(sourceAspectRatio: 4.0 / 3), CGSize(width: 1440, height: 1080))
        XCTAssertEqual(ShotVideoExportFormat.original.renderSize(sourceAspectRatio: 3.0 / 4), CGSize(width: 1080, height: 1440))
    }

    func testLandscapeInsidePortraitKeepsEntireSourceAndAlignedTrace() {
        let rect = ShotVideoLayout.fittedRect(sourceAspectRatio: 16.0 / 9, canvasSize: CGSize(width: 1080, height: 1920))
        XCTAssertEqual(rect.width, 1080, accuracy: 0.001)
        XCTAssertEqual(rect.height, 607.5, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 656.25, accuracy: 0.001)
        let first = ShotVideoLayout.point(NormalizedPoint(x: 0, y: 0), in: rect)
        let last = ShotVideoLayout.point(NormalizedPoint(x: 1, y: 1), in: rect)
        XCTAssertEqual(first, CGPoint(x: 0, y: 656.25))
        XCTAssertEqual(last, CGPoint(x: 1080, y: 1263.75))
    }

    func testPreviewAndExportUseTheSameScaledGeometry() {
        let preview = ShotVideoLayout.fittedRect(sourceAspectRatio: 16.0 / 9, canvasSize: CGSize(width: 216, height: 384))
        let output = ShotVideoLayout.fittedRect(sourceAspectRatio: 16.0 / 9, canvasSize: CGSize(width: 1080, height: 1920))
        let p = NormalizedPoint(x: 0.39, y: 0.76)
        let previewPoint = ShotVideoLayout.point(p, in: preview)
        let exportPoint = ShotVideoLayout.point(p, in: output)
        XCTAssertEqual(previewPoint.x * 5, exportPoint.x, accuracy: 0.001)
        XCTAssertEqual(previewPoint.y * 5, exportPoint.y, accuracy: 0.001)
    }

    func testFrameStepsUseActualSourcePresentationTimes() {
        let times = [0.0, 1.0 / 240, 2.0 / 240, 0.017, 0.024, 0.039]
        XCTAssertEqual(ShotVideoLayout.adjacentFrame(to: 1.0 / 240, direction: 1, presentationTimes: times), 2.0 / 240)
        XCTAssertEqual(ShotVideoLayout.adjacentFrame(to: 0.024, direction: -1, presentationTimes: times), 0.017)
        XCTAssertNil(ShotVideoLayout.adjacentFrame(to: 0, direction: -1, presentationTimes: times))
        XCTAssertNil(ShotVideoLayout.adjacentFrame(to: 0.039, direction: 1, presentationTimes: times))
        XCTAssertEqual(ShotVideoLayout.nearestFrame(to: 0.023, presentationTimes: times), 0.024)
    }

    func testAutomaticStudioTraceExcludesExtrapolatedFlightAndCarry() throws {
        let candidate = try XCTUnwrap(ReviewFixtures.quickReviewSession.defaultCandidate)
        let evidence = try XCTUnwrap(candidate.evidenceAnchoredPath)
        let trace = try XCTUnwrap(ShotVideoTrace(candidate: candidate, mode: .automatic))
        XCTAssertEqual(trace.points, evidence.observedPoints)
        XCTAssertEqual(trace.presentationTimes, evidence.observedPresentationTimes)
        XCTAssertFalse(trace.isManual)
        XCTAssertNil(ShotVideoTrace(candidate: candidate, mode: .original))
        XCTAssertTrue(trace.visiblePoints(at: 0).isEmpty)
        let renderedEnd = try XCTUnwrap(trace.visiblePoints(at: 100).last)
        let observedEnd = try XCTUnwrap(evidence.observedPoints.last)
        XCTAssertEqual(renderedEnd.x, observedEnd.x, accuracy: 0.000_001)
        XCTAssertEqual(renderedEnd.y, observedEnd.y, accuracy: 0.000_001)
    }

    func testTrimmingDoesNotRestartOrCompressAutomaticSourceTiming() throws {
        let candidate = try XCTUnwrap(ReviewFixtures.quickReviewSession.defaultCandidate)
        let trace = try XCTUnwrap(ShotVideoTrace(candidate: candidate, mode: .automatic))
        let edit = ShotVideoEdit(trimStart: 1.75, trimEnd: 3)
        let outputTime = 0.08
        let actual = trace.visiblePoints(at: edit.trimStart + outputTime)
        let expected = TimedTrajectoryPath(points: trace.points, presentationTimes: trace.presentationTimes)?.visibleTrailSamples(at: 1.83).map(\.point)
        let comparison = try XCTUnwrap(expected)
        XCTAssertEqual(actual.count, comparison.count)
        for (point, expectedPoint) in zip(actual, comparison) {
            XCTAssertEqual(point.x, expectedPoint.x, accuracy: 0.000_001)
            XCTAssertEqual(point.y, expectedPoint.y, accuracy: 0.000_001)
        }
    }

    func testManualTraceIsSeparateAndHasNoAutomaticSampleTimes() throws {
        var candidate = try XCTUnwrap(ReviewFixtures.quickReviewSession.defaultCandidate)
        candidate.assistedTracer = .default
        let trace = try XCTUnwrap(ShotVideoTrace(candidate: candidate, mode: .manual))
        XCTAssertTrue(trace.isManual)
        XCTAssertTrue(trace.presentationTimes.isEmpty)
        XCTAssertEqual(trace.label, "Manual trace")
        XCTAssertTrue(trace.visiblePoints(at: candidate.impactTime - 0.1).isEmpty)
        XCTAssertEqual(trace.visiblePoints(at: candidate.impactTime), trace.points)
    }
}
