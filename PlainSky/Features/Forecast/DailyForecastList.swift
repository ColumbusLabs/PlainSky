import SwiftUI

struct DailyForecastList: View {
    let items: [DailyForecastItem]

    var body: some View {
        WeatherCard(padding: 0) {
            VStack(spacing: 0) {
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
                            .padding(.horizontal, 14)
                    }
                }
            }
        }
    }
}

private struct DailyForecastRow: View {
    @Environment(WeatherStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let item: DailyForecastItem

    private var hasDaytime: Bool {
        item.daytimeHigh != nil
    }

    private var conditionName: String {
        item.daytimeCondition.displayName(isDaytime: hasDaytime)
    }

    private var high: String {
        WeatherFormatters.temperature(item.daytimeHigh, unitSystem: store.unitSystem)
    }

    private var low: String {
        WeatherFormatters.temperature(item.overnightLow, unitSystem: store.unitSystem)
    }

    private var dayChance: String {
        WeatherFormatters.percent(hasDaytime ? item.daytimePrecipitationChance : nil)
    }

    private var nightChance: String {
        WeatherFormatters.percent(item.nighttimePrecipitationChance)
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedLayout
            } else {
                standardLayout
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(WeatherFormatters.fullForecastDay(item.date, hasDaytimePeriod: hasDaytime)), " +
            "\(WeatherFormatters.monthDay(item.date)). \(conditionName). " +
            "High \(high), low \(low). " +
            "Day precipitation \(dayChance), night precipitation \(nightChance)."
        )
        .accessibilityHint("Opens day details")
    }

    private var standardLayout: some View {
        HStack(spacing: 6) {
            dayLabel
                .frame(width: 48, alignment: .leading)

            ConditionIcon(condition: item.daytimeCondition, isDaytime: hasDaytime, size: 26)
                .frame(width: 30)

            if dynamicTypeSize < .xLarge {
                Text(conditionName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(WeatherTheme.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }

            temperatureColumn(value: high, label: "H", color: WeatherTheme.primaryText)
            temperatureColumn(value: low, label: "L", color: WeatherTheme.secondaryText)

            precipitationColumn(value: dayChance, label: "Day")
                .padding(.leading, 2)

            Rectangle()
                .fill(WeatherTheme.divider)
                .frame(width: 1, height: 30)

            precipitationColumn(value: nightChance, label: "Night")

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WeatherTheme.tertiaryText)
        }
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                dayLabel
                Spacer()
                ConditionIcon(condition: item.daytimeCondition, isDaytime: hasDaytime, size: 30)
            }

            Text(conditionName)
                .font(.subheadline)
                .foregroundStyle(WeatherTheme.secondaryText)

            Text("H \(high)  L \(low)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(WeatherTheme.primaryText)

            Text("Day \(dayChance) · Night \(nightChance)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(WeatherTheme.accent)
        }
    }

    private var dayLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(WeatherFormatters.compactDay(item.date, hasDaytimePeriod: hasDaytime))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(WeatherTheme.primaryText)

            Text(WeatherFormatters.monthDay(item.date))
                .font(.caption2)
                .foregroundStyle(WeatherTheme.secondaryText)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private func temperatureColumn(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)

            Text(label)
                .font(.caption2)
                .foregroundStyle(WeatherTheme.tertiaryText)
        }
        .frame(minWidth: 30)
    }

    private func precipitationColumn(value: String, label: String) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 2) {
                Image(systemName: "drop.fill")
                    .font(.caption2)
                Text(value)
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
            .foregroundStyle(WeatherTheme.accent)

            Text(label)
                .font(.caption2)
                .foregroundStyle(WeatherTheme.tertiaryText)
        }
        .frame(minWidth: 38)
        .lineLimit(1)
    }
}
