import SwiftUI

struct CurrentConditionsHero: View {
    @Environment(WeatherStore.self) private var store
    @ScaledMetric(relativeTo: .largeTitle) private var temperatureSize: CGFloat = 96

    let current: WeatherProductState<CurrentConditions>
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
        let currentValue = current.value

        VStack(alignment: .leading, spacing: 2) {
            Text(WeatherFormatters.temperature(
                currentValue?.temperature,
                unitSystem: store.unitSystem
            ))
                .font(.system(size: temperatureSize, weight: .medium))
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityLabel(currentValue.map {
                    "Current temperature \(temperature($0.temperature))"
                } ?? currentStatus)

            Text(currentValue?.conditionDescription ?? currentStatus)
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 2) {
                if let apparentTemperature = currentValue?.apparentTemperature {
                    Text("Feels like \(temperature(apparentTemperature))")
                }

                if let highLowText {
                    Text(highLowText)
                }
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(WeatherTheme.heroText)
            .padding(.top, 2)
        }
        .foregroundStyle(WeatherTheme.heroText)
        .heroTextShadow()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var currentStatus: String {
        current.isLoading ? "Checking current conditions" : "Current conditions unavailable"
    }

    private func temperature(_ value: Double?) -> String {
        WeatherFormatters.temperature(value, unitSystem: store.unitSystem)
    }
}
