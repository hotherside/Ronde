import Foundation
import CoreLocation
import os

/// Provides a one-shot GPS fix for course auto-detection.
/// Call `requestPermissionAndLocation()` to kick off the process.
/// Observe `currentLocation` and `authorizationStatus` for updates.
@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private let logger = Logger(subsystem: "com.ronde.Ronde", category: "LocationService")

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    /// Requests permission (if needed) then triggers a one-shot location fix.
    func requestPermissionAndLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            break // authorizationStatus publisher notifies observers
        @unknown default:
            break
        }
    }

    func stopUpdates() {
        manager.stopUpdatingLocation()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.currentLocation = location
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.logger.error("Location fix failed: \(error.localizedDescription)")
            // currentLocation stays nil; CourseDetectView reacts to the timeout.
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = self.manager.authorizationStatus
            if self.manager.authorizationStatus == .authorizedAlways
                || self.manager.authorizationStatus == .authorizedWhenInUse {
                self.manager.requestLocation()
            }
        }
    }
}
