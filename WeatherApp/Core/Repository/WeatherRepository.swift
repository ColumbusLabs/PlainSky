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
        let primaryResult = try await primary.weather(for: location)

        let supplementalResult: SupplementalWeatherPayload?
        let supplementalFailure: String?

        do {
            supplementalResult = try await supplemental.weather(for: location)
            supplementalFailure = nil
        } catch {
            supplementalResult = nil
            supplementalFailure = error.localizedDescription
        }

        guard let current = primaryResult.current ?? supplementalResult?.currentFallback else {
            throw ProviderError.missingRequiredData(
                "Neither the NWS observation group nor the approved current-conditions fallback was available."
            )
        }

        var availability = primaryResult.availability

        if availability[.currentConditions] == nil {
            availability[.currentConditions] = .available
        }
        if availability[.hourlyForecast] == nil {
            availability[.hourlyForecast] = primaryResult.hourly.isEmpty
                ? .unavailable("Hourly forecast data is currently unavailable.")
                : .available
        }
        if availability[.dailyForecast] == nil {
            availability[.dailyForecast] = primaryResult.daily.isEmpty
                ? .unavailable("Daily forecast data is currently unavailable.")
                : .available
        }
        if availability[.alerts] == nil {
            availability[.alerts] = .available
        }

        if let supplementalResult {
            availability.merge(supplementalResult.availability) { _, supplemental in
                supplemental
            }

            if availability[.minutePrecipitation] == nil {
                availability[.minutePrecipitation] = supplementalResult.minutePrecipitation.isEmpty
                    ? .unsupported("Next-hour precipitation is not available for this location.")
                    : .available
            }

            if availability[.uvIndex] == nil {
                availability[.uvIndex] = supplementalResult.solar?.uvIndex == nil
                    ? .unsupported("UV data is not available for this location.")
                    : .available
            }

            if availability[.solarEvents] == nil {
                let hasSolarEvent = supplementalResult.solar?.sunrise != nil
                    || supplementalResult.solar?.sunset != nil
                availability[.solarEvents] = hasSolarEvent
                    ? .available
                    : .unsupported("Sunrise and sunset data is not available for this location.")
            }
        } else {
            let reason = supplementalFailure ?? "Apple supplemental weather is unavailable."
            availability[.minutePrecipitation] = .unavailable(reason)
            availability[.uvIndex] = .unavailable(reason)
            availability[.solarEvents] = .unavailable(reason)
        }

        availability[.radar] = availability[.radar]
            ?? .unavailable("Radar has not been loaded for this weather snapshot.")

        return WeatherSnapshot(
            location: location,
            current: current,
            hourly: primaryResult.hourly,
            daily: primaryResult.daily,
            minutePrecipitation: supplementalResult?.minutePrecipitation ?? [],
            alerts: primaryResult.alerts,
            solar: supplementalResult?.solar,
            availability: availability,
            fetchedAt: Date()
        )
    }
}
