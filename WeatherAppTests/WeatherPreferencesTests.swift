import XCTest
@testable import WeatherApp

@MainActor
final class WeatherPreferencesTests: XCTestCase {
    func testLocationsAppearanceAndUnitsRoundTrip() throws {
        let suite = "WeatherPreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = WeatherPreferences(defaults: defaults)
        let location = WeatherLocation(
            name: "Columbus",
            region: "Indiana",
            latitude: 39.2014,
            longitude: -85.9214
        )

        preferences.saveSavedLocations([location])
        preferences.saveLastLocation(location)
        preferences.saveAppearance(.dark)
        preferences.saveUnitSystem(.metric)

        XCTAssertEqual(preferences.loadSavedLocations(), [location])
        XCTAssertEqual(preferences.loadLastLocation(), location)
        XCTAssertEqual(preferences.loadAppearance(), .dark)
        XCTAssertEqual(preferences.loadUnitSystem(), .metric)
    }

    func testMissingPreferencesReturnNilInsteadOfInventingValues() throws {
        let suite = "WeatherPreferencesEmptyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = WeatherPreferences(defaults: defaults)

        XCTAssertNil(preferences.loadSavedLocations())
        XCTAssertNil(preferences.loadLastLocation())
        XCTAssertNil(preferences.loadAppearance())
        XCTAssertNil(preferences.loadUnitSystem())
    }
}
