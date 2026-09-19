import Foundation
import XCTest
@testable import Ronde

final class ShotReviewDomainTests: XCTestCase {
    func testImportIntentRatherThanDurationChoosesTheReviewExperience() {
        let shortRangeSession = ReviewSession(
            id: UUID(),
            mode: .range,
            importKind: .rangeSession,
            title: "Short range burst",
            sourceName: nil,
            sourceURL: nil,
            createdAt: .now,
            duration: 18,
            status: .reviewing,
            progress: 1,
            candidates: []
        )
        let longOneShot = ReviewSession(
            id: UUID(),
            mode: .range,
            importKind: .oneShot,
            title: "Slow setup",
            sourceName: nil,
            sourceURL: nil,
            createdAt: .now,
            duration: 42,
            status: .reviewing,
            progress: 1,
            candidates: []
        )

        XCTAssertFalse(shortRangeSession.isSingleShotImport)
        XCTAssertTrue(longOneShot.isSingleShotImport)
    }

    func testImpactWindowClampsAtStartAndEnd() {
        let early = ImpactClipWindow(impactTime: 2).clipped(to: 30)
        XCTAssertEqual(early.start, 0, accuracy: 0.0001)
        XCTAssertEqual(early.duration, 7, accuracy: 0.0001)

        let late = ImpactClipWindow(impactTime: 28).clipped(to: 30)
        XCTAssertEqual(late.start, 23, accuracy: 0.0001)
        XCTAssertEqual(late.duration, 7, accuracy: 0.0001)
    }

    func testReviewTimeRangeClipsToFiniteSourceAndRejectsMalformedValues() {
        XCTAssertEqual(
            ReviewTimeRange(start: 8, duration: 8).clipped(to: 10),
            .init(start: 8, duration: 2)
        )
        XCTAssertEqual(
            ReviewTimeRange(start: 20, duration: 1).clipped(to: 10),
            .init(start: 10, duration: 0)
        )
        XCTAssertEqual(ReviewTimeRange(start: .infinity, duration: 1), .init(start: 0, duration: 1))
        XCTAssertEqual(ReviewTimeRange(start: 2, duration: .infinity), .init(start: 2, duration: 0))
        XCTAssertEqual(
            ReviewTimeRange(start: 2, duration: 1).clipped(to: .infinity),
            .init(start: 0, duration: 0)
        )
    }

    func testRecordingBookmarkClampsItsManualClipToTheOriginalSource() {
        let early = RecordingBookmark(sourceTime: -5, beforeDuration: 8, afterDuration: 5)
        XCTAssertEqual(early.clipRange(sourceDuration: 120), .init(start: 0, duration: 5))

        let late = RecordingBookmark(sourceTime: 119, beforeDuration: 5, afterDuration: 9)
        XCTAssertEqual(late.clipRange(sourceDuration: 120), .init(start: 114, duration: 6))
    }

    @MainActor
    func testManualBookmarkCreatesAnEvidenceFreeSourceLinkedShotAndDoesNotDuplicateIt() throws {
        let store = ReviewerStore()
        let recording = Self.recording(duration: 600)
        store.sessions = [recording]

        let bookmark = try XCTUnwrap(store.addBookmark(at: 120, to: recording))
        XCTAssertEqual(store.addBookmark(at: 120.02, to: recording)?.id, bookmark.id)

        let created = store.createShots(from: recording)
        let shotID = try XCTUnwrap(created.first)
        let shot = try XCTUnwrap(store.sessions.first { $0.id == shotID })
        XCTAssertEqual(shot.sourceRecordingID, recording.id)
        XCTAssertEqual(shot.sourceBookmarkID, bookmark.id)
        XCTAssertEqual(shot.duration, recording.duration)
        XCTAssertEqual(shot.sourceClipRange, .init(start: 115, duration: 10))
        XCTAssertEqual(shot.videoEdit?.sourceRange, shot.sourceClipRange)
        XCTAssertEqual(shot.displayRange, shot.sourceClipRange)
        XCTAssertFalse(try XCTUnwrap(shot.defaultCandidate).hasAutomaticTracer)
        XCTAssertEqual(try XCTUnwrap(shot.defaultCandidate).tracerSource, .unavailable)
        XCTAssertNil(shot.errorMessage)
        XCTAssertTrue(store.createShots(from: recording).isEmpty)
    }

