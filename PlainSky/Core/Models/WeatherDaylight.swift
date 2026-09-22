import Foundation

enum WeatherDaylight {
    static let fallbackSunriseMinute = 6 * 60 + 30
    static let fallbackSunsetMinute = 19 * 60 + 30

    /// Compares time of day only, so today's sunrise and sunset also approximate nearby days.
    static func isDaytime(
        _ date: Date,
        solar: SolarWeather?,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        let minute = minuteOfDay(date, calendar: calendar)
        let sunrise = solar?.sunrise.map { minuteOfDay($0, calendar: calendar) }
            ?? fallbackSunriseMinute
        let sunset = solar?.sunset.map { minuteOfDay($0, calendar: calendar) }
            ?? fallbackSunsetMinute

        return minute >= sunrise && minute < sunset
    }

    private static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
