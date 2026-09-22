import SwiftUI

struct WeatherMetricDetailSheet: View {
    @Environment(WeatherStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let metric: WeatherMetric
    let current: CurrentConditions
    let solar: SolarWeather?

    var body: some View {
        NavigationStack {
            ZStack {
                WeatherBackdrop(style: .calm)

                ScrollView {
                    VStack(spacing: 16) {
                        hero
                        detailCard
                        sourceCard
                    }
                    .padding(WeatherTheme.horizontalPadding)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(title)
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
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(WeatherTheme.accent)
                    .frame(width: 52, height: 52)
                    .background(WeatherTheme.accent.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(primaryValue)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundStyle(WeatherTheme.primaryText)

                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(WeatherTheme.secondaryText)
                }

                Spacer()
            }
        }
    }

    private var detailCard: some View {
        WeatherCard {
            VStack(spacing: 0) {
                SectionHeader(title: "Details")
                    .padding(.bottom, 8)

                ForEach(Array(detailRows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label)
                            .font(.subheadline)
                            .foregroundStyle(WeatherTheme.secondaryText)

                        Spacer()

                        Text(row.value)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(WeatherTheme.primaryText)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 10)

                    if index < detailRows.count - 1 {
                        Divider()
                            .overlay(WeatherTheme.divider)
                    }
                }
            }
        }
    }

    private var sourceCard: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 9) {
                SectionHeader(title: "Source")
                SourceFreshnessView(metadata: source)
                WeatherProviderAttributionView(metadata: source)

                Text("These are provider-supplied weather values. Unit changes are display conversions only.")
                    .font(.caption)
                    .foregroundStyle(WeatherTheme.tertiaryText)
            }
        }
    }

    private var title: String {
        switch metric {
        case .wind: "Wind"
        case .humidity: "Humidity"
        case .uv: "UV Index"
        case .sun: "Sunrise & Sunset"
        case .visibility: "Visibility"
        case .pressure: "Pressure"
        }
    }

    private var icon: String {
        switch metric {
        case .wind: "wind"
        case .humidity: "humidity.fill"
        case .uv: "sun.max.fill"
        case .sun: "sunset.fill"
        case .visibility: "eye.fill"
        case .pressure: "gauge.with.dots.needle.33percent"
        }
    }

    private var primaryValue: String {
        switch metric {
        case .wind:
            WeatherFormatters.wind(
                speed: current.windSpeed,
                direction: current.windDirection,
                unitSystem: store.unitSystem
            )
        case .humidity:
            WeatherFormatters.percent(current.humidity)
        case .uv:
            solar?.uvIndex.map(String.init) ?? "—"
        case .sun:
            solar?.sunset.map(WeatherFormatters.hour) ?? "—"
        case .visibility:
            WeatherFormatters.visibility(
                current.visibilityMiles,
                unitSystem: store.unitSystem
            )
        case .pressure:
            WeatherFormatters.pressure(
                current.pressureMillibars,
                unitSystem: store.unitSystem
            )
        }
    }

    private var summary: String {
        switch metric {
        case .wind: "Current station wind"
        case .humidity: "Current relative humidity"
        case .uv: "Current available UV index"
        case .sun: "Today's solar events"
        case .visibility: "Current observed visibility"
        case .pressure: "Current station pressure"
        }
    }

    private var detailRows: [(label: String, value: String)] {
        switch metric {
        case .wind:
            return [
                ("Direction", current.windDirection ?? "—"),
                (
                    "Speed",
                    WeatherFormatters.wind(
                        speed: current.windSpeed,
                        direction: nil,
                        unitSystem: store.unitSystem
                    )
                ),
                (
                    "Gusts",
                    WeatherFormatters.wind(
                        speed: current.windGust,
                        direction: nil,
                        unitSystem: store.unitSystem
                    )
                )
            ]

        case .humidity:
            return [
                ("Relative humidity", WeatherFormatters.percent(current.humidity)),
                (
                    "Dew point",
                    WeatherFormatters.temperature(
                        current.dewPoint,
                        unitSystem: store.unitSystem
                    )
                )
            ]

        case .uv:
            return [
                ("UV index", solar?.uvIndex.map(String.init) ?? "—")
            ]

        case .sun:
            return [
                ("Sunrise", solar?.sunrise.map(WeatherFormatters.hour) ?? "—"),
                ("Sunset", solar?.sunset.map(WeatherFormatters.hour) ?? "—")
            ]

        case .visibility:
            return [
                (
                    "Visibility",
                    WeatherFormatters.visibility(
                        current.visibilityMiles,
                        unitSystem: store.unitSystem
                    )
                )
            ]

        case .pressure:
            return [
                (
                    "Pressure",
                    WeatherFormatters.pressure(
                        current.pressureMillibars,
                        unitSystem: store.unitSystem
                    )
                )
            ]
        }
    }

    private var source: WeatherSourceMetadata {
        switch metric {
        case .uv, .sun:
            solar?.source ?? current.source
        case .wind, .humidity, .visibility, .pressure:
            current.source
        }
    }
}
