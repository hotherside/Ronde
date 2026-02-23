import Foundation
import CoreMotion
import os.log

private let log = Logger(subsystem: "com.ronde.Ronde", category: "PedometerService")

/// Provides real-time step count and distance during a round using CMPedometer.
@MainActor
final class PedometerService: ObservableObject {

    static let shared = PedometerService()

    @Published private(set) var totalSteps: Int = 0
    @Published private(set) var totalDistanceMeters: Double = 0.0

    private let pedometer = CMPedometer()
    private var isTracking = false

    private init() {}

    // MARK: - Lifecycle

    /// Begin live pedometer updates from the given start date.
    func startTracking(from startDate: Date = .now) {
        guard CMPedometer.isStepCountingAvailable() else {
            log.warning("Step counting not available on this device")
            return
        }
        guard !isTracking else { return }

        isTracking = true
        totalSteps = 0
        totalDistanceMeters = 0.0

        pedometer.startUpdates(from: startDate) { [weak self] data, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    log.error("Pedometer update error: \(error.localizedDescription)")
                    return
                }
                guard let data else { return }
                self.totalSteps = data.numberOfSteps.intValue
                self.totalDistanceMeters = data.distance?.doubleValue ?? 0.0
            }
        }

        log.info("Pedometer tracking started")
    }

    /// Stop updates and return final values for persistence.
    func stopTracking() -> (steps: Int, distanceMeters: Double) {
        pedometer.stopUpdates()
        isTracking = false
        let result = (steps: totalSteps, distanceMeters: totalDistanceMeters)
        log.info("Pedometer stopped — \(result.steps) steps, \(String(format: "%.0f", result.distanceMeters))m")
        return result
    }
}
