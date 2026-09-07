import Foundation
import Testing
@testable import Ronde

private final class GolfBallTrackerTestBundleMarker: NSObject {}

struct GolfBallTrackSelectorTests {
    @Test func launchAnchorDetectorFindsTheUniqueDepartingBall() throws {
        let width = 120
        let height = 100
        var before = [Float](repeating: 34, count: width * height)
        let after = [Float](repeating: 34, count: width * height)
        for y in 77...83 {
            for x in 59...65 {
                before[(y * width) + x] = 225
            }
        }
        let initial = GolfBallLaunchLuminancePlane(
            sourceWidth: width,
            sourceHeight: height,
            width: width,
            height: height,
            values: before
        )
        let departed = GolfBallLaunchLuminancePlane(
            sourceWidth: width,
            sourceHeight: height,
            width: width,
            height: height,
            values: after
        )

        let detection = try #require(GolfBallLaunchAnchorDetector().detect(
            before: initial,
            after: departed,
            firstObservedPoint: NormalizedPoint(x: 0.53, y: 0.27)
        ))

        #expect(abs(detection.point.x - (62.0 / 120.0)) < 0.015)
        #expect(abs(detection.point.y - 0.80) < 0.015)
        #expect(detection.confidence >= 0.55)
    }

    @Test func launchAnchorDetectorRejectsAmbiguousDepartingObjects() {
        let width = 160
        let height = 120
        var before = [Float](repeating: 30, count: width * height)
        let after = [Float](repeating: 30, count: width * height)
        for centre in [(x: 75, y: 92), (x: 95, y: 92)] {
            for y in (centre.y - 3)...(centre.y + 3) {
                for x in (centre.x - 3)...(centre.x + 3) {
                    before[(y * width) + x] = 220
                }
            }
        }
        let initial = GolfBallLaunchLuminancePlane(
            sourceWidth: width,
            sourceHeight: height,
            width: width,
            height: height,
            values: before
        )
        let departed = GolfBallLaunchLuminancePlane(
            sourceWidth: width,
            sourceHeight: height,
            width: width,
            height: height,
            values: after
        )

        #expect(GolfBallLaunchAnchorDetector().detect(
            before: initial,
            after: departed,
            firstObservedPoint: NormalizedPoint(x: 0.53, y: 0.28)
        ) == nil)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["RONDE_RUN_EXTERNAL_VIDEO_MATRIX"] == "1"))
    func optionalExternalVideoMatrixTracksTheLabelledBall() async throws {
        let specs: [(resource: String, impact: TimeInterval, launchX: ClosedRange<Double>, launchY: ClosedRange<Double>, previousPointCount: Int)] = [
            ("RondeExternalLandscapeA", 1.6320, 0.50...0.56, 0.20...0.30, 7),
            ("RondeExternalLandscapeB", 0.8747, 0.70...0.79, 0.17...0.28, 86),
            ("RondeExternalPortraitC", 1.6747, 0.54...0.60, 0.32...0.38, 82)
        ]
        let bundle = Bundle(for: GolfBallTrackerTestBundleMarker.self)

        for spec in specs {
            let videoURL = try #require(
                bundle.url(forResource: spec.resource, withExtension: "mov"),
                "The opted-in external matrix requires every named private fixture."
            )
            let estimate = try await WASBGolfBallTrackingService().analyse(
                url: videoURL,
                impactTime: spec.impact
            )
            let points = estimate.observedTrajectory?.detectedPoints ?? []
            print("EXTERNAL_PROBE \(spec.resource) confidence=\(estimate.confidence) points=\(points)")
            #expect(estimate.isDisplayable)
            #expect(points.count >= spec.previousPointCount)
            #expect(spec.launchX.contains(estimate.launch.x))
            #expect(spec.launchY.contains(estimate.launch.y))
            #expect((points.map(\.y).min() ?? 1) < estimate.launch.y - 0.01)
        }
    }

    @Test(.enabled(if:
        ProcessInfo.processInfo.environment["RONDE_TEST_VIDEO_PATH"]?.isEmpty == false
            || Bundle(for: GolfBallTrackerTestBundleMarker.self).url(forResource: "RondeRealVideoProbe", withExtension: "mov") != nil
    ))
    func optionalRealClipProducesTheObservedBallTrack() async throws {
        let environmentURL = ProcessInfo.processInfo.environment["RONDE_TEST_VIDEO_PATH"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        let bundledURL = Bundle(for: GolfBallTrackerTestBundleMarker.self)
            .url(forResource: "RondeRealVideoProbe", withExtension: "mov")
        guard let videoURL = environmentURL ?? bundledURL else { return }

        let estimate = try await WASBGolfBallTrackingService().analyse(
            url: videoURL,
            impactTime: 1.675,
            configuration: WASBGolfBallTrackingConfiguration(
                maximumPostImpactDuration: 0.88,
                minimumPeakConfidence: 0.08,
                maximumCandidatesPerFrame: 8,
                diagnosticTileOrigins: [
                    NormalizedPoint(x: 896.0 / 2_160.0, y: 896.0 / 3_840.0),
                    NormalizedPoint(x: 896.0 / 2_160.0, y: 1_120.0 / 3_840.0)
                ]
            )
        )

        #expect(estimate.source == .observed)
        #expect(estimate.observedPointCount >= 12)
        #expect(estimate.launch.x > 0.52 && estimate.launch.x < 0.59)
        #expect(estimate.launch.y > 0.32 && estimate.launch.y < 0.38)
        #expect(estimate.landing.y < estimate.launch.y)
        #expect(estimate.isDisplayable)
    }

    @Test func motionConsistentPostImpactBallWinsOverStaticAndErraticPeaks() {
        let impactTime = 1.675
        let trackedPixels: [(Double, Double)] = [
            (1_215, 1_348), (1_209, 1_304), (1_203, 1_272), (1_197, 1_248),
            (1_193, 1_228), (1_189, 1_208), (1_185, 1_192), (1_183, 1_178),
            (1_179, 1_164), (1_175, 1_150), (1_173, 1_142), (1_169, 1_130),
            (1_165, 1_122), (1_163, 1_116), (1_161, 1_107), (1_157, 1_101)
        ]
        var candidates = trackedPixels.enumerated().map { index, pixel in
            GolfBallDetectionCandidate(
                frameIndex: index,
                presentationTime: 1.995 + (Double(index) / 30),
                point: NormalizedPoint(x: pixel.0 / 2_160, y: pixel.1 / 3_840),
                confidence: 0.42 + (Double(index % 4) * 0.05)
            )
        }
        for index in trackedPixels.indices {
            candidates.append(GolfBallDetectionCandidate(
                frameIndex: index,
                presentationTime: 1.995 + (Double(index) / 30),
                point: NormalizedPoint(x: 0.31, y: 0.49),
                confidence: 0.92
            ))
            candidates.append(GolfBallDetectionCandidate(
                frameIndex: index,
                presentationTime: 1.995 + (Double(index) / 30),
                point: NormalizedPoint(
                    x: 0.18 + (Double(index % 3) * 0.035),
                    y: 0.28 + (Double(index % 2) * 0.04)
                ),
                confidence: 0.75
            ))
        }

        let selected = GolfBallTrackSelector.select(from: candidates, impactTime: impactTime)

        #expect(selected?.detections.count == trackedPixels.count)
        #expect(selected?.detections.first?.point.x == trackedPixels[0].0 / 2_160)
        #expect(selected?.detections.last?.point.y == trackedPixels.last!.1 / 3_840)
        #expect((selected?.confidence ?? 0) > 0.4)
    }

    @Test func abruptGolferMotionCannotBeMergedIntoTheBallTrack() {
        let points: [NormalizedPoint] = [
            NormalizedPoint(x: 0.502315, y: 0.492188),
            NormalizedPoint(x: 0.529630, y: 0.414323),
            NormalizedPoint(x: 0.562500, y: 0.351042),
            NormalizedPoint(x: 0.556944, y: 0.331250),
            NormalizedPoint(x: 0.552315, y: 0.319792),
            NormalizedPoint(x: 0.548611, y: 0.310417),
            NormalizedPoint(x: 0.545833, y: 0.303125),
            NormalizedPoint(x: 0.543056, y: 0.297396)
        ]
        let candidates = points.enumerated().map { index, point in
            GolfBallDetectionCandidate(
                frameIndex: index,
                presentationTime: 1.985 + (Double(index) / 15),
                point: point,
                confidence: 0.7
            )
        }

        let selected = GolfBallTrackSelector.select(
            from: candidates,
            impactTime: 1.675,
            minimumDetectionCount: 5
        )
        let trimmed = GolfBallTrackSelector.trimmingLeadingDetectorHandoff(from: candidates)

        #expect(trimmed.first?.point == points[2])
        #expect(trimmed.count == points.count - 2)
        #expect(selected?.detections.first?.point == points[2])
        #expect(selected?.detections.count == points.count - 2)
    }

    @Test func longerBallTrackWinsOverAnEarlierHighConfidenceMovingSpeck() {
        let impactTime = 1.632
        var candidates = (0..<6).map { index in
            GolfBallDetectionCandidate(
                frameIndex: index,
                presentationTime: 1.70 + (Double(index) / 15),
                point: NormalizedPoint(
                    x: 0.04 + (Double(index) * 0.038),
                    y: 0.314 - (Double(index) * 0.029)
                ),
                confidence: 0.9
            )
        }
        candidates.append(contentsOf: (0..<10).map { index in
            GolfBallDetectionCandidate(
                frameIndex: index + 3,
                presentationTime: 1.90 + (Double(index) / 15),
                point: NormalizedPoint(
                    x: 0.532 - (Double(index) * 0.0013),
                    y: 0.273 - (Double(index) * 0.015)
                ),
                confidence: 0.46
            )
        })

        let selected = GolfBallTrackSelector.select(
            from: candidates,
            impactTime: impactTime,
            minimumDetectionCount: 8
        )

        #expect(selected?.detections.count == 10)
        #expect(abs((selected?.detections.first?.point.x ?? 0) - 0.532) < 0.001)
    }

    @Test func fivePointMovingSpeckCannotCommitCompetitiveAcquisition() {
        let impactTime = 1.632
        var gate = CompetitiveTrackAcquisitionGate(impactTime: impactTime)
        let firstFive = (0..<5).map { index in
            GolfBallDetectionCandidate(
                frameIndex: index,
                presentationTime: 1.70 + (Double(index) / 15),
                point: NormalizedPoint(
                    x: 0.04 + (Double(index) * 0.038),
                    y: 0.314 - (Double(index) * 0.029)
                ),
                confidence: 0.9
            )
        }

        #expect(gate.record(firstFive, at: impactTime + 0.7) == nil)
        #expect(!gate.hasCommittedTrack)

        let finalThree = (5..<8).map { index in
            GolfBallDetectionCandidate(
                frameIndex: index,
                presentationTime: 1.70 + (Double(index) / 15),
                point: NormalizedPoint(
                    x: 0.04 + (Double(index) * 0.038),
                    y: 0.314 - (Double(index) * 0.029)
                ),
                confidence: 0.9
            )
        }
        #expect(gate.record(finalThree, at: impactTime + 0.9) != nil)
        #expect(gate.hasCommittedTrack)
    }

    @Test func shortOrStaticDetectionsCannotCreateATracer() {
        let staticCandidates = (0..<12).map { index in
            GolfBallDetectionCandidate(
                frameIndex: index,
                presentationTime: 2 + (Double(index) / 30),
                point: NormalizedPoint(x: 0.5, y: 0.5),
                confidence: 0.99
            )
        }
        let shortMovingCandidates = (0..<5).map { index in
            GolfBallDetectionCandidate(
                frameIndex: index,
                presentationTime: 2 + (Double(index) / 30),
                point: NormalizedPoint(x: 0.6, y: 0.5 - (Double(index) * 0.01)),
                confidence: 0.99
            )
        }

        #expect(GolfBallTrackSelector.select(
            from: staticCandidates + shortMovingCandidates,
            impactTime: 1.7
        ) == nil)
    }

    @Test func presentationTimestampSamplingAndSelectionAreInvariantAcrossCommonSourceRates() {
        let impactTime = 1.675
        let rates = [25.0, 30.0, 50.0, 60.0, 120.0, 240.0]

        for sourceRate in rates {
            let startTime = impactTime + 0.06
            var sampler = PresentationTimestampFrameSampler(
                startTime: startTime,
                cadence: 1.0 / 30.0
            )
            var candidates: [GolfBallDetectionCandidate] = []
            let sourceFrameCount = Int((sourceRate * 0.72).rounded(.up))

            for sourceFrame in 0...sourceFrameCount {
                let presentationTime = startTime + (Double(sourceFrame) / sourceRate)
                guard sampler.accepts(presentationTime: presentationTime) else { continue }
                let progress = min(1, (presentationTime - startTime) / 0.72)
                candidates.append(GolfBallDetectionCandidate(
                    // Deliberately discontinuous: the selector must use PTS, not this value.
                    frameIndex: sourceFrame * 17,
                    presentationTime: presentationTime,
                    point: NormalizedPoint(
                        x: 0.58 - (progress * 0.045),
                        y: 0.48 - (progress * 0.16)
                    ),
                    confidence: 0.68
                ))
            }

            let intervals = zip(candidates, candidates.dropFirst()).map {
                $1.presentationTime - $0.presentationTime
            }
            #expect(candidates.count >= 15, "\(sourceRate) fps should still provide enough samples")
            #expect(intervals.allSatisfy { $0 > 0 && $0 <= (1.0 / 30.0) + (1.0 / sourceRate) + 0.000_01 })
            #expect(candidates.count <= Int(0.72 * 31) + 2)

            let selected = GolfBallTrackSelector.select(from: candidates, impactTime: impactTime)
            #expect(selected != nil, "\(sourceRate) fps should select the same physical motion")
            #expect(abs((selected?.detections.first?.point.x ?? 0) - 0.58) < 0.001)
            #expect((selected?.detections.last?.point.y ?? 1) < 0.34)
        }
    }

    @Test func measuredThirtyFrameFootageDoesNotCollapseToHalfRate() {
        let measuredSourceRate = 30.087
        let startTime = 1.714
        var sampler = PresentationTimestampFrameSampler(
            startTime: startTime,
            cadence: 1.0 / 30.0
        )
        let presentationTimes = (0..<31).map {
            startTime + (Double($0) / measuredSourceRate)
        }
        let acceptedTimes = presentationTimes.filter {
            sampler.accepts(presentationTime: $0)
        }

        #expect(acceptedTimes.count == presentationTimes.count)
        #expect(zip(acceptedTimes, acceptedTimes.dropFirst()).allSatisfy {
            $1 - $0 < 0.034
        })
    }

    @Test func contiguousFrameNumbersCannotBridgeALargePresentationTimeGap() {
        let firstSegment = (0..<6).map { index in
            GolfBallDetectionCandidate(
                frameIndex: index,
                presentationTime: 2 + (Double(index) / 30),
                point: NormalizedPoint(x: 0.6, y: 0.48 - (Double(index) * 0.012)),
                confidence: 0.74
            )
        }
        let delayedSegment = (6..<12).map { index in
            GolfBallDetectionCandidate(
                frameIndex: index,
                presentationTime: 2.45 + (Double(index - 6) / 30),
                point: NormalizedPoint(x: 0.54, y: 0.37 - (Double(index - 6) * 0.012)),
                confidence: 0.74
            )
        }

        let selected = GolfBallTrackSelector.select(
            from: firstSegment + delayedSegment,
            impactTime: 1.7
        )

        #expect(selected?.detections.count == firstSegment.count)
        #expect(selected?.detections.last?.presentationTime ?? 0 < 2.25)
    }

    @Test func linkedContinuationStopsAfterTimestampBoundedMisses() {
        var gate = TrackingContinuationGate()
        let observations = (0..<3).map { index in
            GolfBallDetectionCandidate(
                frameIndex: index,
                presentationTime: 2 + (Double(index) / 30),
                point: NormalizedPoint(
                    x: 0.58 - (Double(index) * 0.008),
                    y: 0.48 - (Double(index) * 0.014)
                ),
                confidence: 0.72
            )
        }

        for observation in observations {
            let accepted = gate.acceptBest(from: [observation], at: observation.presentationTime)
            #expect(accepted == observation)
        }

        #expect(gate.isAcquired)
        #expect(!gate.shouldStopAfterMisses(at: 2.45))
        #expect(gate.shouldStopAfterMisses(at: 2.47))
        #expect(!gate.shouldAbandonInitialSearch(startedAt: 2, at: 2.9))

        let emptyGate = TrackingContinuationGate()
        #expect(!emptyGate.shouldAbandonInitialSearch(startedAt: 2, at: 2.89))
        #expect(emptyGate.shouldAbandonInitialSearch(startedAt: 2, at: 2.9))
    }
}

