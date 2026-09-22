import Foundation

enum WeatherFormatters {
    static func temperature(
        _ fahrenheit: Double?,
        unitSystem: WeatherUnitSystem = .us
    ) -> String {
        guard let fahrenheit else { return "—" }
        return "\(Int(temperatureValue(fahrenheit, unitSystem: unitSystem).rounded()))°"
    }

    static func temperatureValue(
        _ fahrenheit: Double,
        unitSystem: WeatherUnitSystem
    ) -> Double {
        switch unitSystem {
        case .us:
            fahrenheit
        case .metric:
            Measurement(value: fahrenheit, unit: UnitTemperature.fahrenheit)
                .converted(to: .celsius)
                .value
        }
    }

    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "—" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    static func wind(
        speed milesPerHour: Double?,
        direction: String?,
        unitSystem: WeatherUnitSystem = .us
    ) -> String {
        guard let milesPerHour else { return "—" }

        let speed = windSpeedValue(milesPerHour, unitSystem: unitSystem)
        let speedText = "\(Int(speed.rounded())) \(unitSystem.windUnit)"

        guard let direction, !direction.isEmpty else { return speedText }
        return "\(direction) \(speedText)"
    }

    static func windSpeedValue(
        _ milesPerHour: Double,
        unitSystem: WeatherUnitSystem
    ) -> Double {
        switch unitSystem {
        case .us:
            milesPerHour
        case .metric:
            Measurement(value: milesPerHour, unit: UnitSpeed.milesPerHour)
                .converted(to: .kilometersPerHour)
                .value
        }
    }

    static func visibility(
        _ miles: Double?,
        unitSystem: WeatherUnitSystem = .us
    ) -> String {
        guard let miles else { return "—" }

        let value: Double
        switch unitSystem {
        case .us:
            value = miles
        case .metric:
            value = Measurement(value: miles, unit: UnitLength.miles)
                .converted(to: .kilometers)
                .value
        }

        return "\(Int(value.rounded())) \(unitSystem.visibilityUnit)"
    }

    static func pressure(
        _ millibars: Double?,
        unitSystem: WeatherUnitSystem = .us
    ) -> String {
        guard let millibars else { return "—" }
        return "\(Int(millibars.rounded())) \(unitSystem.pressureUnit)"
    }

    static func hour(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Hour without minutes, e.g. "11 AM".
    static func hourLabel(_ date: Date) -> String {
        date.formatted(.dateTime.hour())
    }

    static func monthDay(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Short enough for narrow columns: "Today", "Tonight", or an abbreviated weekday.
    static func compactDay(
        _ date: Date,
        hasDaytimePeriod: Bool
    ) -> String {
        if Calendar.autoupdatingCurrent.isDateInToday(date) {
            return hasDaytimePeriod ? "Today" : "Tonight"
        }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    static func uvCategory(_ index: Int) -> String {
        switch index {
        case ..<3: "Low"
        case 3..<6: "Moderate"
        case 6..<8: "High"
        case 8..<11: "Very High"
        default: "Extreme"
        }
    }

    static func shortDay(_ date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    static func fullDay(_ date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    static func shortForecastDay(
        _ date: Date,
        hasDaytimePeriod: Bool
    ) -> String {
        if !hasDaytimePeriod && Calendar.autoupdatingCurrent.isDateInToday(date) {
            return "Tonight"
        }
        return shortDay(date)
    }

    static func fullForecastDay(
        _ date: Date,
        hasDaytimePeriod: Bool
    ) -> String {
        if !hasDaytimePeriod && Calendar.autoupdatingCurrent.isDateInToday(date) {
            return "Tonight"
        }
        return fullDay(date)
    }
}
