import Foundation

enum WeatherFormatters {
    static func temperature(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))°"
    }

    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "—" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    static func wind(speed: Double?, direction: String?) -> String {
        guard let speed else { return "—" }

        let speedText = "\(Int(speed.rounded())) mph"
        guard let direction, !direction.isEmpty else { return speedText }
        return "\(direction) \(speedText)"
    }

    static func visibility(_ miles: Double?) -> String {
        guard let miles else { return "—" }
        return "\(Int(miles.rounded())) mi"
    }

    static func pressure(_ millibars: Double?) -> String {
        guard let millibars else { return "—" }
        return "\(Int(millibars.rounded())) mb"
    }

    static func hour(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
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
}
