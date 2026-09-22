import SwiftUI

struct DailyForecastPreview: View {
    @Environment(WeatherStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let items: [DailyForecastItem]
    var onSeeAll: (() -> Void)?

    var body: some View {
        Button {
            onSeeAll?()
        } label: {
            WeatherCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(
                        title: "Next \(items.count) Days",
                        showsChevron: onSeeAll != nil
                    )

                    if dynamicTypeSize >= .xxLarge {
                        VStack(spacing: 12) {
                            ForEach(items) { item in
                                row(item)
                            }
                        }
                    } else {
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(items) { item in
                                column(item)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(onSeeAll == nil)
        .accessibilityHint("Opens the daily forecast")
    }

    private func column(_ item: DailyForecastItem) -> some View {
        let hasDaytime = item.daytimeHigh != nil

        return VStack(spacing: 8) {
            Text(WeatherFormatters.compactDay(item.date, hasDaytimePeriod: hasDaytime))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WeatherTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            ConditionIcon(condition: item.daytimeCondition, isDaytime: hasDaytime, size: 24)
                .frame(height: 28)

            temperatures(item)
                .font(.subheadline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            precipitation(item)
        }
        .accessibilityElement(children: .combine)
    }

    private func row(_ item: DailyForecastItem) -> some View {
        let hasDaytime = item.daytimeHigh != nil

        return HStack(spacing: 12) {
            Text(WeatherFormatters.compactDay(item.date, hasDaytimePeriod: hasDaytime))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WeatherTheme.primaryText)

            ConditionIcon(condition: item.daytimeCondition, isDaytime: hasDaytime, size: 24)

            Spacer(minLength: 8)

            precipitation(item)

            temperatures(item)
                .font(.subheadline.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    private func temperatures(_ item: DailyForecastItem) -> some View {
        HStack(spacing: 4) {
            Text(WeatherFormatters.temperature(item.overnightLow, unitSystem: store.unitSystem))
                .foregroundStyle(WeatherTheme.secondaryText)

            if item.daytimeHigh != nil {
                Text(WeatherFormatters.temperature(item.daytimeHigh, unitSystem: store.unitSystem))
                    .fontWeight(.semibold)
                    .foregroundStyle(WeatherTheme.primaryText)
            }
        }
    }

    private func precipitation(_ item: DailyForecastItem) -> some View {
        let chance = item.daytimeHigh == nil
            ? item.nighttimePrecipitationChance
            : item.daytimePrecipitationChance

        return HStack(spacing: 2) {
            Image(systemName: "drop.fill")
            Text(WeatherFormatters.percent(chance))
                .monospacedDigit()
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(WeatherTheme.accent)
    }
}
