import Foundation
import XCTest
@testable import Ronde

final class AudioImpactPeakSelectorTests: XCTestCase {
    private let selector = AudioImpactPeakSelector()
    private let configuration = ImpactAudioAnalysisConfiguration(
        analysisWindowSamples: 512,
        minimumPeakAmplitude: 0.05,
        clusterSeparation: 0.16,
        refractoryPeriod: 4,
        minimumSignalToNoiseRatio: 1
    )

    func testMergesAdjacentBurstToStrongestImpactPeak() {
        let results = selector.mergeClusters([
            .init(time: 1.00, strength: 0.24),
            .init(time: 1.05, strength: 0.82),
            .init(time: 1.13, strength: 0.41)
        ], separation: configuration.clusterSeparation)

        XCTAssertEqual(results, [.init(time: 1.05, strength: 0.82)])
    }

    func testRefractoryPeriodKeepsStrongestNearbySound() {
        let results = selector.enforceRefractoryPeriod([
            .init(time: 1.0, strength: 0.65),
            .init(time: 3.2, strength: 0.92)
        ], period: configuration.refractoryPeriod)

        XCTAssertEqual(results, [.init(time: 3.2, strength: 0.92)])
    }

    func testSilenceDoesNotCreateAnImpactCandidate() {
        let results = selector.select(from: [
            .init(time: 0.5, strength: 0.004),
            .init(time: 1.0, strength: 0.008),
            .init(time: 1.5, strength: 0.006)
        ], configuration: configuration)

        XCTAssertTrue(results.isEmpty)
    }

    func testSeparatedStrongPeaksCreateSeparateCandidates() {
        let results = selector.enforceRefractoryPeriod([
            .init(time: 1.0, strength: 0.72),
            .init(time: 5.3, strength: 0.68),
            .init(time: 9.7, strength: 0.83)
        ], period: configuration.refractoryPeriod)

        XCTAssertEqual(results, [
            .init(time: 1.0, strength: 0.72),
            .init(time: 5.3, strength: 0.68),
            .init(time: 9.7, strength: 0.83)
        ])
    }

    func testBodyMotionAnalysisIsOnlyAFallbackWhenAudioHasNoUsableCandidate() {
        let audioCandidate = SwingCandidate(
            impactTime: 1.2,
            classification: .provisional(confidence: 0.8, explanation: "Audio fixture"),
            evidence: [.audioTransient]
        )

        XCTAssertFalse(
            ImpactCandidateAnalysisPolicy.shouldAnalyseBodyMotion(after: [audioCandidate])
        )
        XCTAssertTrue(
            ImpactCandidateAnalysisPolicy.shouldAnalyseBodyMotion(after: [])
        )
    }

    func testOptionalRealClipProducesOneCandidate() async throws {
        guard let path = ProcessInfo.processInfo.environment["RONDE_TEST_VIDEO_PATH"], !path.isEmpty else {
            throw XCTSkip("Set RONDE_TEST_VIDEO_PATH to run the local real-video probe.")
        }

        let candidates = try await ImpactCandidateAnalysisService().analyse(url: URL(fileURLWithPath: path))
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.evidence, [.audioTransient])
        XCTAssertEqual(candidates.first?.impactTime ?? 0, 1.717, accuracy: 2.0 / 30.0)
        XCTAssertNil(candidates.first?.trajectory)
    }
}
