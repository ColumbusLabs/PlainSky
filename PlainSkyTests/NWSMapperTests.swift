import XCTest
@testable import PlainSky

final class NWSMapperTests: XCTestCase {
    func testCurrentObservationMapsCanonicalValues() throws {
        let now = try XCTUnwrap(NWSParsing.date("2026-09-19T23:00:00Z"))
        let observation = NWSObservationResponse(
            properties: NWSObservationProperties(
                stationId: "KIND",
                stationName: "Indianapolis International Airport",
                timestamp: "2026-09-19T22:30:00Z",
                textDescription: "Partly Cloudy",
                temperature: qv("unit:degC", 20),
                dewpoint: qv("unit:degC", 10),
                windDirection: qv("unit:degree_(angle)", 225),
                windSpeed: qv("unit:m_s-1", 10),
                windGust: qv("unit:m_s-1", 15),
                barometricPressure: qv("unit:Pa", 101_325),
                visibility: qv("unit:m", 16_093.44),
                relativeHumidity: qv("unit:percent", 50),
                windChill: nil,
                heatIndex: qv("unit:degC", 21)
            )
        )

        let mapped = try XCTUnwrap(
            NWSMapper.currentConditions(
                station: NWSStationProperties(
                    stationIdentifier: "KIND",
                    name: "Indianapolis International Airport"
                ),
                observation: observation,
                fetchedAt: now,
                now: now
            )
        )

        XCTAssertEqual(mapped.temperature, 68, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(mapped.apparentTemperature), 69.8, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(mapped.dewPoint), 50, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(mapped.humidity), 0.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(mapped.windSpeed), 22.369, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(mapped.windGust), 33.554, accuracy: 0.01)
        XCTAssertEqual(mapped.windDirection, "SW")
        XCTAssertEqual(try XCTUnwrap(mapped.visibilityMiles), 10, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(mapped.pressureMillibars), 1_013.25, accuracy: 0.01)
        XCTAssertEqual(mapped.condition, .partlyCloudy)
        XCTAssertEqual(mapped.source.provider, .nwsObservation)
    }

    func testStaleObservationIsRejected() throws {
        let now = try XCTUnwrap(NWSParsing.date("2026-09-19T23:00:00Z"))
        let observation = NWSObservationResponse(
            properties: NWSObservationProperties(
                stationId: "KOLD",
                stationName: "Old Station",
                timestamp: "2026-09-19T20:00:00Z",
                textDescription: "Clear",
                temperature: qv("unit:degC", 20),
                dewpoint: nil,
                windDirection: nil,
                windSpeed: nil,
                windGust: nil,
                barometricPressure: nil,
                visibility: nil,
                relativeHumidity: nil,
                windChill: nil,
                heatIndex: nil
            )
        )

        XCTAssertNil(
            NWSMapper.currentConditions(
                station: NWSStationProperties(
                    stationIdentifier: "KOLD",
                    name: "Old Station"
                ),
                observation: observation,
                fetchedAt: now,
                now: now
            )
        )
    }

    func testHourlyForecastUsesProviderPeriodAndGridValues() throws {
        let fetchedAt = try XCTUnwrap(NWSParsing.date("2026-09-19T21:00:00Z"))
        let period = forecastPeriod(
            number: 1,
            name: "",
            start: "2026-09-19T18:00:00-04:00",
            end: "2026-09-19T19:00:00-04:00",
            isDaytime: true,
            temperature: .quantity(qv("wmoUnit:degC", 20)),
            temperatureUnit: nil,
            precipitation: qv("wmoUnit:percent", 30),
            dewpoint: qv("wmoUnit:degC", 10),
            humidity: qv("wmoUnit:percent", 50),
            windSpeed: .quantity(qv("wmoUnit:km_h-1", 16.09344)),
            windGust: nil,
            windDirection: "SW",
            shortForecast: "Partly Cloudy",
            detailedForecast: ""
        )

        let response = NWSForecastResponse(
            properties: NWSForecastProperties(
                updated: nil,
                generatedAt: "2026-09-19T21:00:00Z",
                updateTime: nil,
                periods: [period]
            )
        )

        let grid = NWSGridpointProperties(
            updateTime: "2026-09-19T21:00:00Z",
            validTimes: nil,
            apparentTemperature: series(
                "wmoUnit:degC",
                "2026-09-19T18:00:00-04:00/PT1H",
                22
            ),
            windSpeed: nil,
            windGust: series(
                "wmoUnit:km_h-1",
                "2026-09-19T18:00:00-04:00/PT1H",
                32.18688
            ),
            relativeHumidity: nil,
            dewpoint: nil
        )

        let item = try XCTUnwrap(
            NWSMapper.hourlyForecast(
                response: response,
                grid: grid,
                sourceName: "NWS IND forecast grid",
                fetchedAt: fetchedAt
            ).first
        )

        XCTAssertEqual(item.temperature, 68, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(item.apparentTemperature), 71.6, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(item.dewPoint), 50, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(item.humidity), 0.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(item.windSpeed), 10, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(item.windGust), 20, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(item.precipitationChance), 0.3, accuracy: 0.001)
        XCTAssertEqual(item.condition, .partlyCloudy)
    }

