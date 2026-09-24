import XCTest
@testable import PlainSky

final class AppEnvironmentTests: XCTestCase {
    func testNormalLaunchUsesAssignedNWSNOAAAndWeatherKitSources() {
        XCTAssertEqual(AppEnvironment.dataMode(for: ["PlainSky"]), .liveNWSWeatherKit)
    }

    func testLiveNWSArgumentDisablesWeatherKitForDiagnostics() {
        XCTAssertEqual(
            AppEnvironment.dataMode(for: ["PlainSky", "--live-nws"]),
            .liveNWS
        )
    }

    func testPreviewArgumentTakesPriority() {
        XCTAssertEqual(
            AppEnvironment.dataMode(for: ["PlainSky", "--live-nws", "--preview-data"]),
            .preview
        )
    }

    @MainActor
    func testLiveStoreRestoresPreferencesButNeverDisplaysCachedWeather() throws {
        let suite = "AppEnvironmentFreshStartupTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = WeatherPreferences(defaults: defaults)
        let selected = WeatherLocation(
            name: "Home",
            region: "Indiana",
            latitude: 39.17,
            longitude: -86.52
        )
        var staleSnapshot = MockWeather.snapshot
        staleSnapshot.location = selected
        staleSnapshot.current.temperature = 99
        staleSnapshot.fetchedAt = Date()
        preferences.saveCachedSnapshot(staleSnapshot)
        preferences.saveLastLocation(selected)

        let store = AppEnvironment.makeLiveWeatherStore(
            includeWeatherKit: false,
            preferences: preferences
        )

        XCTAssertEqual(store.screenState.location, selected)
        XCTAssertTrue(store.screenState.current.isLoading)
        XCTAssertTrue(store.screenState.hourly.isLoading)
        XCTAssertTrue(store.screenState.daily.isLoading)
        XCTAssertTrue(store.screenState.alerts.isLoading)
        XCTAssertNil(store.screenState.current.value)
    }
}