extension GolfBallTrackSelectorTests {
    private static func detection(_ index: Int, time: Double, x: Double = 0.5, y: Double, confidence: Double = 0.8) -> GolfBallDetectionCandidate {
        GolfBallDetectionCandidate(frameIndex: index, presentationTime: time, point: NormalizedPoint(x: x, y: y), confidence: confidence)
    }

    @Test func finalisationRetainsTheCommittedIdentityInsteadOfAShorterChallenger() throws {
        let established = (0..<8).map {
            Self.detection($0, time: 0.1 + Double($0) / 15, x: 0.2, y: 0.6 - Double($0) * 0.003, confidence: 0.08)
        }
        let challenger = (0..<6).map {
            Self.detection($0 + 3, time: 0.3 + Double($0) / 15, x: 0.8, y: 0.85 - Double($0) * 0.09, confidence: 0.99)
        }
        var acquisition = CompetitiveTrackAcquisitionGate(impactTime: 0)
        let acquisitionResult = acquisition.record(established + challenger, at: 0.667)
        let committed = try #require(acquisitionResult)
        #expect(committed.detections == established)
        // This is the formerly displayed challenger; it still does not have eight observations.
        #expect(GolfBallTrackSelector.select(from: established + challenger, impactTime: 0)?.detections == challenger)
        #expect(GolfBallTrackSelector.finalise(committedTrack: committed, linkedDetections: challenger, impactTime: 0) == nil)
        #expect(GolfBallTrackSelector.finalise(committedTrack: committed, linkedDetections: established, impactTime: 0)?.detections == established)
    }

