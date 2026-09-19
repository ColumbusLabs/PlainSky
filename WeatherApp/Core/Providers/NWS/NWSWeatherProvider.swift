import Foundation

struct NWSWeatherProvider: PrimaryWeatherProviding {
    private let client: NWSAPIClient

    init(client: NWSAPIClient = NWSAPIClient()) {
        self.client = client
    }

    func weather(for location: WeatherLocation) async throws -> PrimaryWeatherPayload {
        // Endpoint access is implemented and requires no API key.
        // Mapping is deliberately left disabled until real payload fixtures are captured
        // and verified against the exact NWS fields we choose to display.
        _ = client

        throw ProviderError.notConfigured(
            "NWS live mapping is scaffolded but not enabled. Capture and verify real endpoint fixtures before switching the app from preview mode."
        )
    }
}