    @MainActor
    func testRepeatBookmarkExtractionPreservesAnIndependentlyEditedShot() throws {
        let store = ReviewerStore()
        let recording = Self.recording(duration: 600)
        store.sessions = [recording]
        let bookmark = try XCTUnwrap(store.addBookmark(at: 120, to: recording))
        let shotID = try XCTUnwrap(store.createShots(from: recording).first)
        let shot = try XCTUnwrap(store.sessions.first { $0.id == shotID })
        XCTAssertTrue(store.setVideoEdit(ShotVideoEdit(trimStart: 116, trimEnd: 123, overlay: .original), for: shot))

        XCTAssertTrue(store.createShots(from: recording, bookmarkIDs: [bookmark.id]).isEmpty)
        let edited = try XCTUnwrap(store.sessions.first { $0.id == shotID })
        XCTAssertEqual(edited.videoEdit?.sourceRange, .init(start: 116, duration: 7))
        XCTAssertEqual(edited.displayRange, .init(start: 116, duration: 7))

        let nextBookmark = try XCTUnwrap(store.addBookmark(at: 240, to: recording))
        let nextShotID = try XCTUnwrap(store.createShots(from: recording, bookmarkIDs: [nextBookmark.id]).first)
        XCTAssertEqual(store.sessions.first { $0.id == nextShotID }?.title, "Practice session shot 2")
    }

    @MainActor
    func testLegacyRowsFormAStableSingleShotGroup() {
        let store = ReviewerStore(includeFixtures: true)
        let group = try! XCTUnwrap(store.sessionGroups.first)

        XCTAssertEqual(group.id, ReviewFixtures.quickReviewSession.id)
        XCTAssertEqual(group.recordings.map(\.id), [ReviewFixtures.quickReviewSession.id])
        XCTAssertEqual(group.shots.map(\.id), [ReviewFixtures.quickReviewSession.id])
    }

    func testProvisionalServiceRequiresTwoIndependentSignals() {
        let service = ProvisionalSwingCandidateService()
        let insufficient = service.candidate(from: .init(
            impactTime: 4,
            hasTrajectory: true,
            hasBodyMotion: false,
            hasAudioTransient: false,
            trajectory: nil
        ))
        XCTAssertNil(insufficient)

        let candidate = service.candidate(from: .init(
            impactTime: 4,
            hasTrajectory: true,
            hasBodyMotion: true,
            hasAudioTransient: false,
            trajectory: nil
        ))
        XCTAssertEqual(candidate?.classification.kind, .uncertainCandidate)
        XCTAssertFalse(candidate?.classification.isModelBacked ?? true)
        XCTAssertEqual(candidate?.evidence, [.trajectory, .bodyMotion])
    }

    func testRollingLedgerKeepsProtectedSegments() {
        var ledger = RollingSegmentLedger(retentionDuration: 8)
        let old = FinalizedCaptureSegment(url: URL(fileURLWithPath: "/tmp/old.mov"), timeRange: .init(start: 0, duration: 1))
        let active = FinalizedCaptureSegment(url: URL(fileURLWithPath: "/tmp/active.mov"), timeRange: .init(start: 14, duration: 1))
        _ = ledger.append(old)
        _ = ledger.append(active)

        let protected = ledger.protectedSegments(for: ImpactClipWindow(impactTime: 14.5))
        XCTAssertEqual(protected.map(\.id), [active.id])
        XCTAssertEqual(ledger.evictableSegments(at: 24, protectedIDs: [active.id]).map(\.id), [old.id])
    }

    func testVisionCoordinatesInvertYForVideoOverlay() {
        let point = VisionVideoCoordinateMapper.swiftUIPoint(
            from: NormalizedPoint(x: 0.25, y: 0.75),
            in: CGSize(width: 200, height: 100)
        )

        XCTAssertEqual(point.x, 50, accuracy: 0.0001)
        XCTAssertEqual(point.y, 25, accuracy: 0.0001)
    }

