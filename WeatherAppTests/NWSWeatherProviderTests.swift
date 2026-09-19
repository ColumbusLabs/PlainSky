import XCTest
@testable import WeatherApp

@MainActor
final class NWSWeatherProviderTests: XCTestCase {
    func testProviderBuildsPrimaryPayloadAndSkipsStaleNearestStation() async throws {
        let now = try XCTUnwrap(NWSParsing.date("2026-09-19T23:00:00Z"))
        let client = NWSAPIClient(
            httpClient: RoutingNWSHTTPClient(fixtures: Self.fixtures)
        )
        let provider = NWSWeatherProvider(
            client: client,
            now: { now }
        )

        let payload = try await provider.weather(
            for: WeatherLocation(
                name: "Indianapolis",
                region: "Indiana",
                latitude: 39.7684,
                longitude: -86.1581
            )
        )

        XCTAssertEqual(payload.current?.source.sourceName, "Fresh Station (KFRESH)")
        XCTAssertEqual(payload.current?.temperature, 68, accuracy: 0.01)
        XCTAssertEqual(payload.hourly.count, 1)
        XCTAssertEqual(payload.hourly[0].apparentTemperature, 71.6, accuracy: 0.01)
        XCTAssertEqual(payload.daily.count, 1)
        XCTAssertEqual(payload.daily[0].daytimeHigh, 79)
        XCTAssertEqual(payload.daily[0].overnightLow, 61)
        XCTAssertEqual(payload.alerts.map(\.event), ["Tornado Warning"])
        XCTAssertEqual(payload.availability[.currentConditions], .available)
        XCTAssertEqual(payload.availability[.hourlyForecast], .available)
        XCTAssertEqual(payload.availability[.dailyForecast], .available)
        XCTAssertEqual(payload.availability[.alerts], .available)
    }

    func testAlertFailureDoesNotEraseForecast() async throws {
        let now = try XCTUnwrap(NWSParsing.date("2026-09-19T23:00:00Z"))
        var fixtures = Self.fixtures
        fixtures["/alerts/active"] = .status(500)

        let provider = NWSWeatherProvider(
            client: NWSAPIClient(
                httpClient: RoutingNWSHTTPClient(fixtures: fixtures)
            ),
            now: { now }
        )

        let payload = try await provider.weather(
            for: WeatherLocation(
                name: "Indianapolis",
                region: "Indiana",
                latitude: 39.7684,
                longitude: -86.1581
            )
        )

        XCTAssertFalse(payload.hourly.isEmpty)
        XCTAssertFalse(payload.daily.isEmpty)
        XCTAssertTrue(payload.alerts.isEmpty)

        guard case .unavailable = payload.availability[.alerts] else {
            return XCTFail("Expected alerts to retain unavailable state.")
        }
    }

