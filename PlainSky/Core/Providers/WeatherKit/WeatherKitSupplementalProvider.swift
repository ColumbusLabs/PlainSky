import CoreLocation
import Foundation
import WeatherKit

struct WeatherKitSupplementalProvider: SupplementalWeatherProviding {
    private let service: WeatherService
    private let now: () -> Date

    init(
        service: WeatherService = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.now = now
    }

    func weather(for location: WeatherLocation) async throws -> SupplementalWeatherPayload {
        do {
            return try await loadWeather(for: location)
        } catch {
            if error is CancellationError {
                throw error
            }

            throw ProviderError.notConfigured(
                WeatherKitErrorMapper.message(for: error)
            )
        }
    }

    private func loadWeather(for location: WeatherLocation) async throws -> SupplementalWeatherPayload {
        let requestedLocation = CLLocation(
            latitude: location.latitude,
            longitude: location.longitude
        )

        async let attributionRequest = service.attribution

        let (current, minute, daily) = try await service.weather(
            for: requestedLocation,
            including: .current,
            .minute,
            .daily
        )
        let attribution = try await attributionRequest
        let fetchedAt = now()

        let currentSource = sourceMetadata(
            productName: "Apple current conditions",
            metadata: current.metadata,
            validFrom: current.date,
            validTo: nil,
            fetchedAt: fetchedAt,
            attribution: attribution
        )

        let currentFallback = CurrentConditions(
            temperature: current.temperature.converted(to: .fahrenheit).value,
            apparentTemperature: current.apparentTemperature
                .converted(to: .fahrenheit)
                .value,
            condition: WeatherKitConditionMapper.condition(
                symbolName: current.symbolName
            ),
            conditionDescription: current.condition.description,
            humidity: current.humidity,
            dewPoint: current.dewPoint.converted(to: .fahrenheit).value,
            windSpeed: current.wind.speed.converted(to: .milesPerHour).value,
            windGust: current.wind.gust?
                .converted(to: .milesPerHour)
                .value,
            windDirection: current.wind.compassDirection.abbreviation,
            visibilityMiles: current.visibility.converted(to: .miles).value,
            pressureMillibars: current.pressure
                .converted(to: .hectopascals)
                .value,
            source: currentSource
        )

        let minuteSamples: [MinutePrecipitationSample]
        let minuteAvailability: WeatherProductAvailability

        if let minute {
            let forecast = minute.forecast
            let validFrom = forecast.first?.date
            let validTo = forecast.last?.date.addingTimeInterval(60)

            let minuteSource = sourceMetadata(
                productName: "Apple next-hour precipitation",
                metadata: minute.metadata,
                validFrom: validFrom,
                validTo: validTo,
                fetchedAt: fetchedAt,
                attribution: attribution
            )

            minuteSamples = forecast.map { sample in
                MinutePrecipitationSample(
                    date: sample.date,
                    probability: sample.precipitationChance,
                    intensity: millimetersPerHour(
                        sample.precipitationIntensity
                    ),
                    source: minuteSource
                )
            }

            minuteAvailability = minuteSamples.isEmpty
                ? .unavailable("Apple Weather returned no usable minute precipitation samples.")
                : .available
        } else {
            minuteSamples = []
            minuteAvailability = .unsupported(
                "Apple Weather does not provide next-hour precipitation for this location."
            )
        }

        let today = daily.forecast.first
        let solarSource = sourceMetadata(
            productName: "Apple UV and solar events",
            metadata: daily.metadata,
            validFrom: today?.date ?? current.date,
            validTo: nil,
            fetchedAt: fetchedAt,
            attribution: attribution
        )

        let solar = SolarWeather(
            sunrise: today?.sun.sunrise,
            sunset: today?.sun.sunset,
            uvIndex: current.uvIndex.value,
            source: solarSource
        )

        let hasSolarEvents = solar.sunrise != nil || solar.sunset != nil

        return SupplementalWeatherPayload(
            currentFallback: currentFallback,
            minutePrecipitation: minuteSamples,
            solar: solar,
            availability: [
                .minutePrecipitation: minuteAvailability,
                .uvIndex: .available,
                .solarEvents: hasSolarEvents
                    ? .available
                    : .unsupported(
                        "Apple Weather does not provide sunrise or sunset for this location today."
                    )
            ]
        )
    }

    private func sourceMetadata(
        productName: String,
        metadata: WeatherMetadata,
        validFrom: Date?,
        validTo: Date?,
        fetchedAt: Date,
        attribution: WeatherAttribution
    ) -> WeatherSourceMetadata {
        WeatherSourceMetadata(
            provider: .weatherKit,
            productName: productName,
            sourceName: attribution.serviceName,
            observedAt: nil,
            issuedAt: metadata.date,
            validFrom: validFrom,
            validTo: validTo,
            fetchedAt: fetchedAt,
            expiresAt: metadata.expirationDate,
            attributionServiceName: attribution.serviceName,
            attributionLegalURL: attribution.legalPageURL,
            attributionMarkLightURL: attribution.combinedMarkLightURL,
            attributionMarkDarkURL: attribution.combinedMarkDarkURL
        )
    }

    private func millimetersPerHour(
        _ intensity: Measurement<UnitSpeed>
    ) -> Double {
        let metersPerSecond = intensity
            .converted(to: .metersPerSecond)
            .value

        return metersPerSecond * 3_600_000
    }
}

enum WeatherKitErrorMapper {
    static let authenticationMessage = "Apple Weather authentication failed for this build. WeatherKit supplements need the capability enabled for this App ID."
    static let temporaryMessage = "Apple Weather is temporarily unavailable."

    static func message(for error: Error) -> String {
        guard isAuthenticationFailure(error) else {
            return temporaryMessage
        }

        return authenticationMessage
    }

    private static func isAuthenticationFailure(_ error: Error) -> Bool {
        let nsError = error as NSError

        return nsError.domain.contains("WDSJWTAuthenticatorServiceListener")
            || nsError.localizedDescription.contains("WDSJWTAuthenticatorServiceListener")
    }
}
