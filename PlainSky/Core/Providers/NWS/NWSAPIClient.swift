import Foundation

struct NWSAPIClient {
    private let httpClient: any HTTPClient
    private let decoder: JSONDecoder
    private let baseURL = URL(string: "https://api.weather.gov")!

    init(httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.httpClient = httpClient
        self.decoder = JSONDecoder()
    }

    func point(for location: WeatherLocation) async throws -> NWSPointResponse {
        let path = "/points/\(location.latitude),\(location.longitude)"
        return try await fetch(url: try makeURL(path: path))
    }

    func forecast(url: URL) async throws -> NWSForecastResponse {
        try await fetch(
            url: url,
            queryItems: [URLQueryItem(name: "units", value: "us")],
            headers: [
                "Feature-Flags": "forecast_temperature_qv,forecast_wind_speed_qv"
            ]
        )
    }

    func hourlyForecast(url: URL) async throws -> NWSForecastResponse {
        try await fetch(
            url: url,
            queryItems: [URLQueryItem(name: "units", value: "us")],
            headers: [
                "Feature-Flags": "forecast_temperature_qv,forecast_wind_speed_qv"
            ]
        )
    }

    func gridData(url: URL) async throws -> NWSGridpointResponse {
        try await fetch(url: url)
    }

    func stations(url: URL) async throws -> NWSFeatureCollection<NWSStationProperties> {
        try await fetch(url: url)
    }

    func latestObservation(stationIdentifier: String) async throws -> NWSObservationResponse {
        let encoded = stationIdentifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? stationIdentifier

        return try await fetch(
            url: try makeURL(path: "/stations/\(encoded)/observations/latest"),
            queryItems: [URLQueryItem(name: "require_qc", value: "true")]
        )
    }

    func activeAlerts(for location: WeatherLocation) async throws -> NWSAlertCollection {
        try await fetch(
            url: try makeURL(path: "/alerts/active"),
            queryItems: [
                URLQueryItem(
                    name: "point",
                    value: "\(location.latitude),\(location.longitude)"
                )
            ]
        )
    }

    private func fetch<Response: Decodable>(
        url: URL,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:]
    ) async throws -> Response {
        let request = try makeRequest(
            url: url,
            queryItems: queryItems,
            headers: headers
        )
        let (data, _) = try await httpClient.data(for: request)

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw ProviderError.decoding(error.localizedDescription)
        }
    }

    private func makeURL(path: String) throws -> URL {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw ProviderError.invalidURL
        }
        return url
    }

    private func makeRequest(
        url: URL,
        queryItems: [URLQueryItem],
        headers: [String: String]
    ) throws -> URLRequest {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw ProviderError.invalidURL
        }

        if !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }

        guard let finalURL = components.url else {
            throw ProviderError.invalidURL
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(
            "PlainSky/0.1 (https://github.com/ColumbusLabs/PlainSky)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")

        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        return request
    }
}
