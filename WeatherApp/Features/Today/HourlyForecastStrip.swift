import SwiftUI

struct HourlyForecastStrip: View {
    let items: [HourlyForecastItem]

    var body: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Hourly")

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            VStack(spacing: 10) {
                                Text(index == 0 ? "Now" : WeatherFormatters.hour(item.date))
                                    .font(.caption.weight(index == 0 ? .semibold : .regular))
                                    .foregroundStyle(
                                        index == 0 ? WeatherTheme.primaryText : WeatherTheme.secondaryText
                                    )

                                Image(systemName: item.condition.symbolName)
                                    .symbolRenderingMode(.multicolor)
                                    .font(.title3)

                                Text(WeatherFormatters.temperature(item.temperature))
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
                            .frame(width: 67)

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
