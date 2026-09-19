import Foundation

enum WeatherKitConditionMapper {
    static func condition(symbolName: String) -> WeatherCondition {
        let symbol = symbolName.lowercased()

        if symbol.contains("bolt") || symbol.contains("thunder") {
            return .thunderstorm
        }

        if symbol.contains("heavyrain") {
            return .heavyRain
        }

        if symbol.contains("rain") || symbol.contains("drizzle") {
            return .rain
        }

        if symbol.contains("snow")
            || symbol.contains("sleet")
            || symbol.contains("hail") {
            return .snow
        }

        if symbol.contains("fog") || symbol.contains("haze") {
            return .fog
        }

        if symbol.contains("wind") {
            return .windy
        }

        if symbol.contains("cloud.sun")
            || symbol.contains("cloud.moon") {
            return .partlyCloudy
        }

        if symbol.contains("cloud") {
            return .cloudy
        }

        if symbol.contains("sun")
            || symbol.contains("moon")
            || symbol.contains("clear") {
            return .clear
        }

        return .unknown
    }
}
