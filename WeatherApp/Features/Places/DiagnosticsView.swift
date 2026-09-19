import SwiftUI

struct DiagnosticsView: View {
    @Environment(WeatherStore.self) private var store

    private var sourceGroups: [(String, WeatherSourceMetadata)] {
        var groups: [(String, WeatherSourceMetadata)] = [
            ("Current conditions", store.snapshot.current.source)
        ]

        if let source = store.snapshot.hourly.first?.source {
            groups.append(("Hourly forecast", source))
        }

        if let source = store.snapshot.daily.first?.source {
            groups.append(("Daily forecast", source))
        }

        if let source = store.snapshot.minutePrecipitation.first?.source {
            groups.append(("Next-hour precipitation", source))
        }

        if let source = store.snapshot.solar?.source {
            groups.append(("UV / solar", source))
        }

        return groups
    }

    var body: some View {
        ZStack {
            WeatherBackdrop(style: .night)

            ScrollView {
                LazyVStack(spacing: 16) {
                    locationCard
                    requestStateCard

                    ForEach(Array(sourceGroups.enumerated()), id: \.offset) { _, group in
                        DiagnosticSourceCard(title: group.0, metadata: group.1)
                    }

                    WeatherCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Alert state")

                            DiagnosticValueRow(
                                label: "Loaded alerts",
                                value: String(store.snapshot.alerts.count)
                            )

                            DiagnosticValueRow(
                                label: "Snapshot fetched",
                                value: formatted(store.snapshot.fetchedAt)
                            )
                        }
                    }
                }
                .padding(.horizontal, WeatherTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await store.refresh()
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }

    private var locationCard: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Selected location")

                DiagnosticValueRow(
                    label: "Name",
                    value: store.snapshot.location.displayName
                )
                DiagnosticValueRow(
                    label: "Latitude",
                    value: String(format: "%.5f", store.snapshot.location.latitude)
                )
                DiagnosticValueRow(
                    label: "Longitude",
                    value: String(format: "%.5f", store.snapshot.location.longitude)
                )
                DiagnosticValueRow(
                    label: "Current location",
                    value: store.snapshot.location.isCurrentLocation ? "Yes" : "No"
                )
            }
        }
    }

    private var requestStateCard: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Repository state")

                DiagnosticValueRow(label: "Mode", value: "Preview")
                DiagnosticValueRow(
                    label: "Refreshing",
                    value: store.isRefreshing ? "Yes" : "No"
                )
                DiagnosticValueRow(
                    label: "Last error",
                    value: store.lastRefreshError ?? "None"
                )

                Text("Live mode remains intentionally disabled until NWS fixtures, WeatherKit entitlements, and the NOAA radar service are verified.")
                    .font(.caption)
                    .foregroundStyle(WeatherTheme.tertiaryText)
                    .padding(.top, 3)
            }
        }
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .standard)
    }
}

private struct DiagnosticSourceCard: View {
    let title: String
    let metadata: WeatherSourceMetadata

    var body: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: title)

                DiagnosticValueRow(
                    label: "Provider",
                    value: metadata.provider.rawValue
                )
                DiagnosticValueRow(
                    label: "Product",
                    value: metadata.productName
                )
                DiagnosticValueRow(
                    label: "Source",
                    value: metadata.sourceName ?? "—"
                )
                DiagnosticValueRow(
                    label: "Observed",
                    value: formatted(metadata.observedAt)
                )
                DiagnosticValueRow(
                    label: "Issued",
                    value: formatted(metadata.issuedAt)
                )
                DiagnosticValueRow(
                    label: "Valid from",
                    value: formatted(metadata.validFrom)
                )
                DiagnosticValueRow(
                    label: "Valid to",
                    value: formatted(metadata.validTo)
                )
                DiagnosticValueRow(
                    label: "Fetched",
                    value: formatted(metadata.fetchedAt)
                )
                DiagnosticValueRow(
                    label: "Expires",
                    value: formatted(metadata.expiresAt)
                )
                DiagnosticValueRow(
                    label: "Expired",
                    value: metadata.isExpired ? "Yes" : "No"
                )
            }
        }
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .standard)
    }
}

private struct DiagnosticValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(WeatherTheme.secondaryText)
                .frame(width: 86, alignment: .leading)

            Spacer(minLength: 0)

            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(WeatherTheme.primaryText)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}
