import SwiftUI

struct WeatherMetricsGrid: View {
    let current: CurrentConditions
    let solar: SolarWeather?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            MetricCard(
                icon: "wind",
                title: "Wind",
                value: WeatherFormatters.wind(
                    speed: current.windSpeed,
                    direction: current.windDirection
                ),
                detail: current.windGust.map { "Gusts \(Int($0.rounded())) mph" }
            )

            MetricCard(
                icon: "humidity.fill",
                title: "Humidity",
                value: WeatherFormatters.percent(current.humidity),
                detail: current.dewPoint.map { "Dew point \(WeatherFormatters.temperature($0))" }
            )

            MetricCard(
                icon: "sun.max.fill",
                title: "UV index",
                value: solar?.uvIndex.map(String.init) ?? "—",
                detail: "Apple Weather"
            )

            MetricCard(
                icon: "sunset.fill",
                title: "Sunset",
                value: solar?.sunset.map(WeatherFormatters.hour) ?? "—",
                detail: solar?.sunrise.map { "Sunrise \(WeatherFormatters.hour($0))" }
            )

            MetricCard(
                icon: "eye.fill",
                title: "Visibility",
                value: WeatherFormatters.visibility(current.visibilityMiles),
                detail: current.source.sourceName
            )

            MetricCard(
                icon: "gauge.with.dots.needle.33percent",
                title: "Pressure",
                value: WeatherFormatters.pressure(current.pressureMillibars),
                detail: "Station observation"
            )
        }
    }
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
            }

            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(WeatherTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(WeatherTheme.secondaryText)
                    .lineLimit(1)
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
