import XCTest
@testable import PlainSky

final class WidgetWeatherSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSnapshotDropsWeatherKitCurrentAndKeepsNWSForecasts() throws {
        var weather = MockWeather.snapshot
        weather.current.source.provider = .weatherKit
        weather.current.temperature = 91
        weather.current.conditionDescription = "Apple condition"
        weather.fetchedAt = now

        let snapshot = try XCTUnwrap(WidgetWeatherSnapshot(
            state: WeatherScreenState(preview: weather),
            asOf: now
        ))

        XCTAssertNil(snapshot.temperature)
        XCTAssertNil(snapshot.conditionDescription)
        XCTAssertNil(snapshot.condition)
        XCTAssertNil(snapshot.currentProvider)
        XCTAssertFalse(snapshot.hours.isEmpty)
        XCTAssertEqual(snapshot.high, weather.daily.first?.daytimeHigh)
        XCTAssertEqual(snapshot.low, weather.daily.first?.overnightLow)
    }

    func testSnapshotKeepsNWSCurrentWithProviderProvenance() throws {
        var weather = MockWeather.snapshot
        weather.current.source.provider = .nwsObservation
        weather.fetchedAt = now

        let snapshot = try XCTUnwrap(WidgetWeatherSnapshot(
            state: WeatherScreenState(preview: weather),
            asOf: now
        ))

        XCTAssertEqual(snapshot.temperature, weather.current.temperature)
        XCTAssertEqual(snapshot.conditionDescription, weather.current.conditionDescription)
        XCTAssertEqual(snapshot.currentProvider, WeatherProvider.nwsObservation.rawValue)
    }

    func testLegacySnapshotWithoutProviderDropsAmbiguousCurrentButKeepsForecasts() throws {
        let original = WidgetWeatherSnapshot(
            location: MockWeather.snapshot.location,
            temperature: 91,
            conditionDescription: "Unattributed current conditions",
            condition: .clear,
            high: 80,
            low: 60,
            hours: [.init(date: now.addingTimeInterval(3_600), temperature: 72)],
            currentProvider: .nwsObservation,
            asOf: now
        )
        let encoded = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "currentProvider")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let legacy = try JSONDecoder().decode(WidgetWeatherSnapshot.self, from: legacyData)
        XCTAssertNil(legacy.currentProvider)
        XCTAssertEqual(legacy.temperature, 91, "Decoding remains backward compatible.")

        let displayable = try XCTUnwrap(legacy.widgetDisplaySnapshot)
        XCTAssertNil(displayable.temperature)
        XCTAssertNil(displayable.conditionDescription)
        XCTAssertNil(displayable.condition)
        XCTAssertEqual(displayable.high, 80)
        XCTAssertEqual(displayable.low, 60)
        XCTAssertEqual(displayable.hours, original.hours)
    }

    func testCachedWeatherKitCurrentIsRemovedEvenWhenProvenanceIsPresent() throws {
        let snapshot = WidgetWeatherSnapshot(
            location: MockWeather.snapshot.location,
            temperature: 91,
            conditionDescription: "Apple condition",
            condition: .clear,
            high: 80,
            low: 60,
            hours: [],
            currentProvider: .weatherKit,
            asOf: now
        )

        let displayable = try XCTUnwrap(snapshot.widgetDisplaySnapshot)
        XCTAssertNil(displayable.temperature)
        XCTAssertNil(displayable.conditionDescription)
        XCTAssertNil(displayable.condition)
        XCTAssertNil(displayable.currentProvider)
        XCTAssertEqual(displayable.high, 80)
        XCTAssertEqual(displayable.low, 60)
    }
}
