import XCTest
@testable import PlainSky

final class WeatherSourcePolicyTests: XCTestCase {
    func testFixedProviderAssignments() {
        XCTAssertEqual(
            WeatherSourcePolicy.provider(for: .currentConditions),
            .nwsObservation
        )
        XCTAssertEqual(
            WeatherSourcePolicy.provider(for: .hourlyForecast),
            .nwsForecast
        )
        XCTAssertEqual(
            WeatherSourcePolicy.provider(for: .dailyForecast),
            .nwsForecast
        )
        XCTAssertEqual(
            WeatherSourcePolicy.provider(for: .alerts),
            .nwsForecast
        )
        XCTAssertEqual(
            WeatherSourcePolicy.provider(for: .radar),
            .noaaRadar
        )
        XCTAssertEqual(
            WeatherSourcePolicy.provider(for: .minutePrecipitation),
            .weatherKit
        )
        XCTAssertEqual(
            WeatherSourcePolicy.provider(for: .uvIndex),
            .weatherKit
        )
        XCTAssertEqual(
            WeatherSourcePolicy.provider(for: .solarEvents),
            .weatherKit
        )
    }
}
