import XCTest
@testable import PlainSky

final class WeatherFormattersTests: XCTestCase {
    func testTemperatureFormatting() {
        XCTAssertEqual(WeatherFormatters.temperature(74.4), "74°")
        XCTAssertEqual(WeatherFormatters.temperature(74.6), "75°")
        XCTAssertEqual(WeatherFormatters.temperature(nil), "—")
    }

    func testMetricTemperatureConversionIsPresentationOnly() {
        XCTAssertEqual(
            WeatherFormatters.temperature(68, unitSystem: .metric),
            "20°"
        )
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

    func testTonightLabelDoesNotInventTodayDaytimePeriod() throws {
        let today = Date()

        XCTAssertEqual(
            WeatherFormatters.fullForecastDay(
                today,
                hasDaytimePeriod: false
            ),
            "Tonight"
        )
        XCTAssertEqual(
            WeatherFormatters.shortForecastDay(
                today,
                hasDaytimePeriod: false
            ),
            "Tonight"
        )
    }

    func testCompactDayUsesTodayOrTonight() {
        let today = Date()

        XCTAssertEqual(WeatherFormatters.compactDay(today, hasDaytimePeriod: true), "Today")
        XCTAssertEqual(WeatherFormatters.compactDay(today, hasDaytimePeriod: false), "Tonight")
    }

    func testUVCategoryBoundaries() {
        XCTAssertEqual(WeatherFormatters.uvCategory(2), "Low")
        XCTAssertEqual(WeatherFormatters.uvCategory(3), "Moderate")
        XCTAssertEqual(WeatherFormatters.uvCategory(6), "High")
        XCTAssertEqual(WeatherFormatters.uvCategory(8), "Very High")
        XCTAssertEqual(WeatherFormatters.uvCategory(11), "Extreme")
    }

    func testMetricWindAndVisibilityConversion() {
        XCTAssertEqual(
            WeatherFormatters.wind(
                speed: 10,
                direction: nil,
                unitSystem: .metric
            ),
            "16 km/h"
        )

        XCTAssertEqual(
            WeatherFormatters.visibility(
                10,
                unitSystem: .metric
            ),
            "16 km"
        )
    }
}
