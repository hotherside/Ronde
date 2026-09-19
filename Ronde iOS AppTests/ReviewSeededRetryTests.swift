import Foundation
import XCTest
@testable import Ronde

@MainActor
final class ReviewSeededRetryTests: XCTestCase {
    func testSingleShotRetryPreservesSeparateTracesWithReplacementAndEmptyDetection() throws {
        var session = ReviewFixtures.quickReviewSession
        session.importKind = .oneShot
        var previous = try XCTUnwrap(session.defaultCandidate)
        previous.seededTrace = try makeTrace()
        previous.assistedTracer = .default
        session.candidates = [previous]
        let replacement = ReviewCandidate(
            ordinal: 1, impactTime: 0.8, sourceDuration: session.duration,
            classification: .likelyShot, confidence: .high,
            evidence: ["Replacement automatic evidence"],
            evidenceAnchoredPath: previous.evidenceAnchoredPath
        )

        let merged = ReviewerStore.preservingSeparateTraces(in: [replacement], from: session)
        let result = try XCTUnwrap(merged.first)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(result.id, replacement.id)
        XCTAssertEqual(result.impactTime, replacement.impactTime)
        XCTAssertEqual(result.evidenceAnchoredPath, replacement.evidenceAnchoredPath)
        XCTAssertTrue(result.evidence.contains("Replacement automatic evidence"))
        XCTAssertEqual(result.seededTrace, previous.seededTrace)
        XCTAssertEqual(result.assistedTracer, previous.assistedTracer)

        let emptyRetry = ReviewerStore.preservingSeparateTraces(in: [], from: session)
        XCTAssertEqual(emptyRetry.count, 1)
        XCTAssertEqual(emptyRetry.first?.id, previous.id)
        XCTAssertEqual(emptyRetry.first?.seededTrace, previous.seededTrace)
        XCTAssertEqual(emptyRetry.first?.assistedTracer, previous.assistedTracer)

        // A point-assisted trace must survive even when there is no manual
        // annotation to trigger the older retry-preservation branch.
        previous.assistedTracer = nil
        session.candidates = [previous]
        let seededOnlyRetry = ReviewerStore.preservingSeparateTraces(in: [], from: session)
        XCTAssertEqual(seededOnlyRetry.first?.id, previous.id)
        XCTAssertEqual(seededOnlyRetry.first?.seededTrace, previous.seededTrace)
        XCTAssertNil(seededOnlyRetry.first?.assistedTracer)
    }

    func testRetryDoesNotAttachASeededTraceToUnassociatedRangeCandidates() throws {
        var session = ReviewFixtures.quickReviewSession
        session.importKind = .rangeSession
        var previous = try XCTUnwrap(session.defaultCandidate)
        previous.seededTrace = try makeTrace()
        session.candidates = [previous]
        let replacement = ReviewCandidate(
            ordinal: 1, impactTime: 4, sourceDuration: session.duration,
            classification: .likelyShot, confidence: .high, evidence: []
        )
        let result = ReviewerStore.preservingSeparateTraces(in: [replacement], from: session)
        XCTAssertNil(result.first?.seededTrace)
        XCTAssertTrue(ReviewerStore.preservingSeparateTraces(in: [], from: session).isEmpty)
    }

    private func makeTrace() throws -> SeededModelTrace {
        let hash = String(repeating: "a", count: 64)
        return try XCTUnwrap(SeededModelTrace(
            sourceWidth: 1_920, sourceHeight: 1_080,
            seed: try XCTUnwrap(SeededModelTraceSeed(
                sourceFrameIndex: 30, presentationTime: 1,
                sourcePixelX: 100, sourcePixelY: 200
            )),
            sourceInterval: ReviewTimeRange(start: 0.5, duration: 1),
            model: try XCTUnwrap(SeededModelTraceModelIdentity(
                identifier: "EdgeTAM", version: "synthetic-test",
                modelBundleSHA256: hash, learnedConstantsSHA256: hash
            )),
            frames: [
                try XCTUnwrap(SeededModelTraceFrame(
                    sourceFrameIndex: 30, presentationTime: 1,
                    observation: SeededModelTraceObservation(sourcePixelX: 100, sourcePixelY: 200)
                )),
                try XCTUnwrap(SeededModelTraceFrame(
                    sourceFrameIndex: 31, presentationTime: 1.033, observation: nil
                ))
            ],
            policy: try XCTUnwrap(SeededModelTracePolicy(
                maximumSourceTimeGapSeconds: 0.20, automaticReseedCount: 1,
                gapRecoveryCount: 0, terminationReasons: ["forward": "first_empty_mask"],
                wasBudgetLimited: false
            ))
        ))
    }
}