    @Test func trimmingCannotLeaveASubthresholdObservedDuration() {
        let raw: [(Double, Double)] = [
            (0.502315, 0.492188), (0.529630, 0.414323), (0.562500, 0.351042),
            (0.556944, 0.331250), (0.552315, 0.319792), (0.548611, 0.310417),
            (0.545833, 0.303125)
        ]
        let candidates = raw.enumerated().map { index, point in
            Self.detection(index, time: 0.1 + Double(index) / 30, x: point.0 * 0.5, y: point.1 * 0.5)
        }
        let trimmed = GolfBallTrackSelector.trimmingLeadingDetectorHandoff(from: candidates)
        #expect(trimmed.count == 5)
        #expect(GolfBallTrackSelector.select(from: candidates, impactTime: 0) == nil)
    }

    @Test func sourceTimeAcquisitionCanCommitPerfectEvidenceAcrossFrameRatesAndJitter() {
        for rate in [15.0, 20, 24, 25, 29.97, 30.087, 31, 32, 40, 50, 59.94, 60, 120, 240] {
            for jitter in [0.0, 0.0015] {
                let impact = 1.0
                let start = impact + 0.04 - 2.0 / 30.0
                var decoderSampler = PresentationTimestampFrameSampler(startTime: start, cadence: 1.0 / 30.0)
                var acquisitionSampler = PresentationTimestampFrameSampler(startTime: start, cadence: 1.0 / 15.0)
                var acquisition = CompetitiveTrackAcquisitionGate(impactTime: impact)
                var samples = 0
                for frame in 0...Int(rate * 2) {
                    let time = Double(frame) / rate + (frame.isMultiple(of: 2) ? jitter : 0)
                    guard time >= start, decoderSampler.accepts(presentationTime: time) else { continue }
                    samples += 1
                    if samples >= 3, acquisitionSampler.accepts(presentationTime: time) {
                        _ = acquisition.record([Self.detection(frame, time: time, y: 0.8 - 0.3 * (time - impact))], at: time)
                    }
                    if acquisition.hasCommittedTrack || (samples >= 3 && time - start >= 0.9) { break }
                }
                #expect(acquisition.hasCommittedTrack, "Correct evidence should remain eligible at \(rate) fps with \(jitter) s jitter")
            }
        }
    }

