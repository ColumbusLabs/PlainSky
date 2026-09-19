import SwiftUI

struct DailyForecastList: View {
    let items: [DailyForecastItem]

    var body: some View {
        WeatherCard {
            VStack(spacing: 0) {
                SectionHeader(title: "Seven day outlook")
                    .padding(.bottom, 8)

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    NavigationLink {
                        DayForecastDetailView(day: item)
                    } label: {
                        DailyForecastRow(item: item)
                    }
                    .buttonStyle(.plain)

                    if index < items.count - 1 {
                        Divider()
                            .overlay(WeatherTheme.divider)
                    }
                }
            }
        }
    }
}

private struct DailyForecastRow: View {
    @Environment(WeatherStore.self) private var store

    let item: DailyForecastItem

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(WeatherFormatters.fullDay(item.date))
                    .font(.headline)
                    .foregroundStyle(WeatherTheme.primaryText)

                Text(item.daytimeDescription)
                    .font(.caption)
                    .foregroundStyle(WeatherTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 8) {
                    Image(systemName: item.daytimeCondition.symbolName)
                        .symbolRenderingMode(.multicolor)

                    Text(
                        WeatherFormatters.temperature(
                            item.overnightLow,
                            unitSystem: store.unitSystem
                        )
                    )
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(WeatherTheme.secondaryText)

                    Text(
                        WeatherFormatters.temperature(
                            item.daytimeHigh,
                            unitSystem: store.unitSystem
                        )
                    )
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(WeatherTheme.primaryText)
                }

                HStack(spacing: 10) {
                    Label(
                        "Day \(WeatherFormatters.percent(item.daytimePrecipitationChance))",
                        systemImage: "drop.fill"
                    )

                    Text("Night \(WeatherFormatters.percent(item.nighttimePrecipitationChance))")
                }
                .font(.caption2)
                .foregroundStyle(WeatherTheme.accent)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(WeatherTheme.tertiaryText)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
