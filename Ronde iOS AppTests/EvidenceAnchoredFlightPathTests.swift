import Foundation
import XCTest
@testable import Ronde

final class EvidenceAnchoredFlightPathTests: XCTestCase {
    func testExtrapolatorBuildsABoundedFullEstimatedFlightFromObservedSourceFrames() throws {
        let trajectory = DetectedTrajectory(
            detectedPoints: [
                .init(x: 0.38, y: 0.64),
                .init(x: 0.44, y: 0.56),
                .init(x: 0.50, y: 0.50),
                .init(x: 0.56, y: 0.47)
            ],
            projectedPoints: [],
            presentationTimes: [8.00, 8.04, 8.08, 8.12],
            equationCoefficients: [],
            confidence: 0.86
        )
        let estimate = BallFlightEstimate(
            launch: trajectory.detectedPoints[0],
            apex: trajectory.detectedPoints[2],
            landing: trajectory.detectedPoints[3],
            source: .observed,
            confidence: 0.86,
            observedPointCount: trajectory.detectedPoints.count,
            observedTrajectory: trajectory
        )

        let path = try XCTUnwrap(EvidenceAnchoredFlightPathExtrapolator().path(from: estimate))

        XCTAssertEqual(path.observedPoints, trajectory.detectedPoints)
        XCTAssertEqual(path.observedPresentationTimes, trajectory.presentationTimes)
        XCTAssertEqual(path.source, .observedAndInferred)
        XCTAssertGreaterThanOrEqual(path.inferredContinuation.count, 24)
        XCTAssertEqual(path.inferredSegmentPoints.first, trajectory.detectedPoints.last)
        let observedDisplayPrefix = Array(path.allDisplayPoints.prefix(trajectory.detectedPoints.count))
        XCTAssertEqual(observedDisplayPrefix, trajectory.detectedPoints)
        XCTAssertEqual(path.observedDuration ?? -1, 0.12, accuracy: 0.0001)

        let apex = try XCTUnwrap(path.inferredApex)
        let landing = try XCTUnwrap(path.inferredLanding)
        let observedEndpoint = try XCTUnwrap(trajectory.detectedPoints.last)
        XCTAssertLessThan(apex.y, observedEndpoint.y, "The estimated apex occurs after the observed endpoint.")
        XCTAssertGreaterThan(landing.y, apex.y, "The estimated path returns from the later apex to a landing.")
        XCTAssertGreaterThanOrEqual(landing.y, trajectory.detectedPoints.first?.y ?? 0)
        XCTAssertGreaterThanOrEqual(landing.x, 0.035)
        XCTAssertLessThanOrEqual(landing.x, 0.965)
        XCTAssertGreaterThanOrEqual(landing.y, 0.035)
        XCTAssertLessThanOrEqual(landing.y, 0.965)
        XCTAssertTrue(path.inferredContinuation.allSatisfy { point in
            (0.035...0.965).contains(point.x) && (0.035...0.965).contains(point.y)
        })
    }

    func testExtrapolatorDoesNotUpgradeGenericOrInferredGeometry() {
        let trajectory = DetectedTrajectory(
            detectedPoints: [
                .init(x: 0.42, y: 0.60),
                .init(x: 0.47, y: 0.54),
                .init(x: 0.51, y: 0.50)
            ],
            projectedPoints: [],
            equationCoefficients: [],
            confidence: 0.91
        )
        let inferred = BallFlightEstimate(
            launch: trajectory.detectedPoints[0],
            apex: trajectory.detectedPoints[1],
            landing: trajectory.detectedPoints[2],
            source: .inferred,
            confidence: 0.91,
            observedPointCount: trajectory.detectedPoints.count,
            observedTrajectory: trajectory
        )

        XCTAssertNil(EvidenceAnchoredFlightPathExtrapolator().path(from: inferred))
    }

    func testObservedTrackWithoutPresentationTimesDoesNotGainAnEstimatedFlight() throws {
        let trajectory = DetectedTrajectory(
            detectedPoints: [
                .init(x: 0.41, y: 0.67),
                .init(x: 0.48, y: 0.58),
                .init(x: 0.55, y: 0.51)
            ],
            projectedPoints: [],
            equationCoefficients: [],
            confidence: 0.83
        )
        let estimate = BallFlightEstimate(
            launch: trajectory.detectedPoints[0],
            apex: trajectory.detectedPoints[1],
            landing: trajectory.detectedPoints[2],
            source: .observed,
            confidence: 0.83,
            observedPointCount: 3,
            observedTrajectory: trajectory
        )

        let path = try XCTUnwrap(EvidenceAnchoredFlightPathExtrapolator().path(from: estimate))
        XCTAssertEqual(path.source, .observed)
        XCTAssertTrue(path.inferredContinuation.isEmpty)
    }

