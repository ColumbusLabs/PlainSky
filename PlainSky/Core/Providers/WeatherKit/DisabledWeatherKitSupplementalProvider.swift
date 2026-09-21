import Foundation

struct DisabledWeatherKitSupplementalProvider: SupplementalWeatherProviding {
    func weather(for location: WeatherLocation) async throws -> SupplementalWeatherPayload {
        let message = "WeatherKit supplements are not enabled for this build yet."

        return SupplementalWeatherPayload(
            currentFallback: nil,
            minutePrecipitation: [],
            solar: nil,
            availability: [
                .minutePrecipitation: .unavailable(message),
                .uvIndex: .unavailable(message),
                .solarEvents: .unavailable(message)
            ]
        )
    }
}
