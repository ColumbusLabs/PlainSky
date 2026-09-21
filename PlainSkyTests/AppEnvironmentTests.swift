import XCTest
@testable import PlainSky

final class AppEnvironmentTests: XCTestCase {
    func testNormalLaunchUsesLiveNWSWithoutWeatherKitSupplements() {
        XCTAssertEqual(AppEnvironment.dataMode(for: ["PlainSky"]), .liveNWS)
    }

    func testWeatherKitArgumentOptsIntoSupplements() {
        XCTAssertEqual(
            AppEnvironment.dataMode(for: ["PlainSky", "--live-weatherkit"]),
            .liveNWSWeatherKit
        )
    }

    func testPreviewArgumentTakesPriority() {
        XCTAssertEqual(
            AppEnvironment.dataMode(for: ["PlainSky", "--live-weatherkit", "--preview-data"]),
            .preview
        )
    }

    @MainActor
    func testRestorableSnapshotRestoresWithoutSavedLastLocation() throws {
        let suite = "AppEnvironmentRestoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = WeatherPreferences(defaults: defaults)
        let snapshot = MockWeather.snapshot

        preferences.saveCachedSnapshot(snapshot)

        let restored = try XCTUnwrap(
            AppEnvironment.restorableSnapshot(from: preferences)
        )
        XCTAssertEqual(restored.location.id, snapshot.location.id)
        XCTAssertEqual(restored.current.temperature, snapshot.current.temperature)
        XCTAssertTrue(restored.alerts.isEmpty)
        XCTAssertTrue(restored.availability(for: .alerts).isLoading)
        XCTAssertTrue(restored.availability(for: .uvIndex).isLoading)
        XCTAssertNil(restored.solar)
    }

    @MainActor
    func testRestorableSnapshotAcceptsCacheForSavedLastLocation() throws {
        let suite = "AppEnvironmentRestoreMatchTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = WeatherPreferences(defaults: defaults)
        let snapshot = MockWeather.snapshot

        preferences.saveCachedSnapshot(snapshot)
        preferences.saveLastLocation(snapshot.location)

        let restored = try XCTUnwrap(
            AppEnvironment.restorableSnapshot(from: preferences)
        )
        XCTAssertEqual(restored.location.id, snapshot.location.id)
    }

    @MainActor
    func testRestorableSnapshotAcceptsRecentCache() throws {
        let suite = "AppEnvironmentRecentCacheTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = WeatherPreferences(defaults: defaults)
        var snapshot = MockWeather.snapshot
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        snapshot.fetchedAt = now.addingTimeInterval(
            -AppEnvironment.maximumRestorableSnapshotAge + 1
        )
        preferences.saveCachedSnapshot(snapshot)

        XCTAssertNotNil(AppEnvironment.restorableSnapshot(from: preferences, now: now))
    }

    @MainActor
    func testRestorableSnapshotRejectsExpiredCache() throws {
        let suite = "AppEnvironmentExpiredCacheTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = WeatherPreferences(defaults: defaults)
        var snapshot = MockWeather.snapshot
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        snapshot.fetchedAt = now.addingTimeInterval(
            -AppEnvironment.maximumRestorableSnapshotAge - 1
        )
        preferences.saveCachedSnapshot(snapshot)

        XCTAssertNil(AppEnvironment.restorableSnapshot(from: preferences, now: now))
    }

    @MainActor
    func testRestorableSnapshotRejectsCacheForAnotherLocation() throws {
        let suite = "AppEnvironmentRestoreMismatchTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = WeatherPreferences(defaults: defaults)

        preferences.saveCachedSnapshot(MockWeather.snapshot)
        preferences.saveLastLocation(
            WeatherLocation(
                name: "Other",
                region: "Ohio",
                latitude: 39.9,
                longitude: -83.0
            )
        )

        XCTAssertNil(AppEnvironment.restorableSnapshot(from: preferences))
    }
}
