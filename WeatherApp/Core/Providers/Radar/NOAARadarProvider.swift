import Foundation

struct NOAARadarProvider: RadarProviding {
    func frames(for location: WeatherLocation) async throws -> [RadarFrame] {
        throw ProviderError.notConfigured(
            "NOAA radar frame discovery is not enabled yet. The Radar UI is ready to accept timestamped tile frames once the selected NOAA/NCEP service is verified."
        )
    }
}
