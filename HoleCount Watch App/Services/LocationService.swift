import Foundation
import CoreLocation

/// Placeholder for Session 5: GPS-based course detection.
/// Will wrap CLLocationManager to provide one-shot location for course lookup.
@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    // TODO: Session 5 - Implement CLLocationManagerDelegate
    // - requestWhenInUseAuthorization()
    // - requestLocation() for one-shot GPS fix
    // - Handle authorization changes
}
