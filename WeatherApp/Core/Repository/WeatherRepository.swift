import Foundation

@MainActor
protocol WeatherRepository {
    func load(location: WeatherLocation) async throws -> WeatherSnapshot
}

@MainActor
struct PreviewWeatherRepository: WeatherRepository {
    func load(location: WeatherLocation) async throws -> WeatherSnapshot {
        var snapshot = MockWeather.snapshot
        snapshot.location = location
        return snapshot
    }
}

@MainActor
final class LiveWeatherRepository: WeatherRepository {
    private let primary: any PrimaryWeatherProviding
    private let supplemental: any SupplementalWeatherProviding

    init(
        primary: any PrimaryWeatherProviding,
        supplemental: any SupplementalWeatherProviding
    ) {
        self.primary = primary
        self.supplemental = supplemental
    }

    func load(location: WeatherLocation) async throws -> WeatherSnapshot {
        async let primaryPayload = primary.weather(for: location)
        async let supplementalPayload = supplemental.weather(for: location)

        let primaryResult = try await primaryPayload
        let supplementalResult = try? await supplementalPayload

        guard let current = primaryResult.current ?? supplementalResult?.currentFallback else {
            throw ProviderError.missingRequiredData(
                "Neither the NWS observation group nor the approved current-conditions fallback was available."
            )
        }

        return WeatherSnapshot(
            location: location,
            current: current,
            hourly: primaryResult.hourly,
            daily: primaryResult.daily,
            minutePrecipitation: supplementalResult?.minutePrecipitation ?? [],
            alerts: primaryResult.alerts,
            solar: supplementalResult?.solar,
            fetchedAt: Date()
        )
    }
}