    func testVideoAspectRatioHonoursPreferredOrientation() {
        let portrait = VideoAssetMetadata(
            duration: 6,
            naturalWidth: 3_840,
            naturalHeight: 2_160,
            nominalFrameRate: 30,
            isExportable: true,
            isReadable: true,
            preferredTransform: [0, 1, -1, 0, 0, 0]
        )

        XCTAssertEqual(portrait.displayAspectRatio ?? 0, 9.0 / 16.0, accuracy: 0.0001)
    }

    func testDefaultTracerRunsFromGroundThroughApexToLanding() {
        let path = AssistedTracerPath.default

        XCTAssertGreaterThan(path.launch.y, path.apex.y)
        XCTAssertGreaterThan(path.landing.y, path.apex.y)
        XCTAssertLessThan(path.launch.x, path.landing.x)
    }

    func testTracerRevealUsesPlayerItemTimeAndResetsOnSeek() {
        let timeline = TracerRevealTimeline(impactTime: 4, flightDuration: 1.25)

        XCTAssertEqual(timeline.progress(at: 3.99), 0, accuracy: 0.0001)
        XCTAssertEqual(timeline.progress(at: 4), 0, accuracy: 0.0001)
        XCTAssertEqual(timeline.progress(at: 4.625), 0.5, accuracy: 0.0001)
        XCTAssertEqual(timeline.progress(at: 5.25), 1, accuracy: 0.0001)
        XCTAssertEqual(timeline.progress(at: 3.5), 0, accuracy: 0.0001)
    }

    func testReducedMotionShowsCompletedTracerOnlyAfterImpact() {
        let timeline = TracerRevealTimeline(impactTime: 4, flightDuration: 1.25)

        XCTAssertEqual(timeline.progress(at: 3.99, reducesMotion: true), 0, accuracy: 0.0001)
        XCTAssertEqual(timeline.progress(at: 4, reducesMotion: true), 1, accuracy: 0.0001)
    }

    func testLongSessionAcceptsExactlyThreeVerifiedTargetGolferShots() async {
        let service = LongSessionAnalysisService()
        let proposals = [
            ShotEventProposal(sourceTime: 12, signals: [.targetBodyMotion], confidence: 0.85), // practice swing
            ShotEventProposal(sourceTime: 34, signals: [.impactLikeAudio], confidence: 0.90), // range noise
            ShotEventProposal(sourceTime: 61, signals: [.impactLikeAudio, .targetBodyMotion], confidence: 0.92),
            ShotEventProposal(sourceTime: 61.12, signals: [.targetBodyMotion], confidence: 0.76), // duplicate burst
            ShotEventProposal(sourceTime: 118, signals: [.targetBodyMotion], confidence: 0.91), // another golfer
            ShotEventProposal(sourceTime: 177, signals: [.impactLikeAudio, .targetBodyMotion], confidence: 0.94),
            ShotEventProposal(sourceTime: 296, signals: [.impactLikeAudio, .targetBodyMotion], confidence: 0.93)
        ]

        let result = await service.classify(proposals: proposals, sourceDuration: 300) { proposal in
            switch proposal.sourceTime {
            case 61...62, 177...178, 296...297:
                return Self.verifiedTargetShotEvidence(at: proposal.sourceTime)
            case 118...119:
                return RealShotEvidence(
                    targetGolferSwing: .init(
                        state: .differentGolfer,
                        impactTime: proposal.sourceTime,
                        confidence: 0.93,
                        sourceDescription: "Person association selected a neighbouring golfer."
                    ),
                    ballLaunch: .init(
                        state: .verifiedGolfBall,
                        launchTime: proposal.sourceTime + 0.04,
                        confidence: 0.96,
                        stableDetectionCount: 4,
                        belongsToTargetGolfer: false,
                        detectorDescription: "Fixture detector"
                    )
                )
            default:
                return RealShotEvidence(
                    targetGolferSwing: .init(
                        state: .unavailable,
                        impactTime: proposal.sourceTime,
                        confidence: 0.6,
                        sourceDescription: "Unidentified body movement."
                    ),
                    ballLaunch: .init(
                        state: .noLaunchObserved,
                        detectorDescription: "Fixture detector"
                    )
                )
            }
        }

        XCTAssertEqual(result.acceptedShots.count, 3)
        XCTAssertEqual(result.uncertainMoments.count, 2)
        XCTAssertEqual(result.rejectedEvents.count, 1)
        XCTAssertTrue(result.acceptedShots.allSatisfy { $0.tracerEligibility == .eligible })
        XCTAssertEqual(result.acceptedShots.map(\.clipPlan.sourceRange), [
            .init(start: 56, duration: 10),
            .init(start: 172, duration: 10),
            .init(start: 291, duration: 9)
        ])
    }

