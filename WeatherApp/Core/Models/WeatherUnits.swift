import Foundation

enum WeatherUnitSystem: String, CaseIterable, Identifiable, Codable, Sendable {
    case us
    case metric

    var id: Self { self }

    var title: String {
        switch self {
        case .us: "U.S."
        case .metric: "Metric"
        }
    }

    var temperatureSymbol: String {
        switch self {
        case .us: "°F"
        case .metric: "°C"
        }
    }

    var windUnit: String {
        switch self {
        case .us: "mph"
        case .metric: "km/h"
        }
    }

    var visibilityUnit: String {
        switch self {
        case .us: "mi"
        case .metric: "km"
        }
    }

    var pressureUnit: String {
        switch self {
        case .us: "mb"
        case .metric: "hPa"
        }
    }
}
