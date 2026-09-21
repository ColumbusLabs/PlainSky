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
