import CoreMotion
import Foundation

@MainActor
final class LiveReviewStabilityMonitor {
    var onChange: ((LiveReviewCaptureStability) -> Void)?

    private let motionManager = CMMotionManager()
    private let classifier = LiveReviewStabilityClassifier()
    private var recentSamples: [LiveReviewMotionSample] = []

    func start() {
        guard motionManager.isDeviceMotionAvailable else {
            onChange?(.unavailable)
            return
        }

        recentSamples.removeAll(keepingCapacity: true)
        onChange?(.checking)
        motionManager.deviceMotionUpdateInterval = 0.05
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            Task { @MainActor [weak self] in
                self?.ingest(motion)
            }
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        recentSamples.removeAll(keepingCapacity: false)
    }

    private func ingest(_ motion: CMDeviceMotion) {
        let rotation = motion.rotationRate
        let acceleration = motion.userAcceleration
        let rotationMagnitude = sqrt(
            (rotation.x * rotation.x) + (rotation.y * rotation.y) + (rotation.z * rotation.z)
        )
        let accelerationMagnitude = sqrt(
            (acceleration.x * acceleration.x) +
            (acceleration.y * acceleration.y) +
            (acceleration.z * acceleration.z)
        )
        recentSamples.append(LiveReviewMotionSample(
            rotationMagnitude: rotationMagnitude,
            accelerationMagnitude: accelerationMagnitude
        ))
        if recentSamples.count > classifier.maximumSamples {
            recentSamples.removeFirst(recentSamples.count - classifier.maximumSamples)
        }
        onChange?(classifier.classify(recentSamples))
    }
}
