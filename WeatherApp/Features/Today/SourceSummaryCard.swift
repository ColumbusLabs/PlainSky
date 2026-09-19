import SwiftUI

struct SourceSummaryCard: View {
    let snapshot: WeatherSnapshot

    var body: some View {
        NavigationLink {
            DiagnosticsView()
        } label: {
            WeatherCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionHeader(title: "Sources & freshness")

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WeatherTheme.tertiaryText)
                    }

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

                    Text("Every weather value keeps its provider and original observation or forecast time. Tap for full diagnostics.")
                        .font(.caption)
                        .foregroundStyle(WeatherTheme.tertiaryText)
                        .padding(.top, 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens detailed provider freshness and availability")
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
