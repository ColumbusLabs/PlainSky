import Foundation

@MainActor
struct WeatherPreferences {
    static let live = WeatherPreferences(defaults: .standard)

    private enum Key {
        static let savedLocations = "weather.savedLocations"
        static let lastLocation = "weather.lastLocation"
        static let unitSystem = "weather.unitSystem"
        static let cachedSnapshot = "weather.cachedSnapshot"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func loadSavedLocations() -> [WeatherLocation]? {
        guard let data = defaults.data(forKey: Key.savedLocations) else { return nil }
        return try? decoder.decode([WeatherLocation].self, from: data)
    }

    func saveSavedLocations(_ locations: [WeatherLocation]) {
        guard let data = try? encoder.encode(locations) else { return }
        defaults.set(data, forKey: Key.savedLocations)
    }

    func loadLastLocation() -> WeatherLocation? {
        guard let data = defaults.data(forKey: Key.lastLocation) else { return nil }
        return try? decoder.decode(WeatherLocation.self, from: data)
    }

    func saveLastLocation(_ location: WeatherLocation) {
        guard let data = try? encoder.encode(location) else { return }
        defaults.set(data, forKey: Key.lastLocation)
    }

    func loadUnitSystem() -> WeatherUnitSystem? {
        guard let rawValue = defaults.string(forKey: Key.unitSystem) else { return nil }
        return WeatherUnitSystem(rawValue: rawValue)
    }

    func saveUnitSystem(_ unitSystem: WeatherUnitSystem) {
        defaults.set(unitSystem.rawValue, forKey: Key.unitSystem)
    }

    func loadCachedSnapshot() -> WeatherSnapshot? {
        guard let data = defaults.data(forKey: Key.cachedSnapshot) else { return nil }
        return try? decoder.decode(WeatherSnapshot.self, from: data)
    }

    func saveCachedSnapshot(_ snapshot: WeatherSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: Key.cachedSnapshot)
    }
}
