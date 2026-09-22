import SwiftUI

struct WeatherMetricsGrid: View {
    @Environment(WeatherStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let current: CurrentConditions
    let solar: SolarWeather?

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
        WeatherCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Weather Metrics")

                LazyVGrid(columns: columns, spacing: 8) {
                    metricButton(
                        .wind,
                        icon: "wind",
                        title: "Wind",
                        value: WeatherFormatters.wind(
                            speed: current.windSpeed,
                            direction: nil,
                            unitSystem: store.unitSystem
                        ),
                        detail: current.windDirection
                    )

                    metricButton(
                        .humidity,
                        icon: "drop.fill",
                        title: "Humidity",
                        value: WeatherFormatters.percent(current.humidity),
                        detail: nil
                    )

                    metricButton(
                        .uv,
                        icon: "sun.max.fill",
                        title: "UV Index",
                        value: solar?.uvIndex.map(String.init) ?? "—",
                        detail: uvDetail
                    )

                    metricButton(
                        .visibility,
                        icon: "eye.fill",
                        title: "Visibility",
                        value: WeatherFormatters.visibility(
                            current.visibilityMiles,
                            unitSystem: store.unitSystem
                        ),
                        detail: nil
                    )

                    metricButton(
                        .sun,
                        icon: "sunset.fill",
                        title: "Sunset",
                        value: solar?.sunset.map(WeatherFormatters.hour) ?? "—",
                        detail: solar == nil ? pendingDetail(for: .solarEvents) : nil
                    )

                    metricButton(
                        .pressure,
                        icon: "gauge.with.dots.needle.33percent",
                        title: "Pressure",
                        value: WeatherFormatters.pressure(
                            current.pressureMillibars,
                            unitSystem: store.unitSystem
                        ),
                        detail: nil
                    )
                }
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

    private var uvDetail: String? {
        if let uvIndex = solar?.uvIndex {
            return WeatherFormatters.uvCategory(uvIndex)
        }

        return pendingDetail(for: .uvIndex)
    }

    private func pendingDetail(for product: WeatherProduct) -> String {
        store.snapshot.availability(for: product).isLoading
            ? "Loading…"
            : "Unavailable"
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
