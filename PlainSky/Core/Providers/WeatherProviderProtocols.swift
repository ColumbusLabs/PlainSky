import Foundation

struct PrimaryWeatherPayload: Sendable {
    var current: CurrentConditions?
    var hourly: [HourlyForecastItem]
    var daily: [DailyForecastItem]
    var alerts: [WeatherAlert]
    var availability: [WeatherProduct: WeatherProductAvailability] = [:]
}

struct SupplementalWeatherPayload: Sendable {
    var currentFallback: CurrentConditions?
    var minutePrecipitation: [MinutePrecipitationSample]
    var solar: SolarWeather?
    var availability: [WeatherProduct: WeatherProductAvailability] = [:]
}

protocol PrimaryWeatherProviding {
    func weather(for location: WeatherLocation) async throws -> PrimaryWeatherPayload

    func updates(
        for location: WeatherLocation,
        context: WeatherRefreshContext,
        onUpdate: @escaping WeatherProductUpdateHandler
    ) async throws
}

extension PrimaryWeatherProviding {
    func updates(
        for location: WeatherLocation,
        context: WeatherRefreshContext,
        onUpdate: @escaping WeatherProductUpdateHandler
    ) async throws {
        let payload = try await weather(for: location)
        let now = Date()
        let identity = context.identity

        await onUpdate(WeatherProductUpdate(
            identity: identity,
            event: .current(primaryState(
                payload.current,
                availability: payload.availability[.currentConditions],
                provider: .nwsObservation,
                name: "Current conditions",
                now: now
            ))
        ))
        await onUpdate(WeatherProductUpdate(
            identity: identity,
            event: .hourly(primaryState(
                payload.hourly,
                availability: payload.availability[.hourlyForecast],
                provider: .nwsForecast,
                name: "Hourly forecast",
                now: now
            ))
        ))
        await onUpdate(WeatherProductUpdate(
            identity: identity,
            event: .daily(primaryState(
                payload.daily,
                availability: payload.availability[.dailyForecast],
                provider: .nwsForecast,
                name: "Daily forecast",
                now: now
            ))
        ))
        await onUpdate(WeatherProductUpdate(
            identity: identity,
            event: .alerts(primaryState(
                payload.alerts,
                availability: payload.availability[.alerts],
                provider: .nwsForecast,
                name: "NWS alerts",
                now: now,
                allowEmpty: true
            ))
        ))
    }

    private func primaryState<Value: Sendable>(
        _ value: Value?,
        availability: WeatherProductAvailability?,
        provider: WeatherProvider,
        name: String,
        now: Date,
        allowEmpty: Bool = false
    ) -> WeatherProductState<Value> {
        let resolvedAvailability = availability ?? (value == nil
            ? .unavailable("\(name) is unavailable.")
            : .available)

        switch resolvedAvailability {
        case .loading:
            return .loading
        case let .unsupported(message):
            return .unsupported(message)
        case let .unavailable(message):
            return .unavailable(message)
        case .available:
            guard let value else {
                return .unavailable("\(name) is unavailable.")
            }
            if !allowEmpty,
               let array = value as? [Any],
               array.isEmpty {
                return .unavailable("\(name) returned no usable data.")
            }

            var source: WeatherSourceMetadata
            if let current = value as? CurrentConditions {
                source = current.source
            } else if let hourly = value as? [HourlyForecastItem], let first = hourly.first {
                source = first.source
            } else if let daily = value as? [DailyForecastItem], let first = daily.first {
                source = first.source
            } else if let alerts = value as? [WeatherAlert], let first = alerts.first {
                source = first.source
            } else {
                source = WeatherSourceMetadata(
                    provider: provider,
                    productName: name,
                    sourceName: nil,
                    observedAt: nil,
                    issuedAt: now,
                    validFrom: nil,
                    validTo: nil,
                    fetchedAt: now,
                    expiresAt: nil,
                    validatedAt: now
                )
            }
            source.validatedAt = now
            return .available(value, WeatherValidationMetadata(source: source, validatedAt: now))
        }
    }
}

protocol SupplementalWeatherProviding {
    func weather(for location: WeatherLocation) async throws -> SupplementalWeatherPayload
}

protocol RadarProviding {
    func frames(for location: WeatherLocation) async throws -> [RadarFrame]
}

enum WeatherProduct: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case currentConditions
    case hourlyForecast
    case dailyForecast
    case alerts
    case radar
    case minutePrecipitation
    case uvIndex
    case solarEvents

    var id: Self { self }

    var displayName: String {
        switch self {
        case .currentConditions: "Current conditions"
        case .hourlyForecast: "Hourly forecast"
        case .dailyForecast: "Daily forecast"
        case .alerts: "Alerts"
        case .radar: "Radar"
        case .minutePrecipitation: "Next-hour precipitation"
        case .uvIndex: "UV index"
        case .solarEvents: "Sunrise / sunset"
        }
    }
}

enum WeatherSourcePolicy {
    static func provider(for product: WeatherProduct) -> WeatherProvider {
        switch product {
        case .currentConditions:
            .nwsObservation
        case .hourlyForecast, .dailyForecast, .alerts:
            .nwsForecast
        case .radar:
            .noaaRadar
        case .minutePrecipitation, .uvIndex, .solarEvents:
            .weatherKit
        }
    }
}
