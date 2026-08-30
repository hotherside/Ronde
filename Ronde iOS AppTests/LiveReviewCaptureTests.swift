import Foundation
import XCTest
@testable import Ronde

final class LiveReviewCaptureTests: XCTestCase {
    func testStabilityClassifierRequiresEnoughEvidence() {
        let classifier = LiveReviewStabilityClassifier()
        let samples = Array(repeating: LiveReviewMotionSample(
            rotationMagnitude: 0.001,
            accelerationMagnitude: 0.001
        ), count: 11)

        XCTAssertEqual(classifier.classify(samples), .checking)
    }

    func testStabilityClassifierAcceptsBracedPhone() {
        let classifier = LiveReviewStabilityClassifier()
        let samples = Array(repeating: LiveReviewMotionSample(
            rotationMagnitude: 0.01,
            accelerationMagnitude: 0.01
        ), count: 20)

        XCTAssertEqual(classifier.classify(samples), .steady)
    }

    func testStabilityClassifierRejectsMovingPhone() {
        let classifier = LiveReviewStabilityClassifier()
        var samples = Array(repeating: LiveReviewMotionSample(
            rotationMagnitude: 0.01,
            accelerationMagnitude: 0.01
        ), count: 12)
        samples.append(contentsOf: Array(repeating: LiveReviewMotionSample(
            rotationMagnitude: 0.12,
            accelerationMagnitude: 0.08
        ), count: 8))

        XCTAssertEqual(classifier.classify(samples), .moving)
    }

    func testRollingLedgerProtectsImpactWindowAndEvictsOlderSegments() {
        var ledger = RollingSegmentLedger(retentionDuration: 8)
        let old = FinalizedCaptureSegment(
            url: URL(fileURLWithPath: "/tmp/ronde-old.mov"),
            timeRange: ReviewTimeRange(start: 0, duration: 2)
        )
        let recent = FinalizedCaptureSegment(
            url: URL(fileURLWithPath: "/tmp/ronde-recent.mov"),
            timeRange: ReviewTimeRange(start: 8, duration: 2)
        )

        XCTAssertTrue(ledger.append(old).isEmpty)
        XCTAssertEqual(ledger.append(recent), [old])

        let candidate = SwingCandidate(impactTime: 9)
        XCTAssertEqual(ledger.protectedSegments(for: candidate.clipWindow), [recent])
    }
}
