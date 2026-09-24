import XCTest
@testable import PlainSky

@MainActor
final class NWSWeatherProviderTests: XCTestCase {
    func testProviderBuildsPrimaryPayloadAndSkipsStaleNearestStation() async throws {
        let now = try XCTUnwrap(NWSParsing.date("2026-09-19T22:50:00Z"))
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

        let current = try XCTUnwrap(payload.current)
        XCTAssertEqual(current.source.sourceName, "Fresh Station (KFRESH)")
        XCTAssertEqual(current.temperature, 68, accuracy: 0.01)
        XCTAssertEqual(payload.hourly.count, 1)
        XCTAssertEqual(
            try XCTUnwrap(payload.hourly[0].apparentTemperature),
            71.6,
            accuracy: 0.01
        )
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
        let now = try XCTUnwrap(NWSParsing.date("2026-09-19T22:50:00Z"))
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

    func testStaleGridRoutesAreReResolvedOnceAndAffectedProductsRetry() async throws {
        let now = try XCTUnwrap(NWSParsing.date("2026-09-19T22:50:00Z"))
        let httpClient = RotatingRouteNWSHTTPClient(fixtures: Self.fixtures)
        let provider = NWSWeatherProvider(
            client: NWSAPIClient(httpClient: httpClient),
            metadataCache: NWSLocationMetadataCache(fileURL: nil),
            now: { now }
        )
        let location = WeatherLocation(
            name: "Indianapolis",
            region: "Indiana",
            latitude: 39.7684,
            longitude: -86.1581
        )
        let recorder = NWSUpdatesRecorder()
        let context = WeatherRefreshContext(location: location, now: now)

        try await provider.updates(
            for: location,
            context: context,
            onUpdate: { update in recorder.record(update) }
        )

        let pointRequestCount = await httpClient.pointRequestCount
        XCTAssertEqual(pointRequestCount, 2, "A stale route should trigger one /points re-resolution.")
        let updates = recorder.updates
        XCTAssertTrue(updates.contains { update in
            guard case let .daily(.available(_, metadata)) = update.event else { return false }
            return metadata.sourceRevision == "IND:42:55"
        })
        XCTAssertTrue(updates.contains { update in
            guard case let .hourly(.available(_, metadata)) = update.event else { return false }
            return metadata.sourceRevision == "IND:42:55"
        })
        XCTAssertTrue(updates.contains { update in
            guard case let .current(.available(_, metadata)) = update.event else { return false }
            return metadata.sourceRevision == "IND:42:55"
        })
    }

    func testForecastsDeliveredOnSupersededRouteAreRefetchedOnNewRoute() async throws {
        // Only the old hourly route is gone. The old daily, grid, and station
        // routes still answer, so their results must not survive the remap.
        let now = try XCTUnwrap(NWSParsing.date("2026-09-19T22:50:00Z"))
        let httpClient = RotatingRouteNWSHTTPClient(
            fixtures: Self.fixtures,
            staleRoutePaths: ["/gridpoints/OLD/1,2/forecast/hourly"]
        )
        let provider = NWSWeatherProvider(
            client: NWSAPIClient(httpClient: httpClient),
            metadataCache: NWSLocationMetadataCache(fileURL: nil),
            now: { now }
        )
        let location = WeatherLocation(
            name: "Indianapolis",
            region: "Indiana",
            latitude: 39.7684,
            longitude: -86.1581
        )
        let recorder = NWSUpdatesRecorder()

        try await provider.updates(
            for: location,
            context: WeatherRefreshContext(location: location, now: now),
            onUpdate: { update in recorder.record(update) }
        )

        let pointRequestCount = await httpClient.pointRequestCount
        XCTAssertEqual(pointRequestCount, 2)
        let updates = recorder.updates
        let routeRevisions = updates.compactMap { update -> String? in
            guard case let .routeRevision(revision, _) = update.event else { return nil }
            return revision
        }
        XCTAssertEqual(routeRevisions, ["OLD:1:2", "IND:42:55"])

        let dailyRevisions = updates.compactMap { update -> String? in
            guard case .daily = update.event else { return nil }
            return update.sourceRevision
        }
        XCTAssertEqual(dailyRevisions.last, "IND:42:55", "Daily must end on the current route.")

        let hourlyUpdates = updates.filter { update in
            guard case .hourly(.available) = update.event else { return false }
            return true
        }
        XCTAssertFalse(hourlyUpdates.isEmpty)
        XCTAssertTrue(
            hourlyUpdates.allSatisfy { $0.sourceRevision == "IND:42:55" },
            "Hourly data and its grid enrichment must come from the same route."
        )
    }

    func testCoordinateAlertsPublishWhilePointResolutionIsBlockedAndFails() async throws {
        let now = try XCTUnwrap(NWSParsing.date("2026-09-19T22:50:00Z"))
        let pointsPath = "/points/39.7684,-86.1581"
        var fixtures = Self.fixtures
        fixtures[pointsPath] = .status(500)
        let httpClient = GatedRoutingNWSHTTPClient(
            fixtures: fixtures,
            gatedPaths: [pointsPath]
        )
        let provider = NWSWeatherProvider(
            client: NWSAPIClient(httpClient: httpClient),
            now: { now }
        )
        let location = WeatherLocation(
            name: "Indianapolis",
            region: "Indiana",
            latitude: 39.7684,
            longitude: -86.1581
        )
        let alertExpectation = expectation(description: "Coordinate alerts publish")
        let alertProbe = NWSUpdateProbe(expectation: alertExpectation) { update in
            guard case let .alerts(.available(alerts, _)) = update.event else {
                return false
            }
            return !alerts.isEmpty
        }
        let context = WeatherRefreshContext(location: location, now: now)

        let updatesTask = Task {
            try await provider.updates(
                for: location,
                context: context,
                onUpdate: { update in alertProbe.receive(update) }
            )
        }

        await httpClient.waitUntilRequested(pointsPath)
        await fulfillment(of: [alertExpectation], timeout: 5)

        let pointsWereStillBlocked = await !httpClient.isReleased(pointsPath)
        XCTAssertTrue(pointsWereStillBlocked, "The alert update must not depend on /points completing.")
        let alertUpdate = try XCTUnwrap(alertProbe.update)
        guard case let .alerts(.available(alerts, _)) = alertUpdate.event else {
            return XCTFail("Expected an available coordinate-based alert update.")
        }
        XCTAssertEqual(alerts.map(\.event), ["Tornado Warning"])

        await httpClient.release(pointsPath)
        try await updatesTask.value
    }

    func testCurrentDeadlinePublishesUnavailableWhilePointResolutionIsBlocked() async throws {
        let now = try XCTUnwrap(NWSParsing.date("2026-09-19T22:50:00Z"))
        let pointsPath = "/points/39.7684,-86.1581"
        let httpClient = GatedRoutingNWSHTTPClient(
            fixtures: Self.fixtures,
            gatedPaths: [pointsPath]
        )
        let provider = NWSWeatherProvider(
            client: NWSAPIClient(httpClient: httpClient),
            now: { now }
        )
        let location = WeatherLocation(
            name: "Indianapolis",
            region: "Indiana",
            latitude: 39.7684,
            longitude: -86.1581
        )
        let currentDeadlineExpectation = expectation(description: "Current deadline publishes unavailable")
        let currentDeadlineProbe = NWSUpdateProbe(expectation: currentDeadlineExpectation) { update in
            guard case .current(.unavailable) = update.event else { return false }
            return true
        }
        let context = WeatherRefreshContext(
            location: location,
            now: now,
            requestBudgets: WeatherRequestBudgets(current: .milliseconds(50))
        )

        let updatesTask = Task {
            try await provider.updates(
                for: location,
                context: context,
                onUpdate: { update in currentDeadlineProbe.receive(update) }
            )
        }

        await httpClient.waitUntilRequested(pointsPath)
        await fulfillment(of: [currentDeadlineExpectation], timeout: 5)

        let pointResolutionWasStillBlocked = await !httpClient.isReleased(pointsPath)
        XCTAssertTrue(
            pointResolutionWasStillBlocked,
            "The current-product deadline must publish while routing is still blocked."
        )
        guard let update = currentDeadlineProbe.update,
              case .current(.unavailable) = update.event else {
            return XCTFail("Expected the current product to time out independently.")
        }

        await httpClient.release(pointsPath)
        try await updatesTask.value
    }

    func testBaseHourlyPublishesBeforeGridEnrichmentCompletes() async throws {
        let now = try XCTUnwrap(NWSParsing.date("2026-09-19T22:50:00Z"))
        let gridPath = "/gridpoints/IND/42,55"
        let httpClient = GatedRoutingNWSHTTPClient(
            fixtures: Self.fixtures,
            gatedPaths: [gridPath]
        )
        let provider = NWSWeatherProvider(
            client: NWSAPIClient(httpClient: httpClient),
            now: { now }
        )
        let location = WeatherLocation(
            name: "Indianapolis",
            region: "Indiana",
            latitude: 39.7684,
            longitude: -86.1581
        )
        let baseHourlyExpectation = expectation(description: "Base hourly publishes")
        let baseHourlyProbe = NWSUpdateProbe(expectation: baseHourlyExpectation) { update in
            guard case let .hourly(.available(items, _)) = update.event else {
                return false
            }
            return items.first?.apparentTemperature == nil
        }
        let enrichedHourlyExpectation = expectation(description: "Grid-enriched hourly publishes")
        let enrichedHourlyProbe = NWSUpdateProbe(expectation: enrichedHourlyExpectation) { update in
            guard case let .hourly(.available(items, _)) = update.event else {
                return false
            }
            return items.first?.apparentTemperature != nil
        }
        let context = WeatherRefreshContext(location: location, now: now)

        let updatesTask = Task {
            try await provider.updates(
                for: location,
                context: context,
                onUpdate: { update in
                    baseHourlyProbe.receive(update)
                    enrichedHourlyProbe.receive(update)
                }
            )
        }

        await httpClient.waitUntilRequested(gridPath)
        await fulfillment(of: [baseHourlyExpectation], timeout: 5)

        let gridWasStillBlocked = await !httpClient.isReleased(gridPath)
        XCTAssertTrue(gridWasStillBlocked, "Base hourly conditions should publish while grid enrichment is pending.")
        let baseHourlyUpdate = try XCTUnwrap(baseHourlyProbe.update)
        guard case let .hourly(.available(baseItems, _)) = baseHourlyUpdate.event else {
            return XCTFail("Expected base hourly conditions to be available.")
        }
        XCTAssertNil(baseItems.first?.apparentTemperature)

        await httpClient.release(gridPath)
        await fulfillment(of: [enrichedHourlyExpectation], timeout: 5)
        let enrichedHourlyUpdate = try XCTUnwrap(enrichedHourlyProbe.update)
        guard case let .hourly(.available(enrichedItems, _)) = enrichedHourlyUpdate.event else {
            return XCTFail("Expected a second, grid-enriched hourly update.")
        }
        XCTAssertEqual(try XCTUnwrap(enrichedItems.first?.apparentTemperature), 71.6, accuracy: 0.01)
        try await updatesTask.value
    }

    func testUsableNearestStationPublishesWhileSecondStationIsBlocked() async throws {
        let now = try XCTUnwrap(NWSParsing.date("2026-09-19T22:50:00Z"))
        let secondStationPath = "/stations/KFAR/observations/latest"
        var fixtures = Self.fixtures
        fixtures["/gridpoints/IND/42,55/stations"] = .json(
            """
            {
              "features": [
                {"properties":{"stationIdentifier":"KNEAR","name":"Nearest Station"}},
                {"properties":{"stationIdentifier":"KFAR","name":"Farther Station"}}
              ]
            }
            """
        )
        fixtures["/stations/KNEAR/observations/latest"] = .json(
            Self.observationJSON(
                stationId: "KNEAR",
                stationName: "Nearest Station",
                timestamp: "2026-09-19T22:40:00Z"
            )
        )
        fixtures[secondStationPath] = .json(
            Self.observationJSON(
                stationId: "KFAR",
                stationName: "Farther Station",
                timestamp: "2026-09-19T22:45:00Z"
            )
        )
        let httpClient = GatedRoutingNWSHTTPClient(
            fixtures: fixtures,
            gatedPaths: [secondStationPath]
        )
        let provider = NWSWeatherProvider(
            client: NWSAPIClient(httpClient: httpClient),
            now: { now }
        )
        let location = WeatherLocation(
            name: "Indianapolis",
            region: "Indiana",
            latitude: 39.7684,
            longitude: -86.1581
        )
        let currentExpectation = expectation(description: "Nearest current observation publishes")
        let currentProbe = NWSUpdateProbe(expectation: currentExpectation) { update in
            guard case let .current(.available(current, _)) = update.event else {
                return false
            }
            return current.source.sourceName?.contains("Nearest Station") == true
        }
        let context = WeatherRefreshContext(location: location, now: now)

        let updatesTask = Task {
            try await provider.updates(
                for: location,
                context: context,
                onUpdate: { update in currentProbe.receive(update) }
            )
        }

        await httpClient.waitUntilRequested(secondStationPath)
        await fulfillment(of: [currentExpectation], timeout: 5)
        let secondStationReleased = await httpClient.isReleased(secondStationPath)
        XCTAssertFalse(secondStationReleased)
        let currentUpdate = try XCTUnwrap(currentProbe.update)
        guard case let .current(.available(current, _)) = currentUpdate.event else {
            return XCTFail("Expected nearest-station current conditions to be available.")
        }
        XCTAssertEqual(current.source.sourceName, "Nearest Station (KNEAR)")

        await httpClient.release(secondStationPath)
        try await updatesTask.value
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
    enum Fixture: Sendable {
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

private actor RotatingRouteNWSHTTPClient: HTTPClient {
    private let fixtures: [String: RoutingNWSHTTPClient.Fixture]
    /// Old-route paths that return 404. When nil, every old-route path does;
    /// otherwise the remaining old-route paths answer with current fixtures.
    private let staleRoutePaths: Set<String>?
    private(set) var pointRequestCount = 0

    init(
        fixtures: [String: RoutingNWSHTTPClient.Fixture],
        staleRoutePaths: Set<String>? = nil
    ) {
        self.fixtures = fixtures
        self.staleRoutePaths = staleRoutePaths
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw ProviderError.invalidURL }

        if url.path == "/points/39.7684,-86.1581" {
            pointRequestCount += 1
            return response(
                RotatingRouteNWSHTTPClient.pointJSON(
                    grid: pointRequestCount == 1 ? "OLD" : "IND",
                    x: pointRequestCount == 1 ? 1 : 42,
                    y: pointRequestCount == 1 ? 2 : 55
                ),
                for: url
            )
        }

        var path = url.path
        if path.hasPrefix("/gridpoints/OLD/") {
            guard let staleRoutePaths, !staleRoutePaths.contains(path) else {
                throw ProviderError.httpStatus(404)
            }
            path = path.replacingOccurrences(of: "/gridpoints/OLD/1,2", with: "/gridpoints/IND/42,55")
        }

        guard case let .json(json) = fixtures[path] else {
            throw ProviderError.httpStatus(404)
        }
        return response(json, for: url)
    }

    private func response(_ json: String, for url: URL) -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(json.utf8), response)
    }

    private static func pointJSON(grid: String, x: Int, y: Int) -> String {
        """
        {
          "properties": {
            "gridId": "\(grid)",
            "gridX": \(x),
            "gridY": \(y),
            "forecast": "https://api.weather.gov/gridpoints/\(grid)/\(x),\(y)/forecast",
            "forecastHourly": "https://api.weather.gov/gridpoints/\(grid)/\(x),\(y)/forecast/hourly",
            "forecastGridData": "https://api.weather.gov/gridpoints/\(grid)/\(x),\(y)",
            "observationStations": "https://api.weather.gov/gridpoints/\(grid)/\(x),\(y)/stations",
            "timeZone": "America/Indiana/Indianapolis"
          }
        }
        """
    }
}

private actor GatedRoutingNWSHTTPClient: HTTPClient {
    private let routing: RoutingNWSHTTPClient
    private let gatedPaths: Set<String>
    private var requestedPaths = Set<String>()
    private var releasedPaths = Set<String>()
    private var requestWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var releaseWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    init(
        fixtures: [String: RoutingNWSHTTPClient.Fixture],
        gatedPaths: Set<String>
    ) {
        routing = RoutingNWSHTTPClient(fixtures: fixtures)
        self.gatedPaths = gatedPaths
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let path = request.url?.path else {
            throw ProviderError.invalidURL
        }

        requestedPaths.insert(path)
        requestWaiters.removeValue(forKey: path)?.forEach { $0.resume() }

        if gatedPaths.contains(path), !releasedPaths.contains(path) {
            await withCheckedContinuation { continuation in
                releaseWaiters[path, default: []].append(continuation)
            }
        }

        return try await routing.data(for: request)
    }

    func waitUntilRequested(_ path: String) async {
        guard !requestedPaths.contains(path) else { return }
        await withCheckedContinuation { continuation in
            requestWaiters[path, default: []].append(continuation)
        }
    }

    func isReleased(_ path: String) -> Bool {
        releasedPaths.contains(path)
    }

    func release(_ path: String) {
        releasedPaths.insert(path)
        releaseWaiters.removeValue(forKey: path)?.forEach { $0.resume() }
    }
}

@MainActor
private final class NWSUpdateProbe {
    private let expectation: XCTestExpectation
    private let matches: (WeatherProductUpdate) -> Bool
    private(set) var update: WeatherProductUpdate?

    init(
        expectation: XCTestExpectation,
        matches: @escaping (WeatherProductUpdate) -> Bool
    ) {
        self.expectation = expectation
        self.matches = matches
    }

    func receive(_ update: WeatherProductUpdate) {
        guard self.update == nil, matches(update) else { return }
        self.update = update
        expectation.fulfill()
    }
}

@MainActor
private final class NWSUpdatesRecorder {
    private(set) var updates: [WeatherProductUpdate] = []

    func record(_ update: WeatherProductUpdate) {
        updates.append(update)
    }
}
