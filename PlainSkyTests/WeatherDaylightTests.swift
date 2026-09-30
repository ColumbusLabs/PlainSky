import XCTest
import UIKit
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

    func testBackdropPreservesWeatherAtNight() {
        let pairs: [(WeatherCondition, WeatherBackdropStyle, WeatherBackdropStyle)] = [
            (.clear, .clear, .night),
            (.mostlyClear, .clear, .night),
            (.partlyCloudy, .clear, .night),
            (.cloudy, .cloudy, .night),
            (.fog, .cloudy, .night),
            (.windy, .clear, .night),
            (.unknown, .clear, .night),
            (.rain, .rain, .rainNight),
            (.heavyRain, .heavyRain, .heavyRainNight),
            (.thunderstorm, .thunderstorm, .thunderstormNight),
            (.snow, .snow, .snowNight)
        ]
        for (condition, day, night) in pairs {
            XCTAssertEqual(WeatherBackdropStyle.forConditions(condition, isDaytime: true), day)
            XCTAssertEqual(WeatherBackdropStyle.forConditions(condition, isDaytime: false), night)
        }
        XCTAssertEqual(WeatherBackdropStyle.forConditions(.fog, isDaytime: true), .cloudy)
        XCTAssertEqual(WeatherBackdropStyle.forConditions(.partlyCloudy, isDaytime: true), .clear)
    }

    func testCurrentBackdropFollowsSolarEventsForSnapshotAndScreenState() {
        var snapshot = MockWeather.snapshot
        snapshot.current.condition = .thunderstorm
        snapshot.solar = solar
        for (hour, expected) in [(12, WeatherBackdropStyle.thunderstorm), (22, .thunderstormNight)] {
            XCTAssertEqual(WeatherBackdropStyle.current(for: snapshot, at: date(hour: hour)), expected)
            XCTAssertEqual(
                WeatherBackdropStyle.current(for: WeatherScreenState(preview: snapshot), at: date(hour: hour)),
                expected
            )
        }
        XCTAssertEqual(WeatherBackdropStyle.current(for: WeatherScreenState(location: snapshot.location)), .calm)
    }

    func testWeatherImagesAreBundledAndLoadable() throws {
        let pairs: [(WeatherCondition, String, String)] = [
            (.clear, "SkyDay", "SkyNight"),
            (.rain, "SkyRainDay", "SkyRainNight"),
            (.heavyRain, "SkyHeavyRainDay", "SkyHeavyRainNight"),
            (.thunderstorm, "SkyThunderstormDay", "SkyThunderstormNight"),
            (.snow, "SkySnowDay", "SkySnowNight")
        ]
        for (condition, day, night) in pairs {
            for (isDaytime, name) in [(true, day), (false, night)] {
                let style = WeatherBackdropStyle.forConditions(condition, isDaytime: isDaytime)
                XCTAssertEqual(style.imageName, name)
                let image = try XCTUnwrap(UIImage(named: name), "Missing bundled weather image: \(name)")
                XCTAssertGreaterThan(image.size.height, image.size.width)
            }
        }
        XCTAssertNil(WeatherBackdropStyle.calm.imageName)
    }
}
