import XCTest
@testable import WeatherApp

final class WeatherFormattersTests: XCTestCase {
    func testTemperatureFormatting() {
        XCTAssertEqual(WeatherFormatters.temperature(74.4), "74°")
        XCTAssertEqual(WeatherFormatters.temperature(74.6), "75°")
        XCTAssertEqual(WeatherFormatters.temperature(nil), "—")
    }

    func testProbabilityFormattingUsesProviderFraction() {
        XCTAssertEqual(WeatherFormatters.percent(0.42), "42%")
        XCTAssertEqual(WeatherFormatters.percent(nil), "—")
    }

    func testWindFormattingDoesNotInventDirection() {
        XCTAssertEqual(
            WeatherFormatters.wind(speed: 8.4, direction: "SW"),
            "SW 8 mph"
        )
        XCTAssertEqual(
            WeatherFormatters.wind(speed: 8.4, direction: nil),
            "8 mph"
        )
    }
}
