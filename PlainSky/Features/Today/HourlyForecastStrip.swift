import SwiftUI

struct HourlyForecastStrip: View {
    @Environment(WeatherStore.self) private var store
    @ScaledMetric(relativeTo: .body) private var cellWidth: CGFloat = 67

    let items: [HourlyForecastItem]
    var onSeeAll: (() -> Void)?

    var body: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "Hourly",
                    actionTitle: onSeeAll == nil ? nil : "See all",
                    action: onSeeAll
                )

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            VStack(spacing: 10) {
                                Text(WeatherFormatters.hour(item.date))
                                    .font(.caption)
                                    .foregroundStyle(
                                        WeatherTheme.secondaryText
                                    )

                                Image(systemName: item.condition.symbolName)
                                    .symbolRenderingMode(.multicolor)
                                    .font(.title3)

                                Text(
                                    WeatherFormatters.temperature(
                                        item.temperature,
                                        unitSystem: store.unitSystem
                                    )
                                )
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(WeatherTheme.primaryText)

                                HStack(spacing: 3) {
                                    Image(systemName: "drop.fill")
                                        .font(.caption2)
                                    Text(WeatherFormatters.percent(item.precipitationChance))
                                        .font(.caption2.monospacedDigit())
                                }
                                .foregroundStyle(WeatherTheme.accent)
                            }
                            .frame(width: max(67, cellWidth))
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(
                                "\(WeatherFormatters.hour(item.date)), " +
                                "\(WeatherFormatters.temperature(item.temperature, unitSystem: store.unitSystem)), " +
                                "precipitation \(WeatherFormatters.percent(item.precipitationChance))"
                            )

                            if index < items.count - 1 {
                                Divider()
                                    .overlay(WeatherTheme.divider)
                                    .frame(height: 74)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}
