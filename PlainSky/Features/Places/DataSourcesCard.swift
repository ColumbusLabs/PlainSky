import SwiftUI

struct DataSourcesCard: View {
    let snapshot: WeatherSnapshot

    /// Apple requires its Weather mark and legal link to be shown when WeatherKit data is used.
    private var weatherKitSource: WeatherSourceMetadata? {
        [
            snapshot.current.source,
            snapshot.minutePrecipitation.first?.source,
            snapshot.solar?.source,
            snapshot.hourly.first?.source,
            snapshot.daily.first?.source
        ]
        .compactMap { $0 }
        .first { $0.provider == .weatherKit && $0.attributionLegalURL != nil }
    }

    var body: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Data Sources")

                SourceRow(title: "Current conditions", metadata: snapshot.current.source)

                if let forecastSource = snapshot.hourly.first?.source {
                    Divider().overlay(WeatherTheme.divider)
                    SourceRow(title: "Forecast", metadata: forecastSource)
                }

                if let minuteSource = snapshot.minutePrecipitation.first?.source {
                    Divider().overlay(WeatherTheme.divider)
                    SourceRow(title: "Next-hour precipitation", metadata: minuteSource)
                }

                Text("Forecasts, observations, and alerts from the National Weather Service. Radar from NOAA.")
                    .font(.caption)
                    .foregroundStyle(WeatherTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let weatherKitSource {
                    WeatherProviderAttributionView(metadata: weatherKitSource)
                }
            }
        }
    }
}

private struct SourceRow: View {
    let title: String
    let metadata: WeatherSourceMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WeatherTheme.primaryText)

            SourceFreshnessView(metadata: metadata)
        }
    }
}
