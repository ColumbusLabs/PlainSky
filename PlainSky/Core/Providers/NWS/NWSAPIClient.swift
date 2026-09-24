import Foundation

struct NWSAPIClient: Sendable {
    private let httpClient: any HTTPClient
    private let baseURL = URL(string: "https://api.weather.gov")!

    init(httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.httpClient = httpClient
    }

    func point(
        for location: WeatherLocation,
        context: HTTPRequestContext? = nil
    ) async throws -> NWSPointResponse {
        let path = "/points/\(location.latitude),\(location.longitude)"
        return try await fetch(url: try makeURL(path: path), context: context)
    }

    func pointMetadata(
        for location: WeatherLocation,
        context: HTTPRequestContext? = nil
    ) async throws -> NWSMetadataCacheResult<NWSPointProperties> {
        let path = "/points/\(location.latitude),\(location.longitude)"
        let fetched: (NWSPointResponse, NWSMetadataCachePolicy) = try await fetchWithCachePolicy(
            url: try makeURL(path: path),
            context: context
        )
        let (response, policy) = fetched
        return NWSMetadataCacheResult(value: response.properties, policy: policy)
    }

    func forecast(url: URL, context: HTTPRequestContext? = nil) async throws -> NWSForecastResponse {
        try await fetch(
            url: url,
            queryItems: [URLQueryItem(name: "units", value: "us")],
            headers: [
                "Feature-Flags": "forecast_temperature_qv,forecast_wind_speed_qv"
            ],
            context: context
        )
    }

    func hourlyForecast(url: URL, context: HTTPRequestContext? = nil) async throws -> NWSForecastResponse {
        try await fetch(
            url: url,
            queryItems: [URLQueryItem(name: "units", value: "us")],
            headers: [
                "Feature-Flags": "forecast_temperature_qv,forecast_wind_speed_qv"
            ],
            context: context
        )
    }

    func gridData(url: URL, context: HTTPRequestContext? = nil) async throws -> NWSGridpointResponse {
        try await fetch(url: url, context: context)
    }

    func stations(
        url: URL,
        context: HTTPRequestContext? = nil
    ) async throws -> NWSFeatureCollection<NWSStationProperties> {
        try await fetch(url: url, context: context)
    }

    func stationDirectoryMetadata(
        url: URL,
        context: HTTPRequestContext? = nil
    ) async throws -> NWSMetadataCacheResult<[NWSStationProperties]> {
        let fetched: (NWSFeatureCollection<NWSStationProperties>, NWSMetadataCachePolicy) =
            try await fetchWithCachePolicy(
            url: url,
            context: context
        )
        let (response, policy) = fetched
        return NWSMetadataCacheResult(
            value: response.features.map(\.properties),
            policy: policy
        )
    }

    func latestObservation(
        stationIdentifier: String,
        context: HTTPRequestContext? = nil
    ) async throws -> NWSObservationResponse {
        let encoded = stationIdentifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? stationIdentifier

        return try await fetch(
            url: try makeURL(path: "/stations/\(encoded)/observations/latest"),
            queryItems: [URLQueryItem(name: "require_qc", value: "true")],
            context: context
        )
    }

    func activeAlerts(
        for location: WeatherLocation,
        context: HTTPRequestContext? = nil
    ) async throws -> NWSAlertCollection {
        try await fetch(
            url: try makeURL(path: "/alerts/active"),
            queryItems: [
                URLQueryItem(
                    name: "point",
                    value: "\(location.latitude),\(location.longitude)"
                )
            ],
            context: context
        )
    }

    private func fetch<Response: Decodable & Sendable>(
        url: URL,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        context: HTTPRequestContext? = nil
    ) async throws -> Response {
        let fetched: (Response, NWSMetadataCachePolicy) = try await fetchWithCachePolicy(
            url: url,
            queryItems: queryItems,
            headers: headers,
            context: context
        )
        return fetched.0
    }

    private func fetchWithCachePolicy<Response: Decodable & Sendable>(
        url: URL,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        context: HTTPRequestContext? = nil
    ) async throws -> (Response, NWSMetadataCachePolicy) {
        var request = try makeRequest(
            url: url,
            queryItems: queryItems,
            headers: headers
        )
        if context?.requiresRevalidation == true {
            request.cachePolicy = .reloadRevalidatingCacheData
        }
        let data: Data
        let response: HTTPURLResponse
        if let context {
            (data, response) = try await httpClient.data(for: request, context: context)
        } else {
            (data, response) = try await httpClient.data(for: request)
        }

        do {
            // Each concurrent endpoint decode owns its decoder. JSONDecoder is
            // mutable and must not be shared by sibling provider tasks.
            let value = try WeatherInstrumentation.measure("NWS response decode") {
                try JSONDecoder().decode(Response.self, from: data)
            }
            return (value, NWSMetadataCachePolicy(response: response))
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
        request.cachePolicy = .useProtocolCachePolicy
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
