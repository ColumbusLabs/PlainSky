import SwiftUI

struct AlertDetailView: View {
    let alert: WeatherAlert

    var body: some View {
        ZStack {
            WeatherBackdrop(style: .rain)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    timingCard
                    messageCard

                    if let instructions = alert.instructions, !instructions.isEmpty {
                        WeatherCard {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "What to do")

                                Text(instructions)
                                    .font(.body)
                                    .foregroundStyle(WeatherTheme.primaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    WeatherCard {
                        VStack(alignment: .leading, spacing: 9) {
                            SectionHeader(title: "Official source")

                            if let office = alert.issuingOffice {
                                Text(office)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(WeatherTheme.primaryText)
                            }

                            SourceFreshnessView(metadata: alert.source)

                            Text("This text is displayed from the provider record; the app does not summarize or reinterpret hazard instructions.")
                                .font(.caption)
                                .foregroundStyle(WeatherTheme.tertiaryText)
                        }
                    }
                }
                .padding(.horizontal, WeatherTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Weather Alert")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }

    private var hero: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: severitySymbol)
                        .font(.title2)
                        .foregroundStyle(severityColor)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(alert.event)
                            .font(.title2.bold())
                            .foregroundStyle(WeatherTheme.primaryText)

                        Text(alert.headline)
                            .font(.subheadline)
                            .foregroundStyle(WeatherTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text(alert.severity.rawValue.capitalized)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle(severityColor)
            }
        }
    }

    private var timingCard: some View {
        WeatherCard {
            VStack(spacing: 10) {
                AlertTimingRow(label: "Effective", date: alert.effectiveAt)

                if let expiresAt = alert.expiresAt {
                    Divider().overlay(WeatherTheme.divider)
                    AlertTimingRow(label: "Expires", date: expiresAt)
                }
            }
        }
    }

    private var messageCard: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Details")

                Text(alert.description)
                    .font(.body)
                    .foregroundStyle(WeatherTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var severitySymbol: String {
        switch alert.severity {
        case .extreme, .severe:
            "exclamationmark.triangle.fill"
        case .moderate:
            "exclamationmark.circle.fill"
        case .minor, .unknown:
            "info.circle.fill"
        }
    }

    private var severityColor: Color {
        switch alert.severity {
        case .extreme:
            .red
        case .severe:
            .orange
        case .moderate:
            .yellow
        case .minor, .unknown:
            WeatherTheme.accent
        }
    }
}

private struct AlertTimingRow: View {
    let label: String
    let date: Date

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(WeatherTheme.secondaryText)

            Spacer()

            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WeatherTheme.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }
}
