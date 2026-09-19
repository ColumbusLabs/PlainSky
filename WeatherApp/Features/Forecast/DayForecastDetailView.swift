import SwiftUI

struct DayForecastDetailView: View {
    @Environment(WeatherStore.self) private var store
    @State private var selectedHour: HourlyForecastItem?

    let day: DailyForecastItem

    private var matchingHours: [HourlyForecastItem] {
        store.snapshot.hourly.filter {
            Calendar.autoupdatingCurrent.isDate($0.date, inSameDayAs: day.date)
        }
    }

    var body: some View {
        ZStack {
            WeatherBackdrop(style: backdropStyle)

            ScrollView {
                LazyVStack(spacing: 16) {
                    hero

                    ForecastPeriodCard(
                        title: "Daytime",
                        description: day.daytimeDescription,
                        temperatureLabel: "High",
                        temperature: day.daytimeHigh,
                        precipitationChance: day.daytimePrecipitationChance,
                        wind: day.windDescription,
                        icon: day.daytimeCondition.symbolName,
                        unitSystem: store.unitSystem
                    )

                    if let nightDescription = day.nighttimeDescription {
                        ForecastPeriodCard(
                            title: "Overnight",
                            description: nightDescription,
                            temperatureLabel: "Low",
                            temperature: day.overnightLow,
                            precipitationChance: day.nighttimePrecipitationChance,
                            wind: day.windDescription,
                            icon: "moon.stars.fill",
                            unitSystem: store.unitSystem
                        )
                    }

                    if !matchingHours.isEmpty {
                        WeatherCard {
                            VStack(alignment: .leading, spacing: 14) {
                                SectionHeader(title: "Hours")

                                HourlyDetailRows(
                                    items: matchingHours,
                                    unitSystem: store.unitSystem,
                                    onSelect: { selectedHour = $0 }
                                )
                            }
                        }
                    }

                    WeatherCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Forecast source")
                            SourceFreshnessView(metadata: day.source)
                        }
                    }
                }
                .padding(.horizontal, WeatherTheme.horizontalPadding)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(WeatherFormatters.fullDay(day.date))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .sheet(item: $selectedHour) { hour in
            HourlyForecastDetailSheet(item: hour)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Text(day.date.formatted(.dateTime.month(.wide).day()))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(WeatherTheme.secondaryText)

            Image(systemName: day.daytimeCondition.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 48))

            HStack(alignment: .firstTextBaseline, spacing: 20) {
                VStack(spacing: 3) {
                    Text(
                        WeatherFormatters.temperature(
                            day.daytimeHigh,
                            unitSystem: store.unitSystem
                        )
                    )
                    .font(.system(size: 46, weight: .medium, design: .rounded))

                    Text("Day high")
                        .font(.caption)
                        .foregroundStyle(WeatherTheme.secondaryText)
                }

                VStack(spacing: 3) {
                    Text(
                        WeatherFormatters.temperature(
                            day.overnightLow,
                            unitSystem: store.unitSystem
                        )
                    )
                    .font(.system(size: 34, weight: .regular, design: .rounded))
                    .foregroundStyle(WeatherTheme.secondaryText)

                    Text("Overnight low")
                        .font(.caption)
                        .foregroundStyle(WeatherTheme.tertiaryText)
                }
            }
            .foregroundStyle(WeatherTheme.primaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var backdropStyle: WeatherBackdropStyle {
        switch day.daytimeCondition {
        case .rain, .heavyRain, .thunderstorm: .rain
        case .cloudy, .fog: .cloudy
        default: .clear
        }
    }
}

private struct ForecastPeriodCard: View {
    let title: String
    let description: String
    let temperatureLabel: String
    let temperature: Double?
    let precipitationChance: Double?
    let wind: String?
    let icon: String
    let unitSystem: WeatherUnitSystem

    var body: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionHeader(title: title)
                    Spacer()
                    Image(systemName: icon)
                        .symbolRenderingMode(.multicolor)
                }

                Text(description)
                    .font(.body)
                    .foregroundStyle(WeatherTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 22) {
                    ForecastFact(
                        label: temperatureLabel,
                        value: WeatherFormatters.temperature(
                            temperature,
                            unitSystem: unitSystem
                        ),
                        icon: "thermometer.medium"
                    )

                    ForecastFact(
                        label: "Precipitation",
                        value: WeatherFormatters.percent(precipitationChance),
                        icon: "drop.fill"
                    )

                    if let wind {
                        ForecastFact(
                            label: "Wind",
                            value: wind,
                            icon: "wind"
                        )
                    }
                }
            }
        }
    }
}

private struct ForecastFact: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(WeatherTheme.secondaryText)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WeatherTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