    func testLongSessionDoesNotEnableTracerForUncertainOrRejectedEvents() async {
        let service = LongSessionAnalysisService()
        let result = await service.classify(
            proposals: [
                .init(sourceTime: 10, signals: [.impactLikeAudio, .targetBodyMotion], confidence: 0.9),
                .init(sourceTime: 28, signals: [.genericMotion], confidence: 0.8)
            ],
            sourceDuration: 60
        ) { proposal in
            if proposal.sourceTime == 10 {
                return RealShotEvidence(
                    targetGolferSwing: .init(
                        state: .supported,
                        impactTime: 10,
                        confidence: 0.92,
                        sourceDescription: "Fixture target golfer"
                    ),
                    ballLaunch: .init(
                        state: .modelUnavailable,
                        detectorDescription: "No model installed"
                    )
                )
            }
            return RealShotEvidence(
                targetGolferSwing: .init(
                    state: .supported,
                    impactTime: 28,
                    confidence: 0.92,
                    sourceDescription: "Fixture target golfer"
                ),
                ballLaunch: .init(
                    state: .genericMotion,
                    launchTime: 28.02,
                    confidence: 0.99,
                    stableDetectionCount: 6,
                    belongsToTargetGolfer: true,
                    detectorDescription: "Generic Vision"
                )
            )
        }

        XCTAssertTrue(result.acceptedShots.isEmpty)
        XCTAssertEqual(result.uncertainMoments.map(\.tracerEligibility), [.ineligibleModelUnavailable])
        XCTAssertEqual(result.rejectedEvents.count, 1)
    }

