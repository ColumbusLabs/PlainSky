import Foundation

struct WeatherKitSupplementalProvider: SupplementalWeatherProviding {
    func weather(for location: WeatherLocation) async throws -> SupplementalWeatherPayload {
        throw ProviderError.notConfigured(
            "WeatherKit is not enabled yet. Add the WeatherKit capability to the App ID and target before activating Apple supplemental data."
        )
    }
}
