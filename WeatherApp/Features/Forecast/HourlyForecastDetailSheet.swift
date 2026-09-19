import SwiftUI

struct HourlyForecastDetailSheet: View {
    @Environment(WeatherStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let item: HourlyForecastItem

    var body: some View {
        NavigationStack {
            ZStack {
                WeatherBackdrop(style: backdropStyle)

                ScrollView {
                    VStack(spacing: 16) {
                        hero

                        WeatherCard {
                            VStack(spacing: 0) {
                                SectionHeader(title: "Details")
                                    .padding(.bottom, 8)

                                detailRow(
                                    "Feels like",
                                    WeatherFormatters.temperature(
                                        item.apparentTemperature,
                                        unitSystem: store.unitSystem
                                    )
                                )
                                divider
                                detailRow(
                                    "Precipitation",
                                    WeatherFormatters.percent(item.precipitationChance)
                                )
                                divider
                                detailRow(
                                    "Humidity",
                                    WeatherFormatters.percent(item.humidity)
                                )
                                divider
                                detailRow(
                                    "Wind",
                                    WeatherFormatters.wind(
                                        speed: item.windSpeed,
                                        direction: nil,
                                        unitSystem: store.unitSystem
                                    )
                                )
                                divider
                                detailRow(
                                    "Gusts",
                                    WeatherFormatters.wind(
                                        speed: item.windGust,
                                        direction: nil,
                                        unitSystem: store.unitSystem
                                    )
                                )
                            }
                        }

                        WeatherCard {
                            VStack(alignment: .leading, spacing: 9) {
                                SectionHeader(title: "Forecast source")
                                SourceFreshnessView(metadata: item.source)

                                if let from = item.source.validFrom,
                                   let to = item.source.validTo {
                                    Text(
                                        "Valid \(from.formatted(date: .omitted, time: .shortened))–\(to.formatted(date: .omitted, time: .shortened))"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(WeatherTheme.tertiaryText)
                                }
                            }
                        }
                    }
                    .padding(WeatherTheme.horizontalPadding)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(item.date.formatted(date: .abbreviated, time: .shortened))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var hero: some View {
        WeatherCard {
            HStack(spacing: 16) {
                Image(systemName: item.condition.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 38))
                    .frame(width: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        WeatherFormatters.temperature(
                            item.temperature,
                            unitSystem: store.unitSystem
                        )
                    )
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundStyle(WeatherTheme.primaryText)

                    Text(item.date.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(WeatherTheme.secondaryText)
                }

                Spacer()
            }
        }
    }

    private var divider: some View {
        Divider()
            .overlay(WeatherTheme.divider)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(WeatherTheme.secondaryText)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WeatherTheme.primaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
    }

    private var backdropStyle: WeatherBackdropStyle {
        switch item.condition {
        case .rain, .heavyRain, .thunderstorm: .rain
        case .cloudy, .fog: .cloudy
        default: .clear
        }
    }
}