    func testDailyForecastKeepsTonightOnlyDayWithoutInventingHigh() throws {
        let fetchedAt = try XCTUnwrap(NWSParsing.date("2026-09-19T22:00:00Z"))

        let tonight = forecastPeriod(
            number: 1,
            name: "Tonight",
            start: "2026-09-19T18:00:00-04:00",
            end: "2026-09-20T06:00:00-04:00",
            isDaytime: false,
            temperature: .number(61),
            temperatureUnit: "F",
            precipitation: qv("wmoUnit:percent", 20),
            dewpoint: nil,
            humidity: nil,
            windSpeed: .text("5 mph"),
            windGust: nil,
            windDirection: "SW",
            shortForecast: "Partly Cloudy",
            detailedForecast: "Partly cloudy overnight."
        )

        let tomorrow = forecastPeriod(
            number: 2,
            name: "Sunday",
            start: "2026-09-20T06:00:00-04:00",
            end: "2026-09-20T18:00:00-04:00",
            isDaytime: true,
            temperature: .number(79),
            temperatureUnit: "F",
            precipitation: qv("wmoUnit:percent", 10),
            dewpoint: nil,
            humidity: nil,
            windSpeed: .text("7 mph"),
            windGust: nil,
            windDirection: "W",
            shortForecast: "Mostly Sunny",
            detailedForecast: "Mostly sunny."
        )

        let tomorrowNight = forecastPeriod(
            number: 3,
            name: "Sunday Night",
            start: "2026-09-20T18:00:00-04:00",
            end: "2026-09-21T06:00:00-04:00",
            isDaytime: false,
            temperature: .number(62),
            temperatureUnit: "F",
            precipitation: qv("wmoUnit:percent", 15),
            dewpoint: nil,
            humidity: nil,
            windSpeed: .text("4 mph"),
            windGust: nil,
            windDirection: "W",
            shortForecast: "Mostly Clear",
            detailedForecast: "Mostly clear."
        )

        let response = NWSForecastResponse(
            properties: NWSForecastProperties(
                updated: nil,
                generatedAt: "2026-09-19T22:00:00Z",
                updateTime: nil,
                periods: [tonight, tomorrow, tomorrowNight]
            )
        )

        let days = NWSMapper.dailyForecast(
            response: response,
            timeZoneIdentifier: "America/Indiana/Indianapolis",
            sourceName: "NWS IND forecast grid",
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(days.count, 2)
        XCTAssertNil(days[0].daytimeHigh)
        XCTAssertEqual(days[0].overnightLow, 61)
        XCTAssertEqual(days[0].nighttimePrecipitationChance, 0.2)
        XCTAssertEqual(days[0].nighttimeCondition, .partlyCloudy)
        XCTAssertEqual(days[0].nighttimeWindDescription, "SW 5 mph")
        XCTAssertEqual(days[1].daytimeHigh, 79)
        XCTAssertEqual(days[1].overnightLow, 62)
        XCTAssertEqual(days[1].windDescription, "W 7 mph")
        XCTAssertEqual(days[1].nighttimeWindDescription, "W 4 mph")
        XCTAssertEqual(days[1].nighttimeCondition, .mostlyClear)
    }

    func testAlertsPreserveOfficialTextAndSortBySeverity() throws {
        let fetchedAt = try XCTUnwrap(NWSParsing.date("2026-09-19T22:00:00Z"))
        let collection = NWSAlertCollection(
            features: [
                alertFeature(id: "minor", event: "Flood Advisory", severity: "Minor"),
                alertFeature(id: "severe", event: "Tornado Warning", severity: "Severe")
            ]
        )

        let alerts = NWSMapper.alerts(
            collection: collection,
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(alerts.map(\.id), ["severe", "minor"])
        XCTAssertEqual(alerts[0].description, "Official description.")
        XCTAssertEqual(alerts[0].instructions, "Official instructions.")
        XCTAssertEqual(alerts[0].severity, .severe)
    }

    private func qv(_ unit: String, _ value: Double?) -> NWSQuantitativeValue {
        NWSQuantitativeValue(unitCode: unit, value: value)
    }

    private func series(
        _ unit: String,
        _ validTime: String,
        _ value: Double
    ) -> NWSGridValueSeries {
        NWSGridValueSeries(
            uom: unit,
            values: [
                NWSGridValue(validTime: validTime, value: value)
            ]
        )
    }

    private func forecastPeriod(
        number: Int,
        name: String,
        start: String,
        end: String,
        isDaytime: Bool,
        temperature: NWSForecastMeasurement?,
        temperatureUnit: String?,
        precipitation: NWSQuantitativeValue?,
        dewpoint: NWSQuantitativeValue?,
        humidity: NWSQuantitativeValue?,
        windSpeed: NWSForecastMeasurement?,
        windGust: NWSForecastMeasurement?,
        windDirection: String?,
        shortForecast: String?,
        detailedForecast: String?
    ) -> NWSForecastPeriod {
        NWSForecastPeriod(
            number: number,
            name: name,
            startTime: start,
            endTime: end,
            isDaytime: isDaytime,
            temperature: temperature,
            temperatureUnit: temperatureUnit,
            probabilityOfPrecipitation: precipitation,
            dewpoint: dewpoint,
            relativeHumidity: humidity,
            windSpeed: windSpeed,
            windGust: windGust,
            windDirection: windDirection,
            shortForecast: shortForecast,
            detailedForecast: detailedForecast
        )
    }

    private func alertFeature(
        id: String,
        event: String,
        severity: String
    ) -> NWSAlertFeature {
        NWSAlertFeature(
            id: id,
            properties: NWSAlertProperties(
                event: event,
                headline: "\(event) headline",
                description: "Official description.",
                instruction: "Official instructions.",
                severity: severity,
                sent: "2026-09-19T21:55:00Z",
                effective: "2026-09-19T22:00:00Z",
                expires: "2026-09-20T00:00:00Z",
                senderName: "NWS Indianapolis IN"
            )
        )
    }
}