    @Test func samplerRejectsInvalidDuplicateAndReversedTimestamps() {
        var sampler = PresentationTimestampFrameSampler(startTime: 1, cadence: 1.0 / 30.0)
        let times: [Double] = [.nan, .infinity, -1, 1, 1, 0.9, 1.04]
        let results = times.map { sampler.accepts(presentationTime: $0) }
        #expect(results == [false, false, false, true, false, false, true])
    }

    @Test func lostTrackRequiresThreeUniqueReturningObservations() {
        var gate = TrackingContinuationGate()
        let seed = (0..<3).map { Self.detection($0, time: Double($0) / 30, y: 0.7 - Double($0) * 0.01) }
        gate.seed(with: seed)
        #expect(gate.needsReacquisition(at: 0.2))
        for index in 0..<3 {
            let time = 0.2 + Double(index) / 30
            let candidate = Self.detection(index + 6, time: time, y: 0.7 - time * 0.3)
            let result = gate.acceptBest(from: [candidate], at: time)
            #expect((result != nil) == (index == 2))
            if index < 2 { #expect(gate.linkedDetections == seed) }
        }
        #expect(gate.linkedDetections.count == 6)
        #expect(gate.linkedDetections.map(\.presentationTime) == seed.map(\.presentationTime) + [0.2, 0.2 + 1.0 / 30, 0.2 + 2.0 / 30])
        #expect(!gate.needsReacquisition(at: 0.3))
    }

    @Test func ambiguousOrDistantReacquisitionDoesNotInheritTheTrack() {
        var gate = TrackingContinuationGate()
        let seed = (0..<3).map { Self.detection($0, time: Double($0) / 30, y: 0.7 - Double($0) * 0.01) }
        gate.seed(with: seed)
        for index in 0..<3 {
            let time = 0.2 + Double(index) / 30
            let expectedY = 0.7 - time * 0.3
            let choices = [
                Self.detection(index + 6, time: time, y: expectedY),
                Self.detection(index + 6, time: time, x: 0.501, y: expectedY, confidence: 0.99)
            ]
            #expect(gate.acceptBest(from: choices, at: time) == nil)
        }
        #expect(gate.acceptBest(from: [Self.detection(10, time: 0.3, x: 0.8, y: 0.61)], at: 0.3) == nil)
        #expect(gate.linkedDetections == seed)
        #expect(gate.shouldStopAfterMisses(at: 0.47))
    }

    @Test func supportedApexRetainsTheVisibleDescent() throws {
        let arc = (0..<31).map { index in
            let time = 0.1 + Double(index) / 30
            return Self.detection(index, time: time, y: 0.25 + 0.6 * pow(time - 0.6, 2))
        }
        let selected = try #require(GolfBallTrackSelector.select(from: arc, impactTime: 0))
        #expect(selected.detections == arc)
        var continuation = TrackingContinuationGate()
        continuation.seed(with: Array(arc.prefix(8)))
        for candidate in arc.dropFirst(8) {
            #expect(continuation.acceptBest(from: [candidate], at: candidate.presentationTime) == candidate)
        }
        #expect(continuation.linkedDetections == arc)
    }

    @Test func stationaryPeaksAndAnUnpredictedReversalRemainIneligible() {
        let stationary = (0..<12).map { Self.detection($0, time: 0.1 + Double($0) / 30, y: 0.5) }
        #expect(GolfBallTrackSelector.select(from: stationary, impactTime: 0) == nil)
        let history = (0..<8).map { Self.detection($0, time: 0.1 + Double($0) / 30, y: 0.7 - Double($0) * 0.01) }
        let reversed = Self.detection(8, time: 0.1 + 8.0 / 30, y: 0.64)
        #expect(GolfBallTrackMotion.linkPenalty(history: history, candidate: reversed) == nil)
    }
}