    func testDeduplicatorCombinesNearbyProposalSignalsWithoutCreatingAShot() {
        let result = ShotEventProposalDeduplicator().deduplicate([
            .init(sourceTime: 45.00, signals: [.impactLikeAudio], confidence: 0.72),
            .init(sourceTime: 45.14, signals: [.targetBodyMotion], confidence: 0.88),
            .init(sourceTime: 50.00, signals: [.impactLikeAudio], confidence: 0.90)
        ])

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].signals, [.impactLikeAudio, .targetBodyMotion])
        XCTAssertEqual(result[0].sourceTime, 45.14, accuracy: 0.0001)
    }

    func testAcceptedShotUsesValidatedTargetImpactInsteadOfProposalTimestamp() async {
        let service = LongSessionAnalysisService()
        let result = await service.classify(
            proposals: [.init(sourceTime: 100.00, signals: [.impactLikeAudio], confidence: 0.9)],
            sourceDuration: 180
        ) { _ in
            RealShotEvidence(
                targetGolferSwing: .init(
                    state: .supported,
                    impactTime: 100.18,
                    confidence: 0.95,
                    sourceDescription: "Fixture association refined the audio proposal."
                ),
                ballLaunch: .init(
                    state: .verifiedGolfBall,
                    launchTime: 100.22,
                    confidence: 0.96,
                    stableDetectionCount: 4,
                    belongsToTargetGolfer: true,
                    detectorDescription: "Fixture detector"
                )
            )
        }

        let shot = try! XCTUnwrap(result.acceptedShots.first)
        XCTAssertEqual(shot.proposal.sourceTime, 100.00, accuracy: 0.0001)
        XCTAssertEqual(shot.impactTime, 100.18, accuracy: 0.0001)
        XCTAssertEqual(shot.clipPlan.impactTime, 100.18, accuracy: 0.0001)
        XCTAssertEqual(shot.clipPlan.sourceRange.start, 95.18, accuracy: 0.0001)
        XCTAssertEqual(shot.clipPlan.sourceRange.duration, 10, accuracy: 0.0001)
    }

    func testVerifiedBallExplicitlyAssociatedWithAnotherGolferIsRejected() async {
        let service = LongSessionAnalysisService()
        let result = await service.classify(
            proposals: [.init(sourceTime: 72, signals: [.impactLikeAudio, .targetBodyMotion], confidence: 0.91)],
            sourceDuration: 120
        ) { _ in
            RealShotEvidence(
                targetGolferSwing: .init(
                    state: .supported,
                    impactTime: 72,
                    confidence: 0.93,
                    sourceDescription: "Fixture target golfer"
                ),
                ballLaunch: .init(
                    state: .verifiedGolfBall,
                    launchTime: 72.03,
                    confidence: 0.96,
                    stableDetectionCount: 5,
                    targetGolferAssociation: .differentGolfer,
                    detectorDescription: "Fixture detector associated the ball with another golfer."
                )
            )
        }

        XCTAssertTrue(result.acceptedShots.isEmpty)
        XCTAssertTrue(result.uncertainMoments.isEmpty)
        XCTAssertEqual(result.rejectedEvents.count, 1)
        XCTAssertTrue(result.rejectedEvents[0].decision.explanation.contains("different golfer"))
    }

    func testVerifiedBallWithUnavailableAssociationRemainsRecoverableUncertain() async {
        let service = LongSessionAnalysisService()
        let result = await service.classify(
            proposals: [.init(sourceTime: 72, signals: [.impactLikeAudio, .targetBodyMotion], confidence: 0.91)],
            sourceDuration: 120
        ) { _ in
            RealShotEvidence(
                targetGolferSwing: .init(
                    state: .supported,
                    impactTime: 72,
                    confidence: 0.93,
                    sourceDescription: "Fixture target golfer"
                ),
                ballLaunch: .init(
                    state: .verifiedGolfBall,
                    launchTime: 72.03,
                    confidence: 0.96,
                    stableDetectionCount: 5,
                    targetGolferAssociation: .unavailable,
                    detectorDescription: "Fixture detector could not associate the ball with a golfer."
                )
            )
        }

        XCTAssertTrue(result.acceptedShots.isEmpty)
        XCTAssertEqual(result.uncertainMoments.count, 1)
        XCTAssertEqual(result.uncertainMoments[0].tracerEligibility, .ineligibleUncertainEvidence)
        XCTAssertTrue(result.rejectedEvents.isEmpty)
    }

    private static func verifiedTargetShotEvidence(at time: TimeInterval) -> RealShotEvidence {
        RealShotEvidence(
            targetGolferSwing: .init(
                state: .supported,
                impactTime: time,
                confidence: 0.94,
                sourceDescription: "Fixture target-golfer swing model"
            ),
            ballLaunch: .init(
                state: .verifiedGolfBall,
                launchTime: time + 0.04,
                confidence: 0.96,
                stableDetectionCount: 4,
                belongsToTargetGolfer: true,
                detectorDescription: "Fixture golf-ball detector"
            )
        )
    }

    private static func recording(duration: TimeInterval) -> ReviewSession {
        ReviewSession(
            id: UUID(),
            mode: .range,
            importKind: .recording,
            title: "Practice session",
            sourceName: "practice.mov",
            sourceURL: nil,
            createdAt: .now,
            duration: duration,
            status: .reviewing,
            progress: 1,
            candidates: [],
            groupID: nil,
            groupTitle: nil,
            sourceRecordingID: nil,
            sourceBookmarkID: nil,
            sourceClipRange: nil,
            storedBookmarks: nil
        )
    }
}
