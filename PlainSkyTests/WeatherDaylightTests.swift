import XCTest
@testable import PlainSky

final class WeatherDaylightTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Indiana/Indianapolis")!
        return calendar
    }()

    private func date(day: Int = 22, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private var solar: SolarWeather {
        SolarWeather(
            sunrise: date(hour: 7, minute: 30),
            sunset: date(hour: 19, minute: 40),
            uvIndex: nil,
            source: MockWeather.snapshot.current.source
        )
    }

    func testUsesSolarTimesWhenAvailable() {
        XCTAssertFalse(WeatherDaylight.isDaytime(date(hour: 7, minute: 0), solar: solar, calendar: calendar))
        XCTAssertTrue(WeatherDaylight.isDaytime(date(hour: 12), solar: solar, calendar: calendar))
        XCTAssertFalse(WeatherDaylight.isDaytime(date(hour: 19, minute: 45), solar: solar, calendar: calendar))
    }

    func testAppliesTodaysSolarTimesToOtherDays() {
        XCTAssertTrue(WeatherDaylight.isDaytime(date(day: 24, hour: 12), solar: solar, calendar: calendar))
        XCTAssertFalse(WeatherDaylight.isDaytime(date(day: 24, hour: 22), solar: solar, calendar: calendar))
    }

    func testFallsBackToFixedHoursWithoutSolarData() {
        XCTAssertFalse(WeatherDaylight.isDaytime(date(hour: 6), solar: nil, calendar: calendar))
        XCTAssertTrue(WeatherDaylight.isDaytime(date(hour: 6, minute: 30), solar: nil, calendar: calendar))
        XCTAssertFalse(WeatherDaylight.isDaytime(date(hour: 19, minute: 30), solar: nil, calendar: calendar))
    }

    func testNightOverridesConditionForBackdrop() {
        XCTAssertEqual(WeatherBackdropStyle.forConditions(.rain, isDaytime: false), .night)
        XCTAssertEqual(WeatherBackdropStyle.forConditions(.rain, isDaytime: true), .rain)
        XCTAssertEqual(WeatherBackdropStyle.forConditions(.fog, isDaytime: true), .cloudy)
        XCTAssertEqual(WeatherBackdropStyle.forConditions(.partlyCloudy, isDaytime: true), .clear)
    }
}