    func testManualExportGeometryStaysManualAndContainsNoInferredAutomaticSegment() {
        let geometry = TracedVideoTracerGeometry(
            manualLaunch: .init(x: 0.40, y: 0.68),
            apex: .init(x: 0.56, y: 0.30),
            landing: .init(x: 0.74, y: 0.60)
        )

        XCTAssertEqual(geometry.provenance, .userAssisted)
        XCTAssertTrue(geometry.inferredContinuation.isEmpty)
        XCTAssertEqual(geometry.observedPoints.count, 15)
    }

    func testSingleGolferAssociatorFailsClosedUntilAllSessionConditionsAreConfirmed() async {
        let disabled = FixedCameraSingleGolferAssociator(sessionEvidence: .init(
            cameraWasFixedForSession: true,
            targetGolferWasExplicitlyConfirmed: true,
            noOtherGolferWasConfirmedInFrame: false
        ))
        let proposal = ShotEventProposal(
            sourceTime: 42.2,
            signals: [.targetBodyMotion],
            confidence: 0.91
        )
        let unavailable = await disabled.swingImpactEvidence(for: proposal, in: URL(fileURLWithPath: "/tmp/range.mov"))
        XCTAssertEqual(unavailable.state, .unavailable)

        let enabled = FixedCameraSingleGolferAssociator(sessionEvidence: .init(
            cameraWasFixedForSession: true,
            targetGolferWasExplicitlyConfirmed: true,
            noOtherGolferWasConfirmedInFrame: true
        ))
        let supported = await enabled.swingImpactEvidence(for: proposal, in: URL(fileURLWithPath: "/tmp/range.mov"))
        XCTAssertEqual(supported.state, .supported)
        XCTAssertEqual(supported.impactTime, proposal.sourceTime)
        XCTAssertEqual(supported.confidence, proposal.confidence)
    }

    @MainActor
    func testManualRescueIsRetainedByTheCurrentReviewSessionWithoutBecomingObservedFlight() {
        let candidate = ReviewCandidate(
            ordinal: 1,
            impactTime: 3,
            sourceDuration: 8,
            classification: .uncertain,
            confidence: .low,
            evidence: ["Ball flight not tracked"]
        )
        let session = ReviewSession(
            id: UUID(),
            mode: .range,
            importKind: .oneShot,
            title: "Manual rescue",
            sourceName: nil,
            sourceURL: nil,
            createdAt: .now,
            duration: 8,
            status: .reviewing,
            progress: 1,
            candidates: [candidate]
        )
        let store = ReviewerStore()
        store.sessions = [session]

        let path = store.startManualTracer(for: candidate, in: session)
        let updated = try! XCTUnwrap(store.sessions.first?.candidates.first)

        XCTAssertEqual(updated.assistedTracer, path)
        XCTAssertTrue(updated.tracerAvailable)
        XCTAssertEqual(updated.tracerSource, .inferred)
        XCTAssertNil(updated.evidenceAnchoredPath)
        XCTAssertTrue(updated.evidence.contains("User-assisted tracer"))
    }

    @MainActor
    func testRangeDetectorOptInRequiresCompleteExplicitSingleGolferEvidence() {
        let store = ReviewerStore()
        XCTAssertNil(store.fixedSingleGolferSessionEvidence)

        let incomplete = store.configureFixedSingleGolferRangeAnalysis(with: .init(
            cameraWasFixedForSession: true,
            targetGolferWasExplicitlyConfirmed: true,
            noOtherGolferWasConfirmedInFrame: false
        ))
        XCTAssertFalse(incomplete)
        XCTAssertNil(store.fixedSingleGolferSessionEvidence)

        let enabled = store.configureFixedSingleGolferRangeAnalysis(with: .init(
            cameraWasFixedForSession: true,
            targetGolferWasExplicitlyConfirmed: true,
            noOtherGolferWasConfirmedInFrame: true
        ))
        XCTAssertTrue(enabled)
        XCTAssertEqual(store.fixedSingleGolferSessionEvidence?.permitsAssociation, true)
    }
}
