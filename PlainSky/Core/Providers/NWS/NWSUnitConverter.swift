import Foundation

enum NWSUnitConverter {
    static func temperatureFahrenheit(_ quantity: NWSQuantitativeValue?) -> Double? {
        guard let quantity, let value = quantity.value else { return nil }
        return temperatureFahrenheit(value, unitCode: quantity.unitCode)
    }

    static func temperatureFahrenheit(_ value: Double, unitCode: String?) -> Double? {
        let unit = normalized(unitCode)

        if unit.contains("degc") {
            return (value * 9 / 5) + 32
        }

        if unit.contains("degf") || unit.isEmpty {
            return value
        }

        if unit == "k" || unit.contains("kelvin") {
            return ((value - 273.15) * 9 / 5) + 32
        }

        return nil
    }

    static func forecastTemperatureFahrenheit(
        _ measurement: NWSForecastMeasurement?,
        legacyUnit: String?
    ) -> Double? {
        guard let measurement else { return nil }

        switch measurement {
        case let .quantity(quantity):
            return temperatureFahrenheit(quantity)
        case let .number(value):
            let unitCode = legacyUnit?.uppercased() == "C" ? "degC" : "degF"
            return temperatureFahrenheit(value, unitCode: unitCode)
        case .text:
            return nil
        }
    }

    static func speedMPH(_ quantity: NWSQuantitativeValue?) -> Double? {
        guard let quantity, let value = quantity.value else { return nil }
        return speedMPH(value, unitCode: quantity.unitCode)
    }

    static func speedMPH(_ value: Double, unitCode: String?) -> Double? {
        let unit = normalized(unitCode)

        if unit.contains("m_s-1") || unit.contains("m/s") {
            return value * 2.236_936_292_1
        }

        if unit.contains("km_h-1") || unit.contains("km/h") {
            return value * 0.621_371_192_2
        }

        if unit.contains("knot") || unit == "kt" || unit == "kts" {
            return value * 1.150_779_448
        }

        if unit.contains("mi_h-1") || unit.contains("mph") || unit.isEmpty {
            return value
        }

        return nil
    }

    static func forecastSpeedMPH(_ measurement: NWSForecastMeasurement?) -> Double? {
        guard let measurement else { return nil }

        switch measurement {
        case let .quantity(quantity):
            return speedMPH(quantity)
        case let .number(value):
            return value
        case let .text(text):
            return exactLegacySpeedMPH(text)
        }
    }

    static func exactLegacySpeedMPH(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !trimmed.contains(" to "),
              !trimmed.contains("-"),
              !trimmed.contains("–") else {
            return nil
        }

        let pattern = #"^([0-9]+(?:\.[0-9]+)?)\s*(mph|kt|kts|knots?|km/h|m/s)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: trimmed,
                range: NSRange(trimmed.startIndex..., in: trimmed)
              ),
              let valueRange = Range(match.range(at: 1), in: trimmed),
              let unitRange = Range(match.range(at: 2), in: trimmed),
              let value = Double(trimmed[valueRange]) else {
            return nil
        }

        return speedMPH(value, unitCode: String(trimmed[unitRange]))
    }

    static func humidityFraction(_ quantity: NWSQuantitativeValue?) -> Double? {
        guard let value = quantity?.value else { return nil }
        return max(0, min(1, value / 100))
    }

    static func visibilityMiles(_ quantity: NWSQuantitativeValue?) -> Double? {
        guard let quantity, let value = quantity.value else { return nil }
        let unit = normalized(quantity.unitCode)

        if unit == "m" || unit.contains("meter") {
            return value / 1_609.344
        }

        if unit.contains("km") {
            return value * 0.621_371_192_2
        }

        if unit.contains("mi") {
            return value
        }

        return nil
    }

    static func pressureMillibars(_ quantity: NWSQuantitativeValue?) -> Double? {
        guard let quantity, let value = quantity.value else { return nil }
        let unit = normalized(quantity.unitCode)

        if unit == "pa" || unit.contains("pascal") {
            return value / 100
        }

        if unit.contains("hpa") || unit.contains("mbar") || unit == "mb" {
            return value
        }

        return nil
    }

    static func precipitationFraction(_ quantity: NWSQuantitativeValue?) -> Double? {
        humidityFraction(quantity)
    }

    static func compassDirection(_ quantity: NWSQuantitativeValue?) -> String? {
        guard let degrees = quantity?.value else { return nil }

        let labels = [
            "N", "NNE", "NE", "ENE",
            "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW",
            "W", "WNW", "NW", "NNW"
        ]

        let raw = degrees.truncatingRemainder(dividingBy: 360)
        let normalizedDegrees = raw < 0 ? raw + 360 : raw
        let index = Int((normalizedDegrees / 22.5).rounded()) % labels.count
        return labels[index]
    }

    private static func normalized(_ unitCode: String?) -> String {
        (unitCode ?? "")
            .lowercased()
            .replacingOccurrences(of: "wmounit:", with: "")
            .replacingOccurrences(of: "unit:", with: "")
    }
}
