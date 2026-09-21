import XCTest
@testable import PlainSky

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
        XCTAssertNil(preferences.loadCachedSnapshot())
    }

    func testCachedSnapshotRoundTrips() throws {
        let suite = "WeatherPreferencesSnapshotTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = WeatherPreferences(defaults: defaults)
        var snapshot = MockWeather.snapshot
        snapshot.availability[.alerts] = .loading
        snapshot.availability[.radar] = .unsupported("Radar is not connected in this test.")

        preferences.saveCachedSnapshot(snapshot)

        let loaded = try XCTUnwrap(preferences.loadCachedSnapshot())
        XCTAssertEqual(loaded.location, snapshot.location)
        XCTAssertEqual(loaded.current, snapshot.current)
        XCTAssertEqual(loaded.availability, snapshot.availability)
        XCTAssertEqual(loaded.hourly, snapshot.hourly)
        XCTAssertEqual(loaded.daily, snapshot.daily)
        XCTAssertEqual(loaded.minutePrecipitation, snapshot.minutePrecipitation)
        XCTAssertEqual(loaded.alerts, snapshot.alerts)
        XCTAssertEqual(loaded.solar, snapshot.solar)
        XCTAssertEqual(
            loaded.fetchedAt.timeIntervalSinceReferenceDate,
            snapshot.fetchedAt.timeIntervalSinceReferenceDate,
            accuracy: 0.001
        )
    }
}
