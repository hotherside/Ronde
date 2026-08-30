import XCTest
@testable import Ronde

final class BodyMotionPeakSelectorTests: XCTestCase {
    private let selector = BodyMotionPeakSelector()
    private let configuration = BodyMotionAnalysisConfiguration(
        sampleInterval: 0.1,
        minimumJointConfidence: 0.25,
        minimumRecognisedJoints: 4,
        minimumMotion: 0.02,
        clusterSeparation: 0.45,
        refractoryPeriod: 4,
        minimumSignalToNoiseRatio: 1
    )

    func testMergesOneSwingBurstToItsStrongestMotionFrame() {
        let selected = selector.select(from: [
            .init(time: 1.1, strength: 0.05),
            .init(time: 1.3, strength: 0.18),
            .init(time: 1.6, strength: 0.08)
        ], configuration: configuration)

        XCTAssertEqual(selected, [.init(time: 1.3, strength: 0.18)])
    }

    func testCooldownPreventsMultipleCandidatesForTheSameSwing() {
        let selected = selector.select(from: [
            .init(time: 1.0, strength: 0.11),
            .init(time: 3.9, strength: 0.15)
        ], configuration: configuration)

        XCTAssertEqual(selected, [.init(time: 3.9, strength: 0.15)])
    }

    func testSmallPoseJitterDoesNotCreateAMarker() {
        let selected = selector.select(from: [
            .init(time: 0.2, strength: 0.003),
            .init(time: 0.4, strength: 0.006),
            .init(time: 0.6, strength: 0.005)
        ], configuration: configuration)

        XCTAssertTrue(selected.isEmpty)
    }

    func testSeparatedMotionBurstsCreateSeparateMarkers() {
        let selected = selector.enforceRefractoryPeriod([
            .init(time: 1.2, strength: 0.12),
            .init(time: 5.5, strength: 0.14),
            .init(time: 9.8, strength: 0.16)
        ], period: configuration.refractoryPeriod)

        XCTAssertEqual(selected, [
            .init(time: 1.2, strength: 0.12),
            .init(time: 5.5, strength: 0.14),
            .init(time: 9.8, strength: 0.16)
        ])
    }
}
