import XCTest
@testable import WeatherApp

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
}

@MainActor
private final class DelayedWeatherRepository: WeatherRepository {
    let delays: [UUID: UInt64]
    let temperatures: [UUID: Double]

    init(delays: [UUID: UInt64], temperatures: [UUID: Double]) {
        self.delays = delays
        self.temperatures = temperatures
    }

    func load(location: WeatherLocation) async throws -> WeatherSnapshot {
        try await Task.sleep(nanoseconds: delays[location.id] ?? 0)

        var snapshot = MockWeather.snapshot
        snapshot.location = location
        snapshot.current.temperature = temperatures[location.id] ?? snapshot.current.temperature
        return snapshot
    }
}
