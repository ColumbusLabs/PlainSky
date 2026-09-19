import Observation
import SwiftUI

@MainActor
@Observable
final class WeatherStore {
    var snapshot: WeatherSnapshot
    var savedLocations: [WeatherLocation]
    var isRefreshing = false
    var appearance: AppAppearance = .system

    init(
        snapshot: WeatherSnapshot = MockWeather.snapshot,
        savedLocations: [WeatherLocation] = MockWeather.savedLocations
    ) {
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
        defer { isRefreshing = false }

        await Task.yield()

        let fresh = MockWeather.snapshot
        snapshot.current = fresh.current
        snapshot.hourly = fresh.hourly
        snapshot.daily = fresh.daily
        snapshot.minutePrecipitation = fresh.minutePrecipitation
        snapshot.alerts = fresh.alerts
        snapshot.solar = fresh.solar
        snapshot.fetchedAt = fresh.fetchedAt
    }

    func select(_ location: WeatherLocation) {
        snapshot.location = location
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
