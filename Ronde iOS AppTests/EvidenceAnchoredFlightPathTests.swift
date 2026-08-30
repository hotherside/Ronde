import AVFoundation
import Foundation
import XCTest
@testable import Ronde

final class EvidenceAnchoredFlightPathTests: XCTestCase {
    func testOptionalTimedTracerExportRendersAPlayableMovie() async throws {
        guard let path = ProcessInfo.processInfo.environment["RONDE_TEST_EXPORT_FIXTURE_PATH"],
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            return
        }
        let sourceURL = URL(fileURLWithPath: path)
        let flightPath = try XCTUnwrap(EvidenceAnchoredFlightPath(
            inferredLaunchConnector: [
                .init(x: 0.18, y: 0.78),
                .init(x: 0.21, y: 0.70)
            ],
            observedPoints: [
                .init(x: 0.24, y: 0.63),
                .init(x: 0.37, y: 0.43),
                .init(x: 0.56, y: 0.26),
                .init(x: 0.69, y: 0.23)
            ],
            inferredContinuation: [
                .init(x: 0.77, y: 0.29),
                .init(x: 0.84, y: 0.43),
                .init(x: 0.89, y: 0.69)
            ],
            observedPresentationTimes: [0.50, 0.80, 1.20, 1.60],
            inferredLaunchPresentationDuration: 0.32,
            inferredPresentationDuration: 0.80,
            estimatedFlightDuration: 2.40,
            estimatedCarry: .init(lowerMetres: 95, upperMetres: 155),
            fitError: 0.006,
            confidence: 0.88
        ))
        let geometry = try XCTUnwrap(TracedVideoTracerGeometry(path: flightPath))
        let outputURL = try await TracedVideoExporter().export(TracedVideoExportRequest(
            sourceURL: sourceURL,
            sourceRange: ReviewTimeRange(start: 0, duration: 3),
            revealStartTime: 0.50,
            geometry: geometry
        ))
        let renderedAsset = AVURLAsset(url: outputURL)
        let renderedDuration = CMTimeGetSeconds(try await renderedAsset.load(.duration))
        let renderedVideoTrack = try await renderedAsset.loadTracks(withMediaType: .video).first

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertGreaterThan(renderedDuration, 2.9)
        XCTAssertNotNil(renderedVideoTrack)
        print("TIMED_EXPORT_PROBE output=\(outputURL.path)")
    }

    func testOptionalSuppliedLandscapeShotProducesTimedExportAndFullShotCarry() async throws {
        guard let path = ProcessInfo.processInfo.environment["RONDE_TEST_LANDSCAPE_SHOT_PATH"],
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            return
        }
        let sourceURL = URL(fileURLWithPath: path)
        let impactCandidates = try await AudioImpactAnalysisService().analyse(url: sourceURL)
        let impact = try XCTUnwrap(impactCandidates.max(by: {
            $0.classification.confidence < $1.classification.confidence
        }))
        let estimate = try await WASBGolfBallTrackingService().analyse(
            url: sourceURL,
            impactTime: impact.impactTime,
            configuration: WASBGolfBallTrackingConfiguration(
                maximumPostImpactDuration: 0.88,
                minimumPeakConfidence: 0.08,
                maximumCandidatesPerFrame: 8,
                diagnosticTileOrigins: [
                    NormalizedPoint(x: 1_664.0 / 3_840.0, y: 224.0 / 2_160.0),
                    NormalizedPoint(x: 1_664.0 / 3_840.0, y: 448.0 / 2_160.0)
                ]
            )
        )
        let flightPath = try XCTUnwrap(EvidenceAnchoredFlightPathExtrapolator().path(
            from: estimate,
            impactTime: impact.impactTime
        ))
        let carry = try XCTUnwrap(flightPath.estimatedCarry)
        let timedPath = try XCTUnwrap(TimedTrajectoryPath(
            points: flightPath.observedPoints,
            presentationTimes: flightPath.observedPresentationTimes
        ))

        XCTAssertGreaterThanOrEqual(flightPath.observedPoints.count, 6)
        XCTAssertGreaterThan(timedPath.endTime, timedPath.startTime)
        XCTAssertGreaterThanOrEqual(carry.lowerMetres, 80)

        print(
            "SUPPLIED_SHOT_PROBE impact=\(impact.impactTime) observed=\(flightPath.observedPoints.count) "
                + "observedStart=\(timedPath.startTime) observedEnd=\(timedPath.endTime) "
                + "carry=\(carry.displayText) apex=\(String(describing: flightPath.apexPoint)) "
                + "landing=\(String(describing: flightPath.inferredLanding))"
        )
    }

    func testTimedTrajectoryVisiblePrefixNeverLeadsRequestedSourceTime() throws {
        let trajectory = try XCTUnwrap(TimedTrajectoryPath(
            points: [
                .init(x: 0.10, y: 0.80),
                .init(x: 0.30, y: 0.55),
                .init(x: 0.90, y: 0.20)
            ],
            presentationTimes: [2.0, 2.2, 2.8]
        ))

        XCTAssertTrue(trajectory.visibleSamples(at: 1.99).isEmpty)
        let visible = trajectory.visibleSamples(at: 2.5)
        let head = try XCTUnwrap(visible.last)
        XCTAssertEqual(head.presentationTime, 2.5, accuracy: 0.000_001)
        XCTAssertEqual(head.point.x, 0.60, accuracy: 0.000_001)
        XCTAssertEqual(head.point.y, 0.375, accuracy: 0.000_001)
        XCTAssertLessThan(head.point.x, 0.90)

        let trailHead = try XCTUnwrap(trajectory.visibleTrailSamples(at: 2.5).last)
        XCTAssertGreaterThan(trajectory.suggestedTrailLag, 0)
        XCTAssertEqual(
            trailHead.presentationTime,
            2.5 - trajectory.suggestedTrailLag,
            accuracy: 0.000_001
        )
        XCTAssertLessThan(trailHead.point.x, head.point.x)
    }

    func testTimedTrajectoryMapsSourceTimeToNonUniformPathLength() throws {
        let trajectory = try XCTUnwrap(TimedTrajectoryPath(
            points: [
                .init(x: 0.0, y: 0.5),
                .init(x: 0.9, y: 0.5),
                .init(x: 1.0, y: 0.5)
            ],
            presentationTimes: [0, 0.5, 1]
        ))

        let keyframes = trajectory.strokeRevealKeyframes(subdivisions: 1)
        XCTAssertEqual(keyframes.keyTimes, [0, 0.5, 1])
        XCTAssertEqual(keyframes.strokeValues[1], 0.9, accuracy: 0.000_001)
        XCTAssertNotEqual(keyframes.strokeValues[1], keyframes.keyTimes[1])
    }

    func testTimedTrajectoryRejectsMissingOrNonMonotonicSourceTimes() {
        let points = [NormalizedPoint(x: 0.2, y: 0.8), NormalizedPoint(x: 0.4, y: 0.6)]

        XCTAssertNil(TimedTrajectoryPath(points: points, presentationTimes: []))
        XCTAssertNil(TimedTrajectoryPath(points: points, presentationTimes: [1, 1]))
        XCTAssertNil(TimedTrajectoryPath(points: points, presentationTimes: [1.1, 1.0]))
    }

    func testExtrapolatorBuildsABoundedFullEstimatedFlightFromObservedSourceFrames() throws {
        let timestamps = (0..<18).map { 8.00 + (Double($0) / 30) }
        let points = timestamps.map { timestamp in
            let elapsed = timestamp - 8.00
            let decay = 1 - exp(-1.6 * elapsed)
            return NormalizedPoint(
                x: 0.56 - (0.03 * decay),
                y: 0.35 - (0.16 * decay)
            )
        }
        let trajectory = DetectedTrajectory(
            detectedPoints: points,
            projectedPoints: [],
            presentationTimes: timestamps,
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

        let path = try XCTUnwrap(EvidenceAnchoredFlightPathExtrapolator().path(
            from: estimate,
            impactTime: 7.72
        ))

        XCTAssertEqual(path.observedPoints, trajectory.detectedPoints)
        XCTAssertEqual(path.observedPresentationTimes, trajectory.presentationTimes)
        XCTAssertEqual(path.source, .observedAndInferred)
        XCTAssertFalse(path.inferredLaunchConnector.isEmpty)
        let estimatedLaunch = try XCTUnwrap(path.inferredLaunchConnector.first)
        XCTAssertGreaterThan(estimatedLaunch.y, trajectory.detectedPoints[0].y)
        XCTAssertLessThanOrEqual(
            estimatedLaunch.y,
            trajectory.detectedPoints[0].y + 0.620_001,
            "The estimated launch connector must not run arbitrarily below the observed ball track."
        )
        XCTAssertGreaterThanOrEqual(path.inferredContinuation.count, 24)
        XCTAssertEqual(path.inferredLaunchSegmentPoints.last, trajectory.detectedPoints.first)
        XCTAssertEqual(path.inferredSegmentPoints.first, trajectory.detectedPoints.last)
        let observedStart = path.inferredLaunchConnector.count
        let observedDisplaySlice = Array(path.allDisplayPoints[observedStart..<(observedStart + points.count)])
        XCTAssertEqual(observedDisplaySlice, trajectory.detectedPoints)
        XCTAssertEqual(path.observedDuration ?? -1, 17.0 / 30.0, accuracy: 0.0001)
        XCTAssertNotNil(path.estimatedCarry)
        XCTAssertGreaterThan(path.estimatedFlightDuration ?? 0, path.observedDuration ?? 0)

        let apex = try XCTUnwrap(path.inferredApex)
        let landing = try XCTUnwrap(path.inferredLanding)
        let observedEndpoint = try XCTUnwrap(trajectory.detectedPoints.last)
        XCTAssertLessThan(apex.y, observedEndpoint.y, "The estimated apex occurs after the observed endpoint.")
        XCTAssertGreaterThan(landing.y, apex.y, "The estimated path returns from the later apex to a landing.")
        XCTAssertGreaterThanOrEqual(landing.x, 0.035)
        XCTAssertLessThanOrEqual(landing.x, 0.965)
        XCTAssertGreaterThanOrEqual(landing.y, 0.035)
        XCTAssertLessThanOrEqual(landing.y, 0.965)
        XCTAssertTrue(path.inferredContinuation.allSatisfy { point in
            (0.035...0.965).contains(point.x) && (0.035...0.965).contains(point.y)
        })
    }

    func testShotVideoPolicyRejectsLongSessionFootage() {
        XCTAssertTrue(ShotVideoImportPolicy.accepts(duration: 59.9))
        XCTAssertTrue(ShotVideoImportPolicy.accepts(duration: 60))
        XCTAssertFalse(ShotVideoImportPolicy.accepts(duration: 60.01))
        XCTAssertFalse(ShotVideoImportPolicy.accepts(duration: 0))
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
        XCTAssertTrue(geometry.observedPresentationTimes.isEmpty)
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
