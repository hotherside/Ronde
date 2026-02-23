import Foundation
import CoreMotion
import os.log

private let log = Logger(subsystem: "com.ronde.Ronde", category: "SwingDetector")

/// Detects full golf swings using high-frequency accelerometer data and
/// derives per-swing metrics (peak g-force, estimated speed, tempo).
///
/// Uses `CMBatchedSensorManager` (watchOS 10+) to read batched accelerometer
/// samples at up to 800 Hz on Ultra / 200 Hz on standard watches.
///
/// Detection algorithm:
/// 1. Compute acceleration magnitude: sqrt(x² + y² + z²)
/// 2. Append to rolling buffer for swing-window capture
/// 3. Fire when magnitude exceeds threshold (~8 g)
/// 4. Enforce cooldown between detections to prevent double-counting
/// 5. Extract metrics from the buffered window around the swing event
@MainActor
final class SwingDetector: ObservableObject {

    static let shared = SwingDetector()

    // MARK: - Published State

    /// Incremented each time a swing is detected. Observe with `.onChange`.
    @Published private(set) var swingCount: Int = 0

    /// Timestamp of the most recent swing detection — used for deduplication.
    @Published private(set) var lastSwingTime: Date = .distantPast

    /// Metrics from the most recently detected swing. Set after a brief capture delay.
    @Published private(set) var lastSwingMetrics: SwingMetrics?

    // MARK: - Configuration

    /// Acceleration magnitude threshold in g's.
    /// Golf swing impact ≈ 10–30 g on the wrist; walking < 3 g.
    var accelerationThreshold: Double = 8.0

    /// Minimum seconds between detections.
    var cooldownSeconds: TimeInterval = 3.0

    // MARK: - Private

    private var detectionTask: Task<Void, Never>?
    private var metricsTask: Task<Void, Never>?
    private var isRunning = false

    /// Rolling buffer of recent acceleration samples for swing-window capture.
    /// Keeps the last `bufferDurationSeconds` worth of data.
    private var sampleBuffer: [(magnitude: Double, timestamp: TimeInterval)] = []

    /// How many seconds of history to retain in the rolling buffer.
    /// 1.5 seconds captures the full swing arc (backswing through follow-through).
    private let bufferDurationSeconds: TimeInterval = 1.5

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
        lastSwingMetrics = nil
        sampleBuffer.removeAll()

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
        metricsTask?.cancel()
        metricsTask = nil
        isRunning = false
        sampleBuffer.removeAll()
        log.info("Swing detection stopped — \(self.swingCount) swings detected this session")
    }

    // MARK: - Detection Logic

    private func processBatch(_ batch: [CMAccelerometerData]) {
        for sample in batch {
            let acc = sample.acceleration
            let magnitude = (acc.x * acc.x + acc.y * acc.y + acc.z * acc.z).squareRoot()

            // 1. Append to rolling buffer
            sampleBuffer.append((magnitude: magnitude, timestamp: sample.timestamp))

            // 2. Trim buffer to keep only recent history
            let cutoff = sample.timestamp - bufferDurationSeconds
            while let first = sampleBuffer.first, first.timestamp < cutoff {
                sampleBuffer.removeFirst()
            }

            // 3. Check threshold
            guard magnitude >= accelerationThreshold else { continue }

            let now = Date()
            guard now.timeIntervalSince(lastSwingTime) >= cooldownSeconds else {
                // Within cooldown — skip
                continue
            }

            // 4. Swing detected
            lastSwingTime = now
            swingCount += 1
            log.debug(
                "Swing detected — magnitude: \(String(format: "%.1f", magnitude))g, total: \(self.swingCount)"
            )

            // 5. Schedule metrics extraction after brief follow-through capture
            captureSwingMetrics()

            // Break after first detection in this batch; the same physical swing
            // produces hundreds of consecutive high-g samples.
            break
        }
    }

    // MARK: - Metrics Extraction

    /// Wait briefly for follow-through samples, then extract metrics from the buffer.
    private func captureSwingMetrics() {
        metricsTask?.cancel()
        metricsTask = Task { @MainActor [weak self] in
            // Wait 300ms for follow-through data to arrive in subsequent batches
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            guard let self else { return }

            let window = self.sampleBuffer
            guard !window.isEmpty else { return }

            // Peak g-force
            let peakG = window.map(\.magnitude).max() ?? self.accelerationThreshold

            // Find the index where threshold was first crossed
            let thresholdIndex = window.firstIndex(where: {
                $0.magnitude >= self.accelerationThreshold
            }) ?? 0

            // Find the index of peak magnitude
            let peakIndex: Int = {
                var best = thresholdIndex
                for i in window.indices where window[i].magnitude >= peakG - 0.01 {
                    best = i
                    break
                }
                return best
            }()

            // Tempo: time from first threshold crossing to peak
            let tempoSeconds: Double
            if peakIndex > thresholdIndex {
                tempoSeconds = window[peakIndex].timestamp - window[thresholdIndex].timestamp
            } else {
                tempoSeconds = 0.1  // fallback minimum
            }

            // Estimated speed via impulse integration:
            // Integrate magnitude above 1g (gravity baseline) over the swing window
            // v = ∫(a × dt) from threshold crossing to end of window
            let baselineG = 1.0
            var integratedAcceleration = 0.0
            let startIdx = max(thresholdIndex, 1)
            for i in startIdx..<window.count {
                guard i > 0 else { continue }
                let dt = window[i].timestamp - window[i - 1].timestamp
                let netAccel = max(window[i].magnitude - baselineG, 0.0)
                integratedAcceleration += netAccel * 9.81 * dt  // g → m/s²
            }

            // Downsample acceleration profile to ~60 points for arc rendering
            let profile = window.map(\.magnitude)
            let downsampledProfile = Self.downsample(profile, targetCount: 60)

            let metrics = SwingMetrics(
                id: UUID(),
                timestamp: .now,
                peakG: peakG,
                estimatedSpeedMPS: integratedAcceleration,
                tempoSeconds: max(tempoSeconds, 0.05),
                accelerationProfile: downsampledProfile
            )

            self.lastSwingMetrics = metrics

            log.debug(
                "Swing metrics: peak=\(String(format: "%.1f", peakG))g, speed=\(String(format: "%.0f", metrics.estimatedSpeedKMH))km/h, tempo=\(metrics.tempoFormatted)"
            )
        }
    }

    /// Downsample an array to approximately `targetCount` points using averaging.
    private static func downsample(_ values: [Double], targetCount: Int) -> [Double] {
        guard values.count > targetCount else { return values }
        let chunkSize = values.count / targetCount
        return stride(from: 0, to: values.count, by: chunkSize).prefix(targetCount).map { start in
            let end = min(start + chunkSize, values.count)
            let slice = values[start..<end]
            return slice.reduce(0, +) / Double(slice.count)
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
