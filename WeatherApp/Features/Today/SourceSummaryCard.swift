import SwiftUI

struct SourceSummaryCard: View {
    let snapshot: WeatherSnapshot

    var body: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Sources & freshness")

                SourceRow(
                    title: "Current conditions",
                    metadata: snapshot.current.source
                )

                if let hourlySource = snapshot.hourly.first?.source {
                    Divider().overlay(WeatherTheme.divider)
                    SourceRow(title: "Forecast", metadata: hourlySource)
                }

                if let minuteSource = snapshot.minutePrecipitation.first?.source {
                    Divider().overlay(WeatherTheme.divider)
                    SourceRow(title: "Next-hour precipitation", metadata: minuteSource)
                }

                Text("Every weather value keeps its provider and original observation or forecast time. A fresh download never makes an older observation look new.")
                    .font(.caption)
                    .foregroundStyle(WeatherTheme.tertiaryText)
                    .padding(.top, 2)
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
