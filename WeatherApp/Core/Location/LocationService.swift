@preconcurrency import CoreLocation
import Observation

@MainActor
@Observable
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    var currentLocation: WeatherLocation?
    var authorizationStatus: CLAuthorizationStatus
    var isResolving = false
    var errorMessage: String?

    private let manager: CLLocationManager
    private let geocoder = CLGeocoder()

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestCurrentLocation() {
        errorMessage = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()

        case .authorizedWhenInUse, .authorizedAlways:
            isResolving = true
            manager.requestLocation()

        case .denied, .restricted:
            errorMessage = "Location access is unavailable. Search for a place instead."

        @unknown default:
            errorMessage = "Location access is unavailable. Search for a place instead."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        if manager.authorizationStatus == .authorizedWhenInUse ||
            manager.authorizationStatus == .authorizedAlways {
            isResolving = true
            manager.requestLocation()
        } else if manager.authorizationStatus == .denied ||
                    manager.authorizationStatus == .restricted {
            isResolving = false
            errorMessage = "Location access is unavailable. Search for a place instead."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            isResolving = false
            return
        }

        Task {
            let placemark = try? await geocoder.reverseGeocodeLocation(location).first
            let locality = placemark?.locality ?? placemark?.subAdministrativeArea ?? "Current Location"
            let region = placemark?.administrativeArea ?? ""

            currentLocation = WeatherLocation(
                name: locality,
                region: region,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                isCurrentLocation: true
            )
            isResolving = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        isResolving = false
        errorMessage = "Your current location could not be resolved. Search for a place instead."
    }
}
