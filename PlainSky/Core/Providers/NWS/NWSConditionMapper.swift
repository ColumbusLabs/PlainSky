import Foundation

enum NWSConditionMapper {
    static func condition(from text: String?) -> WeatherCondition {
        let value = (text ?? "").lowercased()

        if value.contains("thunder") || value.contains("t-storm") {
            return .thunderstorm
        }
        if value.contains("snow") || value.contains("flurr") || value.contains("blizzard") {
            return .snow
        }
        if value.contains("heavy rain") || value.contains("heavy shower") {
            return .heavyRain
        }
        if value.contains("rain") || value.contains("shower") || value.contains("drizzle") {
            return .rain
        }
        if value.contains("fog") || value.contains("mist") || value.contains("haze") {
            return .fog
        }
        if value.contains("partly") {
            return .partlyCloudy
        }
        if value.contains("mostly sunny") || value.contains("mostly clear") {
            return .mostlyClear
        }
        if value.contains("cloud") || value.contains("overcast") {
            return .cloudy
        }
        if value.contains("sunny") || value.contains("clear") || value.contains("fair") {
            return .clear
        }
        if value.contains("windy") || value.contains("breezy") {
            return .windy
        }

        return .unknown
    }
}
