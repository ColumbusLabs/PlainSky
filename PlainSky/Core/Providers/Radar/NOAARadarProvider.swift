import Foundation

/// Lets the Today radar card and the Radar tab share one capabilities download; NOAA
/// publishes a new scan roughly every two minutes, so entries expire quickly.
final class RadarCapabilitiesCache: @unchecked Sendable {
    static let shared = RadarCapabilitiesCache()

    private let lifetime: TimeInterval = 90
    private let lock = NSLock()
    private var entries: [URL: (times: [Date], storedAt: Date)] = [:]

    func times(for url: URL, now: Date = Date()) -> [Date]? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = entries[url], now.timeIntervalSince(entry.storedAt) < lifetime else {
            return nil
        }
        return entry.times
    }

    func store(_ times: [Date], for url: URL, now: Date = Date()) {
        lock.lock()
        entries[url] = (times, now)
        lock.unlock()
    }
}

struct NOAARadarProvider: RadarProviding {
    private let httpClient: any HTTPClient
    private let historyWindow: TimeInterval
    private let maximumFrames: Int
    private let capabilitiesCache: RadarCapabilitiesCache?

    init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        historyWindow: TimeInterval = 2 * 60 * 60,
        maximumFrames: Int = 12,
        capabilitiesCache: RadarCapabilitiesCache? = nil
    ) {
        self.httpClient = httpClient
        self.historyWindow = historyWindow
        self.maximumFrames = maximumFrames
        self.capabilitiesCache = capabilitiesCache
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
        let allTimes = try await frameTimes(from: capabilitiesURL)

        guard let newest = allTimes.last else {
            throw RadarProviderError.noFrameTimes
        }

        let cutoff = newest.addingTimeInterval(-historyWindow)
        let recent = Self.evenlySampled(
            allTimes.filter { $0 >= cutoff && $0 <= newest },
            limit: maximumFrames
        )

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

    private func frameTimes(from capabilitiesURL: URL) async throws -> [Date] {
        if let cached = capabilitiesCache?.times(for: capabilitiesURL) {
            return cached
        }

        var request = URLRequest(url: capabilitiesURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(
            "PlainSky/0.1 (https://github.com/ColumbusLabs/PlainSky)",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await httpClient.data(for: request)
        let times = try RadarTimeParser.frameTimes(from: data)
        capabilitiesCache?.store(times, for: capabilitiesURL)
        return times
    }

    /// Spreads playback across the whole history window and always keeps the newest frame.
    static func evenlySampled(_ times: [Date], limit: Int) -> [Date] {
        guard limit > 0, times.count > limit else { return times }
        guard limit > 1 else { return Array(times.suffix(1)) }

        let lastIndex = times.count - 1
        let indices = (0..<limit).map { step in
            lastIndex - Int((Double(lastIndex) * Double(limit - 1 - step) / Double(limit - 1)).rounded())
        }

        return Array(Set(indices)).sorted().map { times[$0] }
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
