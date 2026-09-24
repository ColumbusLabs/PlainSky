import XCTest
@testable import PlainSky

final class NWSAPIClientTests: XCTestCase {
    func testPointRequestUsesCoordinatesAndIdentifyingUserAgent() async throws {
        let http = CapturingHTTPClient(
            data: Data(
                """
                {
                  "properties": {
                    "gridId": "IND",
                    "gridX": 42,
                    "gridY": 55,
                    "forecast": "https://api.weather.gov/gridpoints/IND/42,55/forecast",
                    "forecastHourly": "https://api.weather.gov/gridpoints/IND/42,55/forecast/hourly",
                    "forecastGridData": "https://api.weather.gov/gridpoints/IND/42,55",
                    "observationStations": "https://api.weather.gov/gridpoints/IND/42,55/stations"
                  }
                }
                """.utf8
            )
        )
        let client = NWSAPIClient(httpClient: http)
        let location = WeatherLocation(
            name: "Test",
            region: "Indiana",
            latitude: 39.7684,
            longitude: -86.1581
        )

        let response = try await client.point(for: location)

        XCTAssertEqual(response.properties.gridId, "IND")
        XCTAssertEqual(
            http.lastRequest?.url?.absoluteString,
            "https://api.weather.gov/points/39.7684,-86.1581"
        )
        XCTAssertEqual(
            http.lastRequest?.value(forHTTPHeaderField: "Accept"),
            "application/geo+json"
        )
        XCTAssertTrue(
            http.lastRequest?
                .value(forHTTPHeaderField: "User-Agent")?
                .contains("ColumbusLabs/PlainSky") == true
        )
    }

    func testForecastRequestUsesCanonicalUSUnits() async throws {
        let http = CapturingHTTPClient(
            data: Data(
                """
                {
                  "properties": {
                    "updated": null,
                    "generatedAt": null,
                    "periods": []
                  }
                }
                """.utf8
            )
        )
        let client = NWSAPIClient(httpClient: http)
        let url = try XCTUnwrap(
            URL(string: "https://api.weather.gov/gridpoints/IND/42,55/forecast")
        )

        _ = try await client.forecast(url: url)

        let components = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(http.lastRequest?.url), resolvingAgainstBaseURL: false)
        )
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "units" })?.value,
            "us"
        )
        XCTAssertEqual(
            http.lastRequest?.value(forHTTPHeaderField: "Feature-Flags"),
            "forecast_temperature_qv,forecast_wind_speed_qv"
        )
    }

    func testRefreshContextForcesProtocolRevalidation() async throws {
        let http = CapturingHTTPClient(data: Data(
            """
            {
              "properties": {
                "gridId": "IND",
                "gridX": 42,
                "gridY": 55,
                "forecast": "https://api.weather.gov/gridpoints/IND/42,55/forecast",
                "forecastHourly": "https://api.weather.gov/gridpoints/IND/42,55/forecast/hourly",
                "forecastGridData": "https://api.weather.gov/gridpoints/IND/42,55",
                "observationStations": "https://api.weather.gov/gridpoints/IND/42,55/stations"
              }
            }
            """.utf8
        ))
        let client = NWSAPIClient(httpClient: http)
        let location = WeatherLocation(name: "Test", region: "IN", latitude: 39, longitude: -86)
        let refresh = WeatherRefreshContext(location: location)

        _ = try await client.point(
            for: location,
            context: refresh.requestContext(for: .routingMetadata)
        )

        XCTAssertEqual(http.lastRequest?.cachePolicy, .reloadRevalidatingCacheData)
    }
}

private final class CapturingHTTPClient: HTTPClient, @unchecked Sendable {
    private let responseData: Data
    private let lock = NSLock()
    private var lastRequestStorage: URLRequest?

    var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return lastRequestStorage
    }

    init(data: Data) {
        self.responseData = data
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock()
        lastRequestStorage = request
        lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!

        return (responseData, response)
    }
}
