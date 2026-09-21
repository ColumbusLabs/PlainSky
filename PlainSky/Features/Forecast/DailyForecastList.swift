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

    private var hasDaytime: Bool {
        item.daytimeHigh != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text(
                    WeatherFormatters.fullForecastDay(
                        item.date,
                        hasDaytimePeriod: hasDaytime
                    )
                )
                .font(.headline)
                .foregroundStyle(WeatherTheme.primaryText)

                Spacer(minLength: 10)

                Image(systemName: item.daytimeCondition.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.title3)
                    .frame(width: 28)

                if hasDaytime {
                    Text(
                        WeatherFormatters.temperature(
                            item.daytimeHigh,
                            unitSystem: store.unitSystem
                        )
                    )
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(WeatherTheme.primaryText)
                    .fixedSize()
                }

                Text(
                    WeatherFormatters.temperature(
                        item.overnightLow,
                        unitSystem: store.unitSystem
                    )
                )
                .font((hasDaytime ? Font.subheadline : Font.headline).monospacedDigit())
                .foregroundStyle(
                    hasDaytime
                        ? WeatherTheme.secondaryText
                        : WeatherTheme.primaryText
                )
                .fixedSize()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WeatherTheme.tertiaryText)
            }

            Text(item.daytimeDescription)
                .font(.caption)
                .foregroundStyle(WeatherTheme.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if hasDaytime {
                HStack(spacing: 16) {
                    Label(
                        "Day \(WeatherFormatters.percent(item.daytimePrecipitationChance))",
                        systemImage: "drop.fill"
                    )

                    Label(
                        "Night \(WeatherFormatters.percent(item.nighttimePrecipitationChance))",
                        systemImage: "moon.fill"
                    )
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(WeatherTheme.accent)
            } else {
                Label(
                    "Tonight \(WeatherFormatters.percent(item.nighttimePrecipitationChance))",
                    systemImage: "drop.fill"
                )
                .font(.caption2.weight(.medium))
                .foregroundStyle(WeatherTheme.accent)
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
