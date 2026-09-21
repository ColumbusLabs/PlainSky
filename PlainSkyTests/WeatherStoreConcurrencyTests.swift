import XCTest
@testable import PlainSky

@MainActor
final class WeatherStoreConcurrencyTests: XCTestCase {
    func testOlderLocationResponseCannotOverwriteNewerSelection() async throws {
        let first = WeatherLocation(
            name: "Slow City",
            region: "Indiana",
            latitude: 39.0,
            longitude: -86.0
        )
        let second = WeatherLocation(
            name: "Fast City",
            region: "Indiana",
            latitude: 40.0,
            longitude: -85.0
        )

        let repository = DelayedWeatherRepository(
            delays: [
                first.id: 180_000_000,
                second.id: 10_000_000
            ],
            temperatures: [
                first.id: 41,
                second.id: 78
            ]
        )

        let suite = "WeatherStoreConcurrencyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = WeatherStore(
            repository: repository,
            snapshot: MockWeather.snapshot,
            savedLocations: [first, second],
            preferences: WeatherPreferences(defaults: defaults)
        )

        store.select(first)
        let slowLoad = Task { await store.refresh() }

        try await Task.sleep(nanoseconds: 25_000_000)

        store.select(second)
        let fastLoad = Task { await store.refresh() }

        await fastLoad.value
        await slowLoad.value

        XCTAssertEqual(store.snapshot.location.id, second.id)
        XCTAssertEqual(store.snapshot.current.temperature, 78)
        XCTAssertFalse(store.isRefreshing)
    }

    func testSavedPlaceRenameReorderAndSelectedRemoval() async throws {
        let current = WeatherLocation(
            name: "Current Location",
            region: "Indiana",
            latitude: 39.0,
            longitude: -86.0,
            isCurrentLocation: true
        )
        let first = WeatherLocation(
            name: "First",
            region: "Indiana",
            latitude: 40.0,
            longitude: -85.0
        )
        let second = WeatherLocation(
            name: "Second",
            region: "Ohio",
            latitude: 39.9,
            longitude: -83.0
        )

        let suite = "WeatherStorePlacesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var snapshot = MockWeather.snapshot
        snapshot.location = first

        let store = WeatherStore(
            snapshot: snapshot,
            savedLocations: [current, first, second],
            preferences: WeatherPreferences(defaults: defaults)
        )

        store.renameLocation(first, to: "Home")
        XCTAssertEqual(store.savedLocations[1].name, "Home")
        XCTAssertEqual(store.snapshot.location.name, "Home")

        let renamedFirst = store.savedLocations[1]
        XCTAssertFalse(store.canMoveLocation(renamedFirst, offset: -1))
        XCTAssertTrue(store.canMoveLocation(second, offset: -1))

        store.moveLocation(second, offset: -1)
        XCTAssertEqual(store.savedLocations.map(\.name), ["Current Location", "Second", "Home"])

        store.removeLocation(renamedFirst)
        XCTAssertEqual(store.savedLocations.map(\.name), ["Current Location", "Second"])
        XCTAssertEqual(store.snapshot.location.id, current.id)

        await Task.yield()
    }

    func testCurrentLocationCannotBeRenamedMovedOrRemoved() throws {
        let current = WeatherLocation(
            name: "Current Location",
            region: "Indiana",
            latitude: 39.0,
            longitude: -86.0,
            isCurrentLocation: true
        )
        let saved = WeatherLocation(
            name: "Saved",
            region: "Indiana",
            latitude: 40.0,
            longitude: -85.0
        )

        let suite = "WeatherStorePinnedCurrentTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = WeatherStore(
            savedLocations: [current, saved],
            preferences: WeatherPreferences(defaults: defaults)
        )

        store.renameLocation(current, to: "Renamed")
        store.moveLocation(current, offset: 1)
        store.removeLocation(current)

        XCTAssertEqual(store.savedLocations.first?.name, "Current Location")
        XCTAssertEqual(store.savedLocations.count, 2)
    }
}

@MainActor
private final class DelayedWeatherRepository: WeatherRepository {
    let delays: [UUID: UInt64]
    let temperatures: [UUID: Double]

    init(delays: [UUID: UInt64], temperatures: [UUID: Double]) {
        self.delays = delays
        self.temperatures = temperatures
    }

    func load(
        location: WeatherLocation,
        onPrimary: (WeatherSnapshot) async -> Void
    ) async throws -> WeatherSnapshot {
        try await Task.sleep(nanoseconds: delays[location.id] ?? 0)

        var snapshot = MockWeather.snapshot
        snapshot.location = location
        snapshot.current.temperature = temperatures[location.id] ?? snapshot.current.temperature
        await onPrimary(snapshot)
        return snapshot
    }
}
