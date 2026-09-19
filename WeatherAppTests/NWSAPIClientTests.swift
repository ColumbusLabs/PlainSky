import XCTest
@testable import WeatherApp

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
                .contains("ColumbusLabs/The-Weather-App") == true
        )
    }

    func testForecastRequestExplicitlyRequestsUSUnits() async throws {
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
    }
}

private final class CapturingHTTPClient: HTTPClient {
    private let responseData: Data
    private(set) var lastRequest: URLRequest?

    init(data: Data) {
        self.responseData = data
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!

        return (responseData, response)
    }
}