    private static let fixtures: [String: RoutingNWSHTTPClient.Fixture] = [
        "/points/39.7684,-86.1581": .json(
            """
            {
              "properties": {
                "gridId": "IND",
                "gridX": 42,
                "gridY": 55,
                "forecast": "https://api.weather.gov/gridpoints/IND/42,55/forecast",
                "forecastHourly": "https://api.weather.gov/gridpoints/IND/42,55/forecast/hourly",
                "forecastGridData": "https://api.weather.gov/gridpoints/IND/42,55",
                "observationStations": "https://api.weather.gov/gridpoints/IND/42,55/stations",
                "timeZone": "America/Indiana/Indianapolis"
              }
            }
            """
        ),
        "/gridpoints/IND/42,55/forecast": .json(
            """
            {
              "properties": {
                "generatedAt": "2026-09-19T22:00:00Z",
                "periods": [
                  {
                    "number": 1,
                    "name": "This Afternoon",
                    "startTime": "2026-09-19T14:00:00-04:00",
                    "endTime": "2026-09-19T18:00:00-04:00",
                    "isDaytime": true,
                    "temperature": {"unitCode":"wmoUnit:degF","value":79},
                    "temperatureUnit": null,
                    "probabilityOfPrecipitation": {"unitCode":"wmoUnit:percent","value":10},
                    "dewpoint": null,
                    "relativeHumidity": null,
                    "windSpeed": {"unitCode":"wmoUnit:mi_h-1","value":7},
                    "windGust": null,
                    "windDirection": "W",
                    "shortForecast": "Mostly Sunny",
                    "detailedForecast": "Mostly sunny, with a high near 79."
                  },
                  {
                    "number": 2,
                    "name": "Tonight",
                    "startTime": "2026-09-19T18:00:00-04:00",
                    "endTime": "2026-09-20T06:00:00-04:00",
                    "isDaytime": false,
                    "temperature": {"unitCode":"wmoUnit:degF","value":61},
                    "temperatureUnit": null,
                    "probabilityOfPrecipitation": {"unitCode":"wmoUnit:percent","value":20},
                    "dewpoint": null,
                    "relativeHumidity": null,
                    "windSpeed": {"unitCode":"wmoUnit:mi_h-1","value":5},
                    "windGust": null,
                    "windDirection": "SW",
                    "shortForecast": "Partly Cloudy",
                    "detailedForecast": "Partly cloudy, with a low around 61."
                  }
                ]
              }
            }
            """
        ),
        "/gridpoints/IND/42,55/forecast/hourly": .json(
            """
            {
              "properties": {
                "generatedAt": "2026-09-19T22:00:00Z",
                "periods": [
                  {
                    "number": 1,
                    "name": "",
                    "startTime": "2026-09-19T18:00:00-04:00",
                    "endTime": "2026-09-19T19:00:00-04:00",
                    "isDaytime": false,
                    "temperature": {"unitCode":"wmoUnit:degF","value":74},
                    "temperatureUnit": null,
                    "probabilityOfPrecipitation": {"unitCode":"wmoUnit:percent","value":20},
                    "dewpoint": {"unitCode":"wmoUnit:degC","value":15},
                    "relativeHumidity": {"unitCode":"wmoUnit:percent","value":55},
                    "windSpeed": {"unitCode":"wmoUnit:mi_h-1","value":8},
                    "windGust": null,
                    "windDirection": "SW",
                    "shortForecast": "Partly Cloudy",
                    "detailedForecast": ""
                  }
                ]
              }
            }
            """
        ),
        "/gridpoints/IND/42,55": .json(
            """
            {
              "properties": {
                "updateTime": "2026-09-19T22:00:00Z",
                "apparentTemperature": {
                  "uom": "wmoUnit:degC",
                  "values": [
                    {"validTime":"2026-09-19T18:00:00-04:00/PT1H","value":22}
                  ]
                },
                "windSpeed": {
                  "uom": "wmoUnit:km_h-1",
                  "values": [
                    {"validTime":"2026-09-19T18:00:00-04:00/PT1H","value":12.874752}
                  ]
                },
                "windGust": {
                  "uom": "wmoUnit:km_h-1",
                  "values": [
                    {"validTime":"2026-09-19T18:00:00-04:00/PT1H","value":24.14016}
                  ]
                },
                "relativeHumidity": {
                  "uom": "wmoUnit:percent",
                  "values": [
                    {"validTime":"2026-09-19T18:00:00-04:00/PT1H","value":55}
                  ]
                },
                "dewpoint": {
                  "uom": "wmoUnit:degC",
                  "values": [
                    {"validTime":"2026-09-19T18:00:00-04:00/PT1H","value":15}
                  ]
                }
              }
            }
            """
        ),
        "/gridpoints/IND/42,55/stations": .json(
            """
            {
              "features": [
                {"properties":{"stationIdentifier":"KSTALE","name":"Stale Station"}},
                {"properties":{"stationIdentifier":"KFRESH","name":"Fresh Station"}}
              ]
            }
            """
        ),
        "/stations/KSTALE/observations/latest": .json(
            observationJSON(
                stationId: "KSTALE",
                stationName: "Stale Station",
                timestamp: "2026-09-19T20:00:00Z"
            )
        ),
        "/stations/KFRESH/observations/latest": .json(
            observationJSON(
                stationId: "KFRESH",
                stationName: "Fresh Station",
                timestamp: "2026-09-19T22:40:00Z"
            )
        ),
        "/alerts/active": .json(
            """
            {
              "features": [
                {
                  "id": "alert-1",
                  "properties": {
                    "event": "Tornado Warning",
                    "headline": "Tornado Warning issued by NWS Indianapolis IN",
                    "description": "Official warning text.",
                    "instruction": "Official safety instructions.",
                    "severity": "Severe",
                    "sent": "2026-09-19T22:45:00Z",
                    "effective": "2026-09-19T22:45:00Z",
                    "expires": "2026-09-19T23:30:00Z",
                    "senderName": "NWS Indianapolis IN"
                  }
                }
              ]
            }
            """
        )
    ]

    private static func observationJSON(
        stationId: String,
        stationName: String,
        timestamp: String
    ) -> String {
        """
        {
          "properties": {
            "stationId": "\(stationId)",
            "stationName": "\(stationName)",
            "timestamp": "\(timestamp)",
            "textDescription": "Partly Cloudy",
            "temperature": {"unitCode":"unit:degC","value":20},
            "dewpoint": {"unitCode":"unit:degC","value":10},
            "windDirection": {"unitCode":"unit:degree_(angle)","value":225},
            "windSpeed": {"unitCode":"unit:m_s-1","value":4},
            "windGust": {"unitCode":"unit:m_s-1","value":6},
            "barometricPressure": {"unitCode":"unit:Pa","value":101325},
            "visibility": {"unitCode":"unit:m","value":16093.44},
            "relativeHumidity": {"unitCode":"unit:percent","value":50},
            "windChill": {"unitCode":"unit:degC","value":null},
            "heatIndex": {"unitCode":"unit:degC","value":21}
          }
        }
        """
    }
}

private struct RoutingNWSHTTPClient: HTTPClient {
    enum Fixture {
        case json(String)
        case status(Int)
    }

    let fixtures: [String: Fixture]

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else {
            throw ProviderError.invalidURL
        }

        let fixture = fixtures[url.path] ?? .status(404)

        switch fixture {
        case let .json(json):
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            return (Data(json.utf8), response)

        case let .status(code):
            throw ProviderError.httpStatus(code)
        }
    }
}
