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

    func testFullFlightTimelineRevealsLaunchObservationAndContinuationChronologically() throws {
        let fixture = try makeFullFlightTimelineFixture()
        let timeline = fixture.timeline

        let launchRange = try XCTUnwrap(timeline.launchRange)
        let continuationRange = try XCTUnwrap(timeline.continuationRange)
        XCTAssertEqual(launchRange.upperBound, timeline.observedRange.lowerBound, accuracy: 0.000_001)
        XCTAssertEqual(timeline.observedRange.upperBound, continuationRange.lowerBound, accuracy: 0.000_001)

        let launchTime = 1.20
        let observationTime = 1.85
        let continuationTime = 2.50
        let launchDistance = timeline.visibleDistance(at: launchTime)
        let observationDistance = timeline.visibleDistance(at: observationTime)
        let continuationDistance = timeline.visibleDistance(at: continuationTime)

        XCTAssertGreaterThan(launchDistance, launchRange.lowerBound)
        XCTAssertLessThan(launchDistance, launchRange.upperBound)
        XCTAssertGreaterThanOrEqual(observationDistance, timeline.observedRange.lowerBound)
        XCTAssertLessThan(observationDistance, timeline.observedRange.upperBound)
        XCTAssertNil(continuationRange.visibleRange(through: observationDistance))
        XCTAssertGreaterThan(continuationDistance, continuationRange.lowerBound)
        XCTAssertLessThan(continuationDistance, continuationRange.upperBound)
        XCTAssertEqual(timeline.visibleDistance(at: timeline.endTime), 1, accuracy: 0.000_001)
    }

    func testFullFlightTimelineNeverRevealsAFutureObservedPoint() throws {
        let fixture = try makeFullFlightTimelineFixture()
        let timeline = fixture.timeline
        let secondObservedTime = fixture.observedTimes[1]
        let secondObservedDistance = try XCTUnwrap(timeline.distance(for: fixture.observedPoints[1]))

        XCTAssertLessThan(
            timeline.visibleDistance(
                at: secondObservedTime + timeline.observedTrailLag - 0.001
            ),
            secondObservedDistance
        )
        XCTAssertEqual(
            timeline.visibleDistance(at: secondObservedTime + timeline.observedTrailLag),
            secondObservedDistance,
            accuracy: 0.000_001
        )
    }

    func testFullFlightTimelineKeyframesMatchPlaybackDistanceAndStayMonotonic() throws {
        let timeline = try makeFullFlightTimelineFixture().timeline
        let keyframes = timeline.strokeRevealKeyframes()
        XCTAssertEqual(keyframes.keyTimes.count, keyframes.strokeValues.count)
        XCTAssertEqual(keyframes.keyTimes.first, 0)
        XCTAssertEqual(keyframes.keyTimes.last, 1)
        XCTAssertEqual(keyframes.strokeValues.first, 0)
        XCTAssertEqual(keyframes.strokeValues.last, 1)

        for index in keyframes.keyTimes.indices {
            let presentationTime = timeline.impactTime
                + ((timeline.endTime - timeline.impactTime) * keyframes.keyTimes[index])
            XCTAssertEqual(
                timeline.visibleDistance(at: presentationTime),
                keyframes.strokeValues[index],
                accuracy: 0.000_001
            )
            if index > 0 {
                XCTAssertGreaterThanOrEqual(keyframes.keyTimes[index], keyframes.keyTimes[index - 1])
                XCTAssertGreaterThanOrEqual(keyframes.strokeValues[index], keyframes.strokeValues[index - 1])
            }
        }
    }

    func testFullFlightTimelineReducedMotionRevealsOnlyAfterImpact() throws {
        let timeline = try makeFullFlightTimelineFixture().timeline

        XCTAssertEqual(timeline.visibleDistance(at: timeline.impactTime - 0.001, reducesMotion: true), 0)
        XCTAssertEqual(timeline.visibleDistance(at: timeline.impactTime, reducesMotion: true), 1)
    }

    func testFullFlightPresentationLeavesAtMostA120MillisecondHold() {
        let duration = FullFlightRevealTimeline.presentationFlightDuration(
            modelFlightDuration: 5.04,
            impactTime: 1.632,
            lastObservedTime: 2.50,
            availablePostImpactDuration: 4.683,
            observedTrailLag: 0.050
        )

        XCTAssertEqual(duration, 4.563, accuracy: 0.001)
        XCTAssertLessThan(duration, 4.683)
        XCTAssertLessThanOrEqual(4.683 - duration, 0.120_001)
        XCTAssertGreaterThan(duration, 2.50 - 1.632 + 0.050)
    }

    func testFullFlightPresentationKeepsModelTimingAndCausalLagWhenItFits() {
        XCTAssertEqual(
            FullFlightRevealTimeline.presentationFlightDuration(
                modelFlightDuration: 2.4,
                impactTime: 1.0,
                lastObservedTime: 1.8,
                availablePostImpactDuration: 4.0,
                observedTrailLag: 0.050
            ),
            2.45,
            accuracy: 0.000_001
        )
    }

    func testShortPresentationPreservesApexTimingAndCompressesOnlyDescent() throws {
        let full = try makeCausalContinuationTimeline(presentationDuration: nil)
        let short = try makeCausalContinuationTimeline(presentationDuration: 3.70)
        let ascentPoint = NormalizedPoint(x: 0.76, y: 0.20)
        let apex = NormalizedPoint(x: 0.80, y: 0.16)
        let firstDescentPoint = NormalizedPoint(x: 0.84, y: 0.22)

        XCTAssertEqual(
            try XCTUnwrap(short.revealTime(for: ascentPoint)),
            try XCTUnwrap(full.revealTime(for: ascentPoint)),
            accuracy: 0.000_001
        )
        let shortApexTime = try XCTUnwrap(short.revealTime(for: apex))
        XCTAssertEqual(
            shortApexTime,
            try XCTUnwrap(full.revealTime(for: apex)),
            accuracy: 0.000_001
        )
        XCTAssertLessThan(
            try XCTUnwrap(short.revealTime(for: firstDescentPoint)),
            try XCTUnwrap(full.revealTime(for: firstDescentPoint))
        )
        XCTAssertLessThan(
            short.visibleDistance(at: shortApexTime - 0.001),
            try XCTUnwrap(short.distance(for: apex))
        )
        XCTAssertTrue(short.revealsEstimatedLanding)
        let keyframes = short.strokeRevealKeyframes()
        XCTAssertEqual(keyframes.keyTimes.last, 1)
        XCTAssertEqual(keyframes.strokeValues.last, 1)
    }

    func testSourceTooShortForModelApexWithholdsApexLandingAndCarryGate() throws {
        let timeline = try makeCausalContinuationTimeline(presentationDuration: 1.60)
        let apex = NormalizedPoint(x: 0.80, y: 0.16)

        XCTAssertFalse(timeline.revealsEstimatedLanding)
        XCTAssertNil(timeline.revealTime(for: apex))
        XCTAssertNil(timeline.continuationRange)
        XCTAssertLessThan(timeline.endTime, 1.0 + 1.60)
    }

    func testContinuationResidualDecaysAndLandingStaysInObservedDirection() {
        XCTAssertEqual(
            EvidenceAnchoredFlightPathExtrapolator.continuationResidualWeight(progress: 0),
            1,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            EvidenceAnchoredFlightPathExtrapolator.continuationResidualWeight(progress: 1),
            0,
            accuracy: 0.000_001
        )

        let firstX = 0.532
        let lastX = 0.522
        let boundedLandingX = EvidenceAnchoredFlightPathExtrapolator.boundedLandingX(
            firstObservedX: firstX,
            lastObservedX: lastX,
            rawLandingX: 0.404
        )
        let maximumDX = EvidenceAnchoredFlightPathExtrapolator.maximumLandingDX(
            observedDX: lastX - firstX
        )

        XCTAssertLessThan(boundedLandingX, lastX)
        XCTAssertLessThanOrEqual(abs(boundedLandingX - lastX), maximumDX + 0.000_001)
        XCTAssertEqual(boundedLandingX, 0.489, accuracy: 0.000_001)
        XCTAssertEqual(EvidenceAnchoredFlightPathExtrapolator.smoothstep(0), 0)
        XCTAssertEqual(EvidenceAnchoredFlightPathExtrapolator.smoothstep(1), 1)
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
        let observedDX = observedEndpoint.x - trajectory.detectedPoints[0].x
        let landingDX = landing.x - observedEndpoint.x
        XCTAssertLessThanOrEqual(
            abs(landingDX),
            EvidenceAnchoredFlightPathExtrapolator.maximumLandingDX(observedDX: observedDX)
                + 0.000_001
        )
        if abs(observedDX) >= 0.002, abs(landingDX) > 0.000_001 {
            XCTAssertEqual(landingDX.sign, observedDX.sign)
        }
        XCTAssertTrue(path.inferredContinuation.allSatisfy { point in
            (0.035...0.965).contains(point.x) && (0.035...0.965).contains(point.y)
        })
    }

    func testExtrapolatorStartsAtAnObservedLaunchAnchorWhenAvailable() throws {
        let timestamps = (0..<18).map { 1.90 + (Double($0) / 30) }
        let points = timestamps.map { timestamp in
            let elapsed = timestamp - 1.90
            let decay = 1 - exp(-1.6 * elapsed)
            return NormalizedPoint(
                x: 0.532 - (0.014 * decay),
                y: 0.230 - (0.115 * decay)
            )
        }
        let trajectory = DetectedTrajectory(
            detectedPoints: points,
            projectedPoints: [],
            presentationTimes: timestamps,
            equationCoefficients: [],
            confidence: 0.88
        )
        let anchor = NormalizedPoint(x: 0.523, y: 0.755)
        let estimate = BallFlightEstimate(
            launch: points[0],
            apex: points[points.count / 2],
            landing: points[points.count - 1],
            observedLaunchAnchor: anchor,
            source: .observed,
            confidence: 0.88,
            observedPointCount: points.count,
            observedTrajectory: trajectory
        )

        let path = try XCTUnwrap(EvidenceAnchoredFlightPathExtrapolator().path(
            from: estimate,
            impactTime: 1.632
        ))
        let firstConnectorPoint = try XCTUnwrap(path.inferredLaunchConnector.first)

        XCTAssertEqual(firstConnectorPoint.x, anchor.x, accuracy: 0.003)
        XCTAssertEqual(firstConnectorPoint.y, anchor.y, accuracy: 0.003)
        XCTAssertEqual(path.inferredLaunchPresentationDuration, 1.90 - 1.632, accuracy: 0.001)
        XCTAssertEqual(path.inferredLaunchSegmentPoints.last, points.first)
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

    private func makeFullFlightTimelineFixture() throws -> (
        timeline: FullFlightRevealTimeline,
        observedPoints: [NormalizedPoint],
        observedTimes: [TimeInterval]
    ) {
        let observedPoints = [
            NormalizedPoint(x: 0.30, y: 0.60),
            NormalizedPoint(x: 0.50, y: 0.34),
            NormalizedPoint(x: 0.70, y: 0.22)
        ]
        let observedTimes = [1.40, 1.70, 2.00]
        let timeline = try XCTUnwrap(FullFlightRevealTimeline(
            impactTime: 1.00,
            inferredLaunchConnector: [
                .init(x: 0.10, y: 0.82),
                .init(x: 0.20, y: 0.72)
            ],
            observedPoints: observedPoints,
            observedPresentationTimes: observedTimes,
            inferredContinuation: [
                .init(x: 0.80, y: 0.34),
                .init(x: 0.90, y: 0.76)
            ],
            estimatedFlightDuration: 2.00
        ))
        return (timeline, observedPoints, observedTimes)
    }

    private func makeCausalContinuationTimeline(
        presentationDuration: TimeInterval?
    ) throws -> FullFlightRevealTimeline {
        try XCTUnwrap(FullFlightRevealTimeline(
            impactTime: 1.00,
            inferredLaunchConnector: [
                .init(x: 0.10, y: 0.82),
                .init(x: 0.20, y: 0.72)
            ],
            observedPoints: [
                .init(x: 0.30, y: 0.60),
                .init(x: 0.50, y: 0.34),
                .init(x: 0.70, y: 0.22)
            ],
            observedPresentationTimes: [1.40, 1.70, 2.00],
            inferredContinuation: [
                .init(x: 0.76, y: 0.20),
                .init(x: 0.80, y: 0.16),
                .init(x: 0.84, y: 0.22),
                .init(x: 0.88, y: 0.38),
                .init(x: 0.90, y: 0.70)
            ],
            estimatedFlightDuration: 4.00,
            presentationFlightDuration: presentationDuration
        ))
    }
}
