import Foundation

struct NOAARadarProvider: RadarProviding {
    private let httpClient: any HTTPClient
    private let historyWindow: TimeInterval
    private let maximumFrames: Int

    init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        historyWindow: TimeInterval = 60 * 60,
        maximumFrames: Int = 40
    ) {
        self.httpClient = httpClient
        self.historyWindow = historyWindow
        self.maximumFrames = maximumFrames
    }

    static func supports(location: WeatherLocation) -> Bool {
        let latitude = location.latitude
        let longitude = location.longitude

        return (20...55).contains(latitude) && (-130 ... -60).contains(longitude)
            || (50...72).contains(latitude)
                && ((-180 ... -129).contains(longitude) || (170...180).contains(longitude))
            || (18...23).contains(latitude) && (-161 ... -154).contains(longitude)
            || (17...20).contains(latitude) && (-69 ... -63).contains(longitude)
            || (12...15).contains(latitude) && (143...147).contains(longitude)
    }

    func frames(for location: WeatherLocation) async throws -> [RadarFrame] {
        let configuration = try configuration(for: location)
        let capabilitiesURL = try capabilitiesURL(for: configuration)

        var request = URLRequest(url: capabilitiesURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(
            "PlainSky/0.1 (https://github.com/ColumbusLabs/PlainSky)",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await httpClient.data(for: request)
        let allTimes = try RadarTimeParser.frameTimes(from: data)

        guard let newest = allTimes.last else {
            throw RadarProviderError.noFrameTimes
        }

        let cutoff = newest.addingTimeInterval(-historyWindow)
        let recent = allTimes
            .filter { $0 >= cutoff && $0 <= newest }
            .suffix(maximumFrames)

        guard !recent.isEmpty else {
            throw RadarProviderError.noFrameTimes
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        return recent.map { timestamp in
            RadarFrame(
                id: "\(configuration.layerName)-\(formatter.string(from: timestamp))",
                timestamp: timestamp,
                serviceURL: configuration.serviceURL,
                layerName: configuration.layerName
            )
        }
    }

    private func capabilitiesURL(
        for configuration: RadarServiceConfiguration
    ) throws -> URL {
        guard var components = URLComponents(
            url: configuration.serviceURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw ProviderError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "service", value: "WMS"),
            URLQueryItem(name: "version", value: "1.3.0"),
            URLQueryItem(name: "request", value: "GetCapabilities")
        ]

        guard let url = components.url else {
            throw ProviderError.invalidURL
        }

        return url
    }

    private func configuration(
        for location: WeatherLocation
    ) throws -> RadarServiceConfiguration {
        let latitude = location.latitude
        let longitude = location.longitude

        if (20...55).contains(latitude),
           (-130 ... -60).contains(longitude) {
            return configuration(
                workspace: "conus",
                layer: "conus_bref_qcd"
            )
        }

        if (50...72).contains(latitude),
           ((-180 ... -129).contains(longitude) || (170...180).contains(longitude)) {
            return configuration(
                workspace: "alaska",
                layer: "alaska_bref_qcd"
            )
        }

        if (18...23).contains(latitude),
           (-161 ... -154).contains(longitude) {
            return configuration(
                workspace: "hawaii",
                layer: "hawaii_bref_qcd"
            )
        }

        if (17...20).contains(latitude),
           (-69 ... -63).contains(longitude) {
            return configuration(
                workspace: "carib",
                layer: "carib_bref_qcd"
            )
        }

        if (12...15).contains(latitude),
           (143...147).contains(longitude) {
            return configuration(
                workspace: "guam",
                layer: "guam_bref_qcd"
            )
        }

        throw RadarProviderError.unsupportedRegion
    }

    private func configuration(
        workspace: String,
        layer: String
    ) -> RadarServiceConfiguration {
        RadarServiceConfiguration(
            serviceURL: URL(
                string: "https://opengeo.ncep.noaa.gov/geoserver/\(workspace)/\(layer)/ows"
            )!,
            layerName: layer
        )
    }
}

private struct RadarServiceConfiguration {
    let serviceURL: URL
    let layerName: String
}
