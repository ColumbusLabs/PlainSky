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
        snapshot = MockWeather.snapshot
    }

    func select(_ location: WeatherLocation) {
        snapshot.location = location
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
