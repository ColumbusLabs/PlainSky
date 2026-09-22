import SwiftUI

struct CurrentConditionsHero: View {
    @Environment(WeatherStore.self) private var store
    @ScaledMetric(relativeTo: .largeTitle) private var temperatureSize: CGFloat = 96

    let current: CurrentConditions
    let today: DailyForecastItem?

    private var highLowText: String? {
        guard let today else { return nil }

        var parts: [String] = []
        if today.daytimeHigh != nil {
            parts.append("H: \(temperature(today.daytimeHigh))")
        }
        if today.overnightLow != nil {
            parts.append("L: \(temperature(today.overnightLow))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(temperature(current.temperature))
                .font(.system(size: temperatureSize, weight: .medium))
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityLabel("Current temperature \(temperature(current.temperature))")

            Text(current.conditionDescription)
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 2) {
                if let apparentTemperature = current.apparentTemperature {
                    Text("Feels like \(temperature(apparentTemperature))")
                }

                if let highLowText {
                    Text(highLowText)
                }
            }
            .font(.body.weight(.medium))
            .foregroundStyle(WeatherTheme.heroSecondaryText)
            .padding(.top, 2)
        }
        .foregroundStyle(WeatherTheme.heroText)
        .heroTextShadow()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func temperature(_ value: Double?) -> String {
        WeatherFormatters.temperature(value, unitSystem: store.unitSystem)
    }
}
