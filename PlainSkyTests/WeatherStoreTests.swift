import XCTest
@testable import PlainSky

@MainActor
final class WeatherStoreTests: XCTestCase {
    func testRefreshCachesSnapshotWhenEnabled() async throws {
        let suite = "WeatherStoreCacheTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = WeatherPreferences(defaults: defaults)
        let store = WeatherStore(
            repository: PreviewWeatherRepository(),
            preferences: preferences,
            cachesSnapshots: true
        )

        await store.refresh()

        let cached = try XCTUnwrap(preferences.loadCachedSnapshot())
        XCTAssertEqual(cached.location.id, store.snapshot.location.id)
        XCTAssertEqual(cached.current.temperature, store.snapshot.current.temperature)
        XCTAssertFalse(store.isShowingPlaceholderData)
    }

    func testRefreshDoesNotCacheSnapshotByDefault() async throws {
        let suite = "WeatherStoreNoCacheTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = WeatherPreferences(defaults: defaults)
        let store = WeatherStore(
            repository: PreviewWeatherRepository(),
            preferences: preferences
        )

        await store.refresh()

        XCTAssertNil(preferences.loadCachedSnapshot())
    }

    func testSelectingPlaceWithRecentCacheShowsItWithoutPlaceholder() throws {
        let suite = "WeatherStoreSelectCacheTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = WeatherPreferences(defaults: defaults)
        let other = WeatherLocation(name: "Pensacola", region: "Florida", latitude: 30.4213, longitude: -87.2169)
        var cached = MockWeather.snapshot
        cached.location = other
        cached.current.temperature = 88
        preferences.saveCachedSnapshot(cached)

        let store = WeatherStore(
            repository: PreviewWeatherRepository(),
            preferences: preferences,
            masksStaleLocationData: true,
            cachesSnapshots: true
        )

        store.select(other)

        XCTAssertFalse(store.isShowingPlaceholderData)
        XCTAssertEqual(store.snapshot.location.id, other.id)
        XCTAssertEqual(store.snapshot.current.temperature, 88)
    }

    func testSelectingPlaceWithoutCacheShowsPlaceholder() throws {
        let suite = "WeatherStoreSelectNoCacheTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = WeatherStore(
            repository: PreviewWeatherRepository(),
            preferences: WeatherPreferences(defaults: defaults),
            masksStaleLocationData: true,
            cachesSnapshots: true
        )

        store.select(WeatherLocation(name: "Elsewhere", region: "Ohio", latitude: 39.9, longitude: -83.0))

        XCTAssertTrue(store.isShowingPlaceholderData)
    }

    func testRestoringFromCacheDropsTimeSensitiveProducts() {
        let restored = MockWeather.snapshot.restoringFromCache()

        XCTAssertTrue(restored.minutePrecipitation.isEmpty)
        XCTAssertTrue(restored.alerts.isEmpty)
        XCTAssertNil(restored.solar)

        XCTAssertEqual(restored.availability(for: .alerts), .loading)
        XCTAssertEqual(restored.availability(for: .minutePrecipitation), .loading)
        XCTAssertEqual(restored.availability(for: .uvIndex), .loading)
        XCTAssertEqual(restored.availability(for: .solarEvents), .loading)

        XCTAssertFalse(restored.hourly.isEmpty)
        XCTAssertFalse(restored.daily.isEmpty)
    }

    func testRefreshIfNeededRunsWhileProductsAreStillLoading() async {
        let repository = CountingWeatherRepository()
        var snapshot = MockWeather.snapshot
        snapshot.fetchedAt = Date()
        snapshot.availability[.alerts] = .loading

        let store = WeatherStore(repository: repository, snapshot: snapshot)

        await store.refreshIfNeeded()

        XCTAssertEqual(repository.loadCount, 1)
    }

    func testRefreshIfNeededSkipsFreshSnapshotWithNoPendingProducts() async {
        let repository = CountingWeatherRepository()
        var snapshot = MockWeather.snapshot
        snapshot.fetchedAt = Date()

        let store = WeatherStore(repository: repository, snapshot: snapshot)

        await store.refreshIfNeeded()

        XCTAssertEqual(repository.loadCount, 0)
    }

    func testFailedRefreshResolvesPendingProductsToUnavailable() async {
        let store = WeatherStore(
            repository: FailingWeatherRepository(),
            snapshot: MockWeather.snapshot.restoringFromCache()
        )

        await store.refresh()

        let error = store.lastRefreshError
        XCTAssertNotNil(error)

        for product in [WeatherProduct.alerts, .minutePrecipitation, .uvIndex, .solarEvents] {
            XCTAssertFalse(
                store.snapshot.availability(for: product).isLoading,
                "\(product) should not stay in a loading state after a failed refresh."
            )
        }

        XCTAssertEqual(store.snapshot.availability(for: .alerts).message, error)
    }
}

@MainActor
private final class CountingWeatherRepository: WeatherRepository {
    private(set) var loadCount = 0

    func load(
        location: WeatherLocation,
        onPrimary: (WeatherSnapshot) async -> Void
    ) async throws -> WeatherSnapshot {
        loadCount += 1

        var snapshot = MockWeather.snapshot
        snapshot.location = location
        await onPrimary(snapshot)
        return snapshot
    }
}

@MainActor
private struct FailingWeatherRepository: WeatherRepository {
    func load(
        location: WeatherLocation,
        onPrimary: (WeatherSnapshot) async -> Void
    ) async throws -> WeatherSnapshot {
        throw ProviderError.notConfigured("NWS is unavailable in test.")
    }
}
