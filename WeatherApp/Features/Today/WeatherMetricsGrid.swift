import SwiftUI

struct WeatherMetricsGrid: View {
    @Environment(WeatherStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let current: CurrentConditions
    let solar: SolarWeather?

    @State private var selectedMetric: WeatherMetric?

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }

        return [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                metricButton(
                    .wind,
                    icon: "wind",
                    title: "Wind",
                    value: WeatherFormatters.wind(
                        speed: current.windSpeed,
                        direction: current.windDirection,
                        unitSystem: store.unitSystem
                    ),
                    detail: current.windGust.map {
                        "Gusts \(WeatherFormatters.wind(speed: $0, direction: nil, unitSystem: store.unitSystem))"
                    }
                )

                metricButton(
                    .humidity,
                    icon: "humidity.fill",
                    title: "Humidity",
                    value: WeatherFormatters.percent(current.humidity),
                    detail: current.dewPoint.map {
                        "Dew point \(WeatherFormatters.temperature($0, unitSystem: store.unitSystem))"
                    }
                )

                metricButton(
                    .uv,
                    icon: "sun.max.fill",
                    title: "UV index",
                    value: solar?.uvIndex.map(String.init) ?? "—",
                    detail: solar == nil ? "Unavailable" : solar?.source.provider.rawValue
                )

                metricButton(
                    .sun,
                    icon: "sunset.fill",
                    title: "Sunset",
                    value: solar?.sunset.map(WeatherFormatters.hour) ?? "—",
                    detail: solar?.sunrise.map { "Sunrise \(WeatherFormatters.hour($0))" }
                )

                metricButton(
                    .visibility,
                    icon: "eye.fill",
                    title: "Visibility",
                    value: WeatherFormatters.visibility(
                        current.visibilityMiles,
                        unitSystem: store.unitSystem
                    ),
                    detail: current.source.sourceName
                )

                metricButton(
                    .pressure,
                    icon: "gauge.with.dots.needle.33percent",
                    title: "Pressure",
                    value: WeatherFormatters.pressure(
                        current.pressureMillibars,
                        unitSystem: store.unitSystem
                    ),
                    detail: current.source.provider.rawValue
                )
            }

            if let solar {
                WeatherProviderAttributionView(metadata: solar.source)
            }
        }
        .sheet(item: $selectedMetric) { metric in
            WeatherMetricDetailSheet(
                metric: metric,
                current: current,
                solar: solar
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func metricButton(
        _ metric: WeatherMetric,
        icon: String,
        title: String,
        value: String,
        detail: String?
    ) -> some View {
        Button {
            selectedMetric = metric
        } label: {
            MetricCard(
                icon: icon,
                title: title,
                value: value,
                detail: detail
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(title.lowercased()) details")
    }
}

enum WeatherMetric: String, Identifiable {
    case wind
    case humidity
    case uv
    case sun
    case visibility
    case pressure

    var id: Self { self }
}

private struct MetricCard: View {
    let icon: String
    let title: String
    let value: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(WeatherTheme.accent)

                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.6)
                    .foregroundStyle(WeatherTheme.secondaryText)

                Spacer()

                Image(systemName: "chevron.up")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WeatherTheme.tertiaryText)
            }

            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(WeatherTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(WeatherTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(WeatherTheme.cardStroke, lineWidth: 1)
                }
        }
    }
}
