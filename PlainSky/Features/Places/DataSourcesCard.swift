import SwiftUI

struct DataSourcesCard: View {
    let state: WeatherScreenState

    /// Apple requires its Weather mark and legal link to be shown when WeatherKit data is used.
    private var weatherKitSource: WeatherSourceMetadata? {
        [
            state.current.validation?.source,
            state.minutePrecipitation.validation?.source,
            state.solarEvents.validation?.source,
            state.hourly.validation?.source,
            state.daily.validation?.source
        ]
        .compactMap { $0 }
        .first { $0.provider == .weatherKit && $0.attributionLegalURL != nil }
    }

    var body: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Data Sources")

                if let source = state.current.validation?.source {
                    SourceRow(title: "Current conditions", metadata: source)
                }

                if let forecastSource = state.hourly.validation?.source {
                    Divider().overlay(WeatherTheme.divider)
                    SourceRow(title: "Forecast", metadata: forecastSource)
                }

                if let minuteSource = state.minutePrecipitation.validation?.source {
                    Divider().overlay(WeatherTheme.divider)
                    SourceRow(title: "Next-hour precipitation", metadata: minuteSource)
                }

                Text("Forecasts, observations, and alerts from the National Weather Service. Radar from NOAA. Forecast radar is NOAA's HRRR model, provided by the Iowa Environmental Mesonet at Iowa State University.")
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
