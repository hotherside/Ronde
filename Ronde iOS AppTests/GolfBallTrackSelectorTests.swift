import Foundation
import Testing
@testable import Ronde

private final class GolfBallTrackerTestBundleMarker: NSObject {}

struct GolfBallTrackSelectorTests {
    @Test func optionalRealClipProducesTheObservedBallTrack() async throws {
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
}
