import XCTest
@testable import Ronde

final class ShotAutomaticSeedSelectionTests: XCTestCase {
    func testNoObservedTrajectoryNeverProducesASyntheticSeed() {
        let estimate = BallFlightEstimate(
            launch: .init(x: 0.5, y: 0.5),
            apex: .init(x: 0.5, y: 0.3),
            landing: .init(x: 0.5, y: 0.2),
            source: .unavailable,
            confidence: 0,
            observedPointCount: 0
        )

        XCTAssertNil(ShotAutomaticSeedSelection.seed(
            from: estimate,
            impactTime: 4,
            in: .init(start: 0, duration: 10)
        ))
    }

    func testInvalidObservedTimestampsDoNotBecomeASeed() {
        let estimate = observedEstimate(
            points: [.init(x: 0.4, y: 0.3), .init(x: 0.45, y: 0.25), .init(x: 0.5, y: 0.2)],
            times: [.nan, .infinity, -.infinity]
        )

        XCTAssertNil(ShotAutomaticSeedSelection.seed(
            from: estimate,
            impactTime: 4,
            in: .init(start: 0, duration: 10)
        ))
    }

    func testSeedPreservesAbsoluteSourceTimeAndClampsTrackingIntervalToClip() throws {
        let estimate = observedEstimate(
            points: [.init(x: 0.41, y: 0.31), .init(x: 0.45, y: 0.25), .init(x: 0.49, y: 0.21)],
            times: [598.2, 598.24, 598.28]
        )

        let seed = try XCTUnwrap(ShotAutomaticSeedSelection.seed(
            from: estimate,
            impactTime: 597.9,
            in: .init(start: 595, duration: 10)
        ))

        XCTAssertEqual(seed.presentationTime, 598.24, accuracy: 0.000_001)
        XCTAssertEqual(seed.point, .init(x: 0.45, y: 0.25))
        XCTAssertEqual(seed.impactTime, 597.9, accuracy: 0.000_001)
        XCTAssertEqual(seed.trackingRange, .init(start: 595, duration: 10))
    }

    func testSeedPrefersTheLargestContinuousInteriorObservationRun() throws {
        let estimate = observedEstimate(
            points: [
                .init(x: 0.31, y: 0.41), .init(x: 0.34, y: 0.37),
                .init(x: 0.37, y: 0.33), .init(x: 0.40, y: 0.29),
                .init(x: 0.62, y: 0.43), .init(x: 0.65, y: 0.39), .init(x: 0.68, y: 0.35)
            ],
            times: [10.05, 10.11, 10.15, 10.19, 10.70, 10.74, 10.78]
        )

        let seed = try XCTUnwrap(ShotAutomaticSeedSelection.seed(
            from: estimate,
            impactTime: 10,
            in: .init(start: 8, duration: 5)
        ))

        XCTAssertEqual(seed.presentationTime, 10.11, accuracy: 0.000_001)
        XCTAssertEqual(seed.point, .init(x: 0.34, y: 0.37))
    }

    func testBoundaryImpactCannotCauseTheTrackerToReadBeforeSelectedClip() {
        let range = ReviewTimeRange(start: 100, duration: 8)
        let candidates = [
            candidate(impactTime: 100, confidence: 0.9),
            candidate(impactTime: 102, confidence: 0.6),
            candidate(impactTime: 106, confidence: 0.8)
        ]

        let anchors = ShotAutomaticSeedSelection.anchors(from: candidates, in: range)

        XCTAssertEqual(anchors.map(\.impactTime), [106, 102])
        XCTAssertEqual(ShotAutomaticSeedSelection.trackerDuration(for: 106, in: range), 2)
        XCTAssertNil(ShotAutomaticSeedSelection.trackerDuration(for: 107.3, in: range))
    }

    func testLongRequestedClipIsRejectedBeforeImpactAnalysis() {
        XCTAssertNil(ShotAutomaticSeedSelection.boundedSourceRange(
            requested: .init(start: 0, duration: 20.001),
            sourceDuration: 600
        ))
    }

    private func candidate(impactTime: TimeInterval, confidence: Double) -> SwingCandidate {
        SwingCandidate(
            impactTime: impactTime,
            classification: .provisional(confidence: confidence, explanation: "Test"),
            evidence: [.audioTransient]
        )
    }

    private func observedEstimate(
        points: [NormalizedPoint],
        times: [TimeInterval]
    ) -> BallFlightEstimate {
        BallFlightEstimate(
            launch: points.first ?? .init(x: 0, y: 0),
            apex: points[points.count / 2],
            landing: points.last ?? .init(x: 0, y: 0),
            source: .observed,
            confidence: 0.8,
            observedPointCount: points.count,
            observedTrajectory: .init(
                detectedPoints: points,
                projectedPoints: [],
                presentationTimes: times,
                equationCoefficients: [],
                confidence: 0.8
            )
        )
    }
}
