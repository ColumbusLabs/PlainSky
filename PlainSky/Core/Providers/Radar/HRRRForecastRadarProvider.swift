import Foundation

/// Forecast "future radar" from NOAA's HRRR model, served as public-domain map tiles by the
/// Iowa Environmental Mesonet at Iowa State University.
struct HRRRForecastRadarProvider {
    private static let tileBaseURL = URL(string: "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/")!
    private static let runMetadataURL = URL(
        string: "https://mesonet.agron.iastate.edu/data/gis/images/4326/hrrr/refd_0000.json"
    )!
    static let stepMinutes = 15
    static let maximumForecastMinute = 1080

    private let httpClient: any HTTPClient
    private let horizon: TimeInterval
    private let now: () -> Date

    init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        horizon: TimeInterval = 2 * 60 * 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.httpClient = httpClient
        self.horizon = horizon
        self.now = now
    }

    static func supports(location: WeatherLocation) -> Bool {
        (21...53).contains(location.latitude) && (-134 ... -60).contains(location.longitude)
    }

    /// Frames valid after `start` and within the horizon from now, pinned to one model run
    /// so labels stay correct even if a newer run is published mid-load.
    func frames(for location: WeatherLocation, after start: Date?) async throws -> [RadarFrame] {
        guard Self.supports(location: location) else { return [] }

        var request = URLRequest(url: Self.runMetadataURL)
        request.timeoutInterval = 10
        request.setValue(
            "PlainSky/0.1 (https://github.com/ColumbusLabs/PlainSky)",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await httpClient.data(for: request)
        let metadata = try JSONDecoder().decode(RunMetadata.self, from: data)

        guard let runStart = ISO8601DateFormatter().date(from: metadata.modelInitUTC) else {
            throw ProviderError.decoding("HRRR run time was not a valid date.")
        }

        return Self.frames(
            runStart: runStart,
            after: max(start ?? now(), now().addingTimeInterval(-10 * 60)),
            until: now().addingTimeInterval(horizon)
        )
    }

    static func frames(runStart: Date, after start: Date, until end: Date) -> [RadarFrame] {
        let runStamp = runStamp(for: runStart)

        return stride(from: 0, through: maximumForecastMinute, by: stepMinutes).compactMap { minute in
            let validTime = runStart.addingTimeInterval(Double(minute) * 60)
            guard validTime > start, validTime <= end else { return nil }

            let layer = String(format: "hrrr::REFD-F%04d-%@", minute, runStamp)
            return RadarFrame(
                id: layer,
                timestamp: validTime,
                serviceURL: tileBaseURL,
                layerName: layer,
                kind: .forecast
            )
        }
    }

    private static func runStamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMddHHmm"
        return formatter.string(from: date)
    }
}

private struct RunMetadata: Decodable {
    let modelInitUTC: String

    enum CodingKeys: String, CodingKey {
        case modelInitUTC = "model_init_utc"
    }
}
