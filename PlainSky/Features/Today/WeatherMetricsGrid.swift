import SwiftUI

struct WeatherMetricsGrid: View {
    @Environment(WeatherStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let current: WeatherProductState<CurrentConditions>
    let uvIndex: WeatherProductState<Int>
    let solar: WeatherProductState<SolarWeather>

    @State private var selectedMetric: WeatherMetric?

    private var columns: [GridItem] {
        let count: Int
        if dynamicTypeSize.isAccessibilitySize {
            count = 1
        } else if dynamicTypeSize >= .xLarge {
            count = 2
        } else {
            count = 3
        }

        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    var body: some View {
        let currentValue = current.value
        let solarValue = solar.value

        WeatherCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Weather Metrics")

                LazyVGrid(columns: columns, spacing: 8) {
                    metricButton(
                        .wind,
                        icon: "wind",
                        title: "Wind",
                        value: WeatherFormatters.wind(
                            speed: currentValue?.windSpeed,
                            direction: nil,
                            unitSystem: store.unitSystem
                        ),
                        detail: currentValue?.windDirection ?? metricStatus(current)
                    )

                    metricButton(
                        .humidity,
                        icon: "drop.fill",
                        title: "Humidity",
                        value: WeatherFormatters.percent(currentValue?.humidity),
                        detail: currentValue == nil ? metricStatus(current) : nil
                    )

                    metricButton(
                        .uv,
                        icon: "sun.max.fill",
                        title: "UV Index",
                        value: uvIndex.value.map(String.init) ?? "—",
                        detail: uvDetail
                    )

                    metricButton(
                        .visibility,
                        icon: "eye.fill",
                        title: "Visibility",
                        value: WeatherFormatters.visibility(
                            currentValue?.visibilityMiles,
                            unitSystem: store.unitSystem
                        ),
                        detail: currentValue == nil ? metricStatus(current) : nil
                    )

                    metricButton(
                        .sun,
                        icon: "sunset.fill",
                        title: "Sunset",
                        value: solarValue?.sunset.map(WeatherFormatters.hour) ?? "—",
                        detail: solarValue == nil ? metricStatus(solar) : nil
                    )

                    metricButton(
                        .pressure,
                        icon: "gauge.with.dots.needle.33percent",
                        title: "Pressure",
                        value: WeatherFormatters.pressure(
                            currentValue?.pressureMillibars,
                            unitSystem: store.unitSystem
                        ),
                        detail: currentValue == nil ? metricStatus(current) : nil
                    )
                }
            }
        }
        .sheet(item: $selectedMetric) { metric in
            if let currentValue {
                WeatherMetricDetailSheet(
                    metric: metric,
                    current: currentValue,
                    solar: solarValue
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var uvDetail: String? {
        if let uvIndex = uvIndex.value {
            return WeatherFormatters.uvCategory(uvIndex)
        }

        return metricStatus(uvIndex)
    }

    private func metricStatus<Value: Sendable>(
        _ state: WeatherProductState<Value>
    ) -> String {
        if state.isLoading { return "Loading…" }
        if let message = state.message { return message }
        return "Unavailable"
    }

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
            MetricTile(
                icon: icon,
                title: title,
                value: value,
                detail: detail
            )
        }
        .buttonStyle(.plain)
        .disabled(current.value == nil)
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

private struct MetricTile: View {
    let icon: String
    let title: String
    let value: String
    let detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WeatherTheme.accent)
                .frame(width: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(WeatherTheme.secondaryText)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WeatherTheme.primaryText)

                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(WeatherTheme.secondaryText)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .weatherInsetSurface()
        .accessibilityElement(children: .combine)
    }
}
