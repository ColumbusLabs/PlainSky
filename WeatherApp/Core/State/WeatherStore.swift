import Observation
import SwiftUI

@MainActor
@Observable
final class WeatherStore {
    var snapshot: WeatherSnapshot
    var savedLocations: [WeatherLocation]
    var isRefreshing = false
    var lastRefreshError: String?

    var appearance: AppAppearance {
        didSet {
            preferences.saveAppearance(appearance)
        }
    }

    private let repository: any WeatherRepository
    private let preferences: WeatherPreferences

    init(
        repository: (any WeatherRepository)? = nil,
        snapshot: WeatherSnapshot = MockWeather.snapshot,
        savedLocations: [WeatherLocation]? = nil,
        preferences: WeatherPreferences = .live
    ) {
        self.repository = repository ?? PreviewWeatherRepository()
        self.preferences = preferences
        self.appearance = preferences.loadAppearance() ?? .system
        self.savedLocations = savedLocations
            ?? preferences.loadSavedLocations()
            ?? MockWeather.savedLocations

        var initialSnapshot = snapshot
        if let lastLocation = preferences.loadLastLocation() {
            initialSnapshot.location = lastLocation
        }
        self.snapshot = initialSnapshot
    }

    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        lastRefreshError = nil
        defer { isRefreshing = false }

        do {
            snapshot = try await repository.load(location: snapshot.location)
        } catch {
            lastRefreshError = error.localizedDescription
        }
    }

    func select(_ location: WeatherLocation) {
        snapshot.location = location
        preferences.saveLastLocation(location)
    }

    func setCurrentLocation(_ location: WeatherLocation) {
        var location = location
        location.isCurrentLocation = true

        if let index = savedLocations.firstIndex(where: { $0.isCurrentLocation }) {
            savedLocations[index] = location
        } else {
            savedLocations.insert(location, at: 0)
        }

        persistLocations()
        select(location)
    }

    func addLocation(_ location: WeatherLocation) {
        if let existing = savedLocations.first(where: {
            abs($0.latitude - location.latitude) < 0.001 &&
            abs($0.longitude - location.longitude) < 0.001
        }) {
            select(existing)
            return
        }

        savedLocations.append(location)
        persistLocations()
        select(location)
    }

    func removeLocation(_ location: WeatherLocation) {
        guard !location.isCurrentLocation else { return }
        savedLocations.removeAll { $0.id == location.id }
        persistLocations()
    }

    func clearRefreshError() {
        lastRefreshError = nil
    }

    private func persistLocations() {
        preferences.saveSavedLocations(savedLocations)
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
