import SwiftUI

struct DailyForecastPreview: View {
    @Environment(WeatherStore.self) private var store

    let items: [DailyForecastItem]
    var onSeeAll: (() -> Void)?

    var body: some View {
        WeatherCard {
            VStack(spacing: 0) {
                SectionHeader(
                    title: "Next days",
                    actionTitle: onSeeAll == nil ? nil : "See all",
                    action: onSeeAll
                )
                .padding(.bottom, 6)

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 14) {
                        Text(WeatherFormatters.shortDay(item.date))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WeatherTheme.primaryText)
                            .frame(width: 68, alignment: .leading)

                        Image(systemName: item.daytimeCondition.symbolName)
                            .symbolRenderingMode(.multicolor)
                            .font(.title3)
                            .frame(width: 28)

                        HStack(spacing: 3) {
                            Image(systemName: "drop.fill")
                                .font(.caption2)
                            Text(WeatherFormatters.percent(item.daytimePrecipitationChance))
                                .font(.caption.monospacedDigit())
                        }
                        .foregroundStyle(WeatherTheme.accent)
                        .frame(width: 54, alignment: .leading)

                        Spacer()

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
                    .padding(.vertical, 13)

                    if index < items.count - 1 {
                        Divider()
                            .overlay(WeatherTheme.divider)
                    }
                }
            }
        }
    }
}
