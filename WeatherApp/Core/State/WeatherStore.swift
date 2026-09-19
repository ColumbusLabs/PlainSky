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

    var unitSystem: WeatherUnitSystem {
        didSet {
            preferences.saveUnitSystem(unitSystem)
        }
    }

    private let repository: any WeatherRepository
    private let preferences: WeatherPreferences
    private var loadGeneration = 0

    init(
        repository: (any WeatherRepository)? = nil,
        snapshot: WeatherSnapshot = MockWeather.snapshot,
        savedLocations: [WeatherLocation]? = nil,
        preferences: WeatherPreferences = .live
    ) {
        self.repository = repository ?? PreviewWeatherRepository()
        self.preferences = preferences
        self.appearance = preferences.loadAppearance() ?? .system
        self.unitSystem = preferences.loadUnitSystem() ?? .us
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

    func refreshIfNeeded(maxAge: TimeInterval = 10 * 60) async {
        guard !isRefreshing else { return }

        let age = Date().timeIntervalSince(snapshot.fetchedAt)
        guard age >= maxAge else { return }

        await refresh()
    }

    func refresh() async {
        loadGeneration += 1
        let generation = loadGeneration
        let requestedLocation = snapshot.location

        isRefreshing = true
        lastRefreshError = nil

        do {
            let loadedSnapshot = try await repository.load(location: requestedLocation)

            guard generation == loadGeneration,
                  snapshot.location.id == requestedLocation.id else {
                return
            }

            snapshot = loadedSnapshot
        } catch {
            guard generation == loadGeneration else { return }
            lastRefreshError = error.localizedDescription
        }

        if generation == loadGeneration {
            isRefreshing = false
        }
    }

    func select(_ location: WeatherLocation) {
        invalidateOutstandingLoad()
        snapshot.location = location
        preferences.saveLastLocation(location)
    }

    func selectAndRefresh(_ location: WeatherLocation) {
        select(location)
        Task {
            await refresh()
        }
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

    func setCurrentLocationAndRefresh(_ location: WeatherLocation) {
        setCurrentLocation(location)
        Task {
            await refresh()
        }
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

    func addLocationAndRefresh(_ location: WeatherLocation) {
        addLocation(location)
        Task {
            await refresh()
        }
    }

    func removeLocation(_ location: WeatherLocation) {
        guard !location.isCurrentLocation else { return }
        savedLocations.removeAll { $0.id == location.id }
        persistLocations()
    }

    func clearRefreshError() {
        lastRefreshError = nil
    }

    private func invalidateOutstandingLoad() {
        loadGeneration += 1
        isRefreshing = false
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
