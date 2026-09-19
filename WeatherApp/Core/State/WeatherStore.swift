import Observation
import SwiftUI

@MainActor
@Observable
final class WeatherStore {
    var snapshot: WeatherSnapshot
    var savedLocations: [WeatherLocation]
    var isRefreshing = false
    var appearance: AppAppearance = .system
    var lastRefreshError: String?

    private let repository: any WeatherRepository

    init(
        repository: any WeatherRepository = PreviewWeatherRepository(),
        snapshot: WeatherSnapshot = MockWeather.snapshot,
        savedLocations: [WeatherLocation] = MockWeather.savedLocations
    ) {
        self.repository = repository
        self.snapshot = snapshot
        self.savedLocations = savedLocations
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
    }

    func setCurrentLocation(_ location: WeatherLocation) {
        var location = location
        location.isCurrentLocation = true

        if let index = savedLocations.firstIndex(where: { $0.isCurrentLocation }) {
            savedLocations[index] = location
        } else {
            savedLocations.insert(location, at: 0)
        }

        select(location)
    }

    func addLocation(_ location: WeatherLocation) {
        guard !savedLocations.contains(where: {
            abs($0.latitude - location.latitude) < 0.001 &&
            abs($0.longitude - location.longitude) < 0.001
        }) else {
            select(location)
            return
        }

        savedLocations.append(location)
        select(location)
    }

    func removeLocation(_ location: WeatherLocation) {
        guard !location.isCurrentLocation else { return }
        savedLocations.removeAll { $0.id == location.id }
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
