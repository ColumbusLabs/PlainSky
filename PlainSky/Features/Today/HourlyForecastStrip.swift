import SwiftUI

struct HourlyForecastStrip: View {
    @Environment(WeatherStore.self) private var store
    @ScaledMetric(relativeTo: .body) private var cellWidth: CGFloat = 56

    let items: [HourlyForecastItem]

    var body: some View {
        WeatherCard(padding: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        cell(item: item, label: index == 0 ? "Now" : WeatherFormatters.hourLabel(item.date))

                        if index < items.count - 1 {
                            Rectangle()
                                .fill(WeatherTheme.divider)
                                .frame(width: 1, height: 64)
                        }
                    }
                }
                .padding(.horizontal, 6)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func cell(item: HourlyForecastItem, label: String) -> some View {
        let temperature = WeatherFormatters.temperature(item.temperature, unitSystem: store.unitSystem)
        let precipitation = WeatherFormatters.percent(item.precipitationChance)

        return VStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WeatherTheme.secondaryText)

            ConditionIcon(
                condition: item.condition,
                isDaytime: WeatherDaylight.isDaytime(item.date, solar: store.snapshot.solar),
                size: 22
            )
            .frame(height: 26)

            Text(temperature)
                .font(.headline.monospacedDigit())
                .foregroundStyle(WeatherTheme.primaryText)

            HStack(spacing: 2) {
                Image(systemName: "drop.fill")
                Text(precipitation)
                    .monospacedDigit()
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(WeatherTheme.accent)
        }
        .frame(width: max(56, cellWidth))
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(temperature), precipitation \(precipitation)")
    }
}
