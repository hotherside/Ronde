import Foundation
import CoreMotion
import os.log

private let log = Logger(subsystem: "com.ronde.Ronde", category: "SwingDetector")

/// Detects full golf swings using high-frequency accelerometer data.
///
/// Uses `CMBatchedSensorManager` (watchOS 10+) to read batched accelerometer
/// samples at up to 800 Hz on Ultra / 200 Hz on standard watches.
///
/// Detection algorithm:
/// 1. Compute acceleration magnitude: sqrt(x² + y² + z²)
/// 2. Fire when magnitude exceeds threshold (~8 g)
/// 3. Enforce cooldown between detections to prevent double-counting
@MainActor
final class SwingDetector: ObservableObject {

    static let shared = SwingDetector()

    // MARK: - Published State

    /// Incremented each time a swing is detected. Observe with `.onChange`.
    @Published private(set) var swingCount: Int = 0

    /// Timestamp of the most recent swing detection — used for deduplication.
    @Published private(set) var lastSwingTime: Date = .distantPast

    // MARK: - Configuration

    /// Acceleration magnitude threshold in g's.
    /// Golf swing impact ≈ 10–30 g on the wrist; walking < 3 g.
    var accelerationThreshold: Double = 8.0

    /// Minimum seconds between detections.
    var cooldownSeconds: TimeInterval = 3.0

    // MARK: - Private

    private var detectionTask: Task<Void, Never>?
    private var isRunning = false

    private init() {}

    // MARK: - Hardware Check

    /// Whether the device supports batched accelerometer (watchOS 10+ with compatible hardware).
    static var isSupported: Bool {
        CMBatchedSensorManager.isAccelerometerSupported
    }

    // MARK: - Lifecycle

    /// Start listening for swing events. Call when a round begins.
    func startDetecting() {
        guard Self.isSupported else {
            log.warning("Batched accelerometer not supported — swing detection disabled")
            return
        }
        guard !isRunning else { return }

        isRunning = true
        swingCount = 0
        lastSwingTime = .distantPast

        let manager = CMBatchedSensorManager()

        detectionTask = Task { [weak self] in
            guard let self else { return }

            log.info(
                "Swing detection started (threshold: \(self.accelerationThreshold)g, cooldown: \(self.cooldownSeconds)s)"
            )

            do {
                for try await batch in manager.accelerometerUpdates() {
                    guard !Task.isCancelled else { break }
                    self.processBatch(batch)
                }
            } catch {
                log.error("Accelerometer stream error: \(error.localizedDescription)")
            }

            log.info("Swing detection loop ended")
        }
    }

    /// Stop listening for swing events. Call when a round ends.
    func stopDetecting() {
        detectionTask?.cancel()
        detectionTask = nil
        isRunning = false
        log.info("Swing detection stopped — \(self.swingCount) swings detected this session")
    }

    // MARK: - Detection Logic

    private func processBatch(_ batch: [CMAccelerometerData]) {
        for sample in batch {
            let acc = sample.acceleration
            let magnitude = (acc.x * acc.x + acc.y * acc.y + acc.z * acc.z).squareRoot()

            guard magnitude >= accelerationThreshold else { continue }

            let now = Date()
            guard now.timeIntervalSince(lastSwingTime) >= cooldownSeconds else {
                // Within cooldown — skip
                continue
            }

            // Swing detected
            lastSwingTime = now
            swingCount += 1
            log.debug(
                "Swing detected — magnitude: \(String(format: "%.1f", magnitude))g, total: \(self.swingCount)"
            )

            // Break after first detection in this batch; the same physical swing
            // produces hundreds of consecutive high-g samples.
            break
        }
    }

    // MARK: - Deduplication

    /// Returns `true` if a swing was detected within the given time window.
    /// Used to avoid double-counting when both swing detection and a manual tap
    /// (Action Button or on-screen +) fire for the same swing.
    func wasSwingDetectedWithin(seconds: TimeInterval = 2.0) -> Bool {
        Date().timeIntervalSince(lastSwingTime) < seconds
    }
}
