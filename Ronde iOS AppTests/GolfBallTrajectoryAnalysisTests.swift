import XCTest
@testable import Ronde

final class GolfBallTrajectoryAnalysisTests: XCTestCase {
    func testInferredGeometryIsNotDisplayable() {
        let result = BallFlightEstimate(
            launch: .init(x: 0.5, y: 0.8),
            apex: .init(x: 0.6, y: 0.2),
            landing: .init(x: 0.7, y: 0.6),
            source: .inferred,
            confidence: 0.9,
            observedPointCount: 5
        )

        XCTAssertFalse(result.isDisplayable)
    }

    func testFlightEstimateClampsConfidenceAndObservedCount() {
        let result = BallFlightEstimate(
            launch: .init(x: 0.5, y: 0.8),
            apex: .init(x: 0.6, y: 0.2),
            landing: .init(x: 0.7, y: 0.6),
            source: .observedAndInferred,
            confidence: 2,
            observedPointCount: -4
        )

        XCTAssertEqual(result.confidence, 1)
        XCTAssertEqual(result.observedPointCount, 0)
        XCTAssertFalse(result.isDisplayable)
    }

    func testObservedTrajectoryWithThreePointsIsDisplayable() {
        let points = [
            NormalizedPoint(x: 0.5, y: 0.8),
            NormalizedPoint(x: 0.52, y: 0.6),
            NormalizedPoint(x: 0.54, y: 0.4)
        ]
        let trajectory = DetectedTrajectory(
            detectedPoints: points,
            projectedPoints: [],
            equationCoefficients: [0, 0, 0],
            confidence: 0.9
        )
        let result = BallFlightEstimate(
            launch: points[0],
            apex: points[2],
            landing: .init(x: 0.58, y: 0.6),
            source: .observed,
            confidence: 0.9,
            observedPointCount: points.count,
            observedTrajectory: trajectory
        )

        XCTAssertTrue(result.isDisplayable)
    }

    func testPolicyGateRejectsTracerForAnUncertainShot() async {
        let proposal = ShotEventProposal(sourceTime: 12, signals: [.impactLikeAudio], confidence: 0.8)
        let evidence = RealShotEvidence(
            targetGolferSwing: .init(state: .unavailable, sourceDescription: "No association"),
            ballLaunch: .init(state: .modelUnavailable, detectorDescription: "No model")
        )
        let shot = AcceptedShot(
            proposal: proposal,
            evidence: evidence,
            decision: .init(kind: .uncertain, explanation: "Fixture", confidence: 0.8),
            clipPlan: .init(acceptedShotID: UUID(), sourceRange: .init(start: 7, duration: 10), impactTime: 12),
            tracerEligibility: .ineligibleModelUnavailable
        )

        do {
            _ = try await GolfBallTrajectoryAnalysisService().analyse(
                url: URL(fileURLWithPath: "/missing.mov"),
                acceptedShot: shot
            )
            XCTFail("An uncertain moment must not reach tracer analysis.")
        } catch let error as GolfBallTrajectoryAnalysisError {
            XCTAssertEqual(error, .ineligibleShot)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
