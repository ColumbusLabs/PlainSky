import SwiftUI

struct CurrentConditionsHero: View {
    @Environment(WeatherStore.self) private var store

    let current: CurrentConditions
    let today: DailyForecastItem?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: current.condition.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 44, weight: .medium))
                .accessibilityHidden(true)

            Text(
                WeatherFormatters.temperature(
                    current.temperature,
                    unitSystem: store.unitSystem
                )
            )
            .font(.system(size: 88, weight: .thin, design: .rounded))
            .foregroundStyle(WeatherTheme.primaryText)
            .contentTransition(.numericText())
            .minimumScaleFactor(0.65)
            .accessibilityLabel(
                "Current temperature \(WeatherFormatters.temperature(current.temperature, unitSystem: store.unitSystem))"
            )

            Text(current.conditionDescription)
                .font(.title3.weight(.medium))
                .foregroundStyle(WeatherTheme.primaryText)

            if let today {
                HStack(spacing: 14) {
                    Label {
                        Text(
                            "High \(WeatherFormatters.temperature(today.daytimeHigh, unitSystem: store.unitSystem))"
                        )
                    } icon: {
                        Image(systemName: "arrow.up")
                    }

                    Label {
                        Text(
                            "Low \(WeatherFormatters.temperature(today.overnightLow, unitSystem: store.unitSystem))"
                        )
                    } icon: {
                        Image(systemName: "arrow.down")
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(WeatherTheme.secondaryText)
            }

            SourceFreshnessView(metadata: current.source, compact: false)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
