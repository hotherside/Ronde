import Foundation
import XCTest
@testable import Ronde

final class SeededModelTraceTests: XCTestCase {
    private let modelHash = String(repeating: "a", count: 64)

    func testAutomaticSeedProvenanceSurvivesArchiveAndChangesRenderedLabel() throws {
        let selected = try XCTUnwrap(makeTrace())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(selected)) as? [String: Any])
        XCTAssertNil(object["seedOrigin"])
        object["seedOrigin"] = "detectedBall"
        let detected = try JSONDecoder().decode(SeededModelTrace.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(detected.seedOrigin, .detectedBall)
        var candidate = try XCTUnwrap(ReviewFixtures.quickReviewSession.defaultCandidate)
        candidate.seededTrace = detected
        XCTAssertEqual(ShotVideoTrace(candidate: candidate, mode: .seeded)?.label, "Observed ball track")
        candidate.seededTrace = selected
        XCTAssertEqual(ShotVideoTrace(candidate: candidate, mode: .seeded)?.label, "Tracked from selected ball point")
    }

    func testVisibilityToggleRestoresTheSelectedTraceAfterArchiveRoundTrip() throws {
        var edit = ShotVideoEdit(trimStart: 0, trimEnd: 10, overlay: .seeded)
        let modes: [ShotVideoOverlayMode] = [.original, .automatic, .seeded, .manual]
        edit.setTraceVisible(false, availableModes: modes)
        XCTAssertEqual(edit.overlay, .original)
        var restored = try JSONDecoder().decode(ShotVideoEdit.self, from: JSONEncoder().encode(edit))
        restored.setTraceVisible(true, availableModes: modes)
        XCTAssertEqual(restored.overlay, .seeded)
        restored.setTraceVisible(false, availableModes: modes)
        restored.setTraceVisible(true, availableModes: [.original, .manual])
        XCTAssertEqual(restored.overlay, .manual)
    }

    func testRoundTripKeepsSourcePixelEvidenceAndRejectsInvalidData() throws {
        let trace = try XCTUnwrap(makeTrace())
        let restored = try JSONDecoder().decode(SeededModelTrace.self, from: JSONEncoder().encode(trace))
        XCTAssertEqual(restored, trace)
        XCTAssertEqual(restored.frames[0].observation?.sourcePixelX, 100)
        XCTAssertEqual(restored.observedSegments.count, 3)

        XCTAssertNil(SeededModelTraceObservation(sourcePixelX: .infinity, sourcePixelY: 1))
        XCTAssertNil(SeededModelTraceSeed(sourceFrameIndex: -1, presentationTime: 1, sourcePixelX: 1, sourcePixelY: 1))
        XCTAssertNil(SeededModelTraceModelIdentity(identifier: "EdgeTAM", version: "1", modelBundleSHA256: "not-a-modelHash", learnedConstantsSHA256: modelHash))
        let outside = try XCTUnwrap(SeededModelTraceObservation(sourcePixelX: 1_920, sourcePixelY: 10))
        XCTAssertNil(SeededModelTrace(
            sourceWidth: 1_920,
            sourceHeight: 1_080,
            seed: try XCTUnwrap(SeededModelTraceSeed(sourceFrameIndex: 10, presentationTime: 1, sourcePixelX: 20, sourcePixelY: 20)),
            sourceInterval: ReviewTimeRange(start: 0.5, duration: 1),
            model: try XCTUnwrap(SeededModelTraceModelIdentity(identifier: "EdgeTAM", version: "1", modelBundleSHA256: modelHash, learnedConstantsSHA256: modelHash)),
            frames: [try XCTUnwrap(SeededModelTraceFrame(sourceFrameIndex: 10, presentationTime: 1, observation: outside))]
        ))
    }

    func testNilAndSkippedFramesProduceIndependentVisibleSegments() throws {
        let trace = try XCTUnwrap(makeTrace())
        let segments = trace.observedSegments
        XCTAssertEqual(segments.map(\.count), [2, 1, 2])
        XCTAssertEqual(try XCTUnwrap(segments[0].last).presentationTime, 1.033, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(segments[1].first).presentationTime, 1.100, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(segments[2].first).presentationTime, 1.133, accuracy: 0.000_001)

        var candidate = try XCTUnwrap(ReviewFixtures.quickReviewSession.defaultCandidate)
        candidate.seededTrace = trace
        let videoTrace = try XCTUnwrap(ShotVideoTrace(candidate: candidate, mode: .seeded))
        let visible = videoTrace.visibleSegments(at: 1.2)
        XCTAssertEqual(visible.count, 3)
        XCTAssertEqual(try XCTUnwrap(visible[0].first).x, 100.0 / 1_920.0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(visible[1].first).x, 500.0 / 1_920.0, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(visible[2].first).x, 520.0 / 1_920.0, accuracy: 0.000_001)
        XCTAssertEqual(videoTrace.label, "Tracked from selected ball point")
    }

    func testPolicyIsOptionalForOldArchivesAndRejectsInvalidBounds() throws {
        let policy = try XCTUnwrap(SeededModelTracePolicy(
            maximumSourceTimeGapSeconds: 0.20,
            automaticReseedCount: 2,
            gapRecoveryCount: 1,
            terminationReasons: ["forward": "sourceIntervalEnd"],
            wasBudgetLimited: true
        ))
        let trace = try XCTUnwrap(makeTrace(policy: policy))
        XCTAssertEqual(trace.policy, policy)

        XCTAssertNil(SeededModelTracePolicy(maximumSourceTimeGapSeconds: 0.201, automaticReseedCount: 0, gapRecoveryCount: 0))
        XCTAssertNil(SeededModelTracePolicy(maximumSourceTimeGapSeconds: .infinity, automaticReseedCount: 0, gapRecoveryCount: 0))
        XCTAssertNil(SeededModelTracePolicy(maximumSourceTimeGapSeconds: 0.20, automaticReseedCount: -1, gapRecoveryCount: 0))
        XCTAssertNil(SeededModelTracePolicy(maximumSourceTimeGapSeconds: 0.20, automaticReseedCount: 0, gapRecoveryCount: -1))

        let encoded = try JSONEncoder().encode(trace)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "policy")
        let restored = try JSONDecoder().decode(SeededModelTrace.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(restored.policy)
    }

    func testMissingSeededTraceDecodesAsNilAndAutomaticRenderingIsUnchanged() throws {
        var candidate = try XCTUnwrap(ReviewFixtures.quickReviewSession.defaultCandidate)
        let automatic = try XCTUnwrap(ShotVideoTrace(candidate: candidate, mode: .automatic))
        XCTAssertEqual(automatic.visibleSegments(at: 100), [automatic.visiblePoints(at: 100)])

        candidate.seededTrace = try XCTUnwrap(makeTrace())
        let encoded = try JSONEncoder().encode(candidate)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "seededTrace")
        let archivedWithoutSeededTrace = try JSONSerialization.data(withJSONObject: object)
        let restored = try JSONDecoder().decode(ReviewCandidate.self, from: archivedWithoutSeededTrace)
        XCTAssertNil(restored.seededTrace)
        XCTAssertNotNil(ShotVideoTrace(candidate: restored, mode: .automatic))
    }

    private func makeTrace(policy: SeededModelTracePolicy? = nil) -> SeededModelTrace? {
        let seed = SeededModelTraceSeed(sourceFrameIndex: 10, presentationTime: 1.0, sourcePixelX: 100, sourcePixelY: 100)
        let model = SeededModelTraceModelIdentity(
            identifier: "EdgeTAM",
            version: "1.0",
            modelBundleSHA256: modelHash,
            learnedConstantsSHA256: modelHash
        )
        let frames = [
            SeededModelTraceFrame(sourceFrameIndex: 10, presentationTime: 1.000, observation: SeededModelTraceObservation(sourcePixelX: 100, sourcePixelY: 100)),
            SeededModelTraceFrame(sourceFrameIndex: 11, presentationTime: 1.033, observation: SeededModelTraceObservation(sourcePixelX: 120, sourcePixelY: 110)),
            SeededModelTraceFrame(sourceFrameIndex: 12, presentationTime: 1.066, observation: nil),
            SeededModelTraceFrame(sourceFrameIndex: 13, presentationTime: 1.100, observation: SeededModelTraceObservation(sourcePixelX: 500, sourcePixelY: 200)),
            // A skipped source index is a second break even without an explicit nil frame.
            SeededModelTraceFrame(sourceFrameIndex: 15, presentationTime: 1.133, observation: SeededModelTraceObservation(sourcePixelX: 520, sourcePixelY: 210)),
            SeededModelTraceFrame(sourceFrameIndex: 16, presentationTime: 1.166, observation: SeededModelTraceObservation(sourcePixelX: 540, sourcePixelY: 220))
        ].compactMap { $0 }
        return SeededModelTrace(
            sourceWidth: 1_920,
            sourceHeight: 1_080,
            seed: seed!,
            sourceInterval: ReviewTimeRange(start: 0.5, duration: 1),
            model: model!,
            frames: frames,
            policy: policy
        )
    }
}
