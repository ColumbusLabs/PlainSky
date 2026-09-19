import SwiftUI

struct CurrentConditionsHero: View {
    @Environment(WeatherStore.self) private var store
    @ScaledMetric(relativeTo: .largeTitle) private var temperatureSize: CGFloat = 88
    @ScaledMetric(relativeTo: .title2) private var conditionIconSize: CGFloat = 44

    let current: CurrentConditions
    let today: DailyForecastItem?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: current.condition.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: conditionIconSize, weight: .medium))
                .accessibilityHidden(true)

            Text(
                WeatherFormatters.temperature(
                    current.temperature,
                    unitSystem: store.unitSystem
                )
            )
            .font(.system(size: temperatureSize, weight: .thin, design: .rounded))
            .foregroundStyle(WeatherTheme.primaryText)
            .contentTransition(.numericText())
            .minimumScaleFactor(0.55)
            .lineLimit(1)
            .accessibilityLabel(
                "Current temperature \(WeatherFormatters.temperature(current.temperature, unitSystem: store.unitSystem))"
            )

            VStack(spacing: 4) {
                Text(current.conditionDescription)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(WeatherTheme.primaryText)
                    .multilineTextAlignment(.center)

                if let apparentTemperature = current.apparentTemperature {
                    Text(
                        "Feels like \(WeatherFormatters.temperature(apparentTemperature, unitSystem: store.unitSystem))"
                    )
                    .font(.subheadline)
                    .foregroundStyle(WeatherTheme.secondaryText)
                }
            }

            if let today {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        temperatureFact(
                            title: "High",
                            value: today.daytimeHigh,
                            symbol: "arrow.up"
                        )
                        temperatureFact(
                            title: "Low",
                            value: today.overnightLow,
                            symbol: "arrow.down"
                        )
                    }

                    VStack(spacing: 6) {
                        temperatureFact(
                            title: "High",
                            value: today.daytimeHigh,
                            symbol: "arrow.up"
                        )
                        temperatureFact(
                            title: "Low",
                            value: today.overnightLow,
                            symbol: "arrow.down"
                        )
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(WeatherTheme.secondaryText)
            }

            SourceFreshnessView(metadata: current.source, compact: false)
                .padding(.top, 2)

            WeatherProviderAttributionView(metadata: current.source)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func temperatureFact(
        title: String,
        value: Double?,
        symbol: String
    ) -> some View {
        Label {
            Text(
                "\(title) \(WeatherFormatters.temperature(value, unitSystem: store.unitSystem))"
            )
        } icon: {
            Image(systemName: symbol)
        }
    }
}
