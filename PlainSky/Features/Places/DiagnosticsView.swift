import SwiftUI

struct DiagnosticsView: View {
    @Environment(WeatherStore.self) private var store

    private var sourceGroups: [(String, WeatherSourceMetadata)] {
        var groups: [(String, WeatherSourceMetadata)] = []

        if let source = store.screenState.current.validation?.source {
            groups.append(("Current conditions", source))
        }

        if let source = store.screenState.hourly.validation?.source {
            groups.append(("Hourly forecast", source))
        }

        if let source = store.screenState.daily.validation?.source {
            groups.append(("Daily forecast", source))
        }

        if let source = store.screenState.minutePrecipitation.validation?.source {
            groups.append(("Next-hour precipitation", source))
        }

        if let source = store.screenState.solarEvents.validation?.source {
            groups.append(("UV / solar", source))
        }

        return groups
    }

    var body: some View {
        ZStack {
            WeatherBackdrop(style: .calm)

            ScrollView {
                LazyVStack(spacing: 16) {
                    locationCard
                    requestStateCard
                    availabilityCard

                    ForEach(Array(sourceGroups.enumerated()), id: \.offset) { _, group in
                        DiagnosticSourceCard(title: group.0, metadata: group.1)
                    }

                    WeatherCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Alert state")

                            DiagnosticValueRow(
                                label: "Loaded alerts",
                                value: store.screenState.alerts.value.map { String($0.count) } ?? "—"
                            )

                            DiagnosticValueRow(
                                label: "Last product validation",
                                value: formatted(latestValidation)
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
                    value: store.screenState.location.displayName
                )
                DiagnosticValueRow(
                    label: "Latitude",
                    value: String(format: "%.5f", store.screenState.location.latitude)
                )
                DiagnosticValueRow(
                    label: "Longitude",
                    value: String(format: "%.5f", store.screenState.location.longitude)
                )
                DiagnosticValueRow(
                    label: "Current location",
                    value: store.screenState.location.isCurrentLocation ? "Yes" : "No"
                )
                DiagnosticValueRow(
                    label: "Units",
                    value: store.unitSystem.title
                )
            }
        }
    }

    private var requestStateCard: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Repository state")

                DiagnosticValueRow(
                    label: "Mode",
                    value: AppEnvironment.dataMode.title
                )
                DiagnosticValueRow(
                    label: "Refreshing",
                    value: store.isRefreshInFlight ? "Yes" : "No"
                )
                DiagnosticValueRow(
                    label: "Last error",
                    value: store.lastRefreshError ?? "None"
                )

                Text(repositoryDescription)
                    .font(.caption)
                    .foregroundStyle(WeatherTheme.tertiaryText)
                    .padding(.top, 3)
            }
        }
    }

    private var repositoryDescription: String {
        switch AppEnvironment.dataMode {
        case .preview:
            return "Deterministic preview data is active for validation."
        case .liveNWS:
            return "NWS observations, forecasts, alerts, and NOAA radar are live. WeatherKit supplements are disabled for this run."
        case .liveNWSWeatherKit:
            return "NWS and NOAA are live, and the app is attempting Apple WeatherKit supplements."
        }
    }

    private var availabilityCard: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Product availability")
                    .padding(.bottom, 8)

                ForEach(Array(WeatherProduct.allCases.enumerated()), id: \.element.id) { index, product in
                    let availability = store.screenState.availability(for: product)

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle()
                            .fill(availabilityColor(availability))
                            .frame(width: 7, height: 7)

                        Text(product.displayName)
                            .font(.caption)
                            .foregroundStyle(WeatherTheme.secondaryText)

                        Spacer(minLength: 8)

                        Text(availabilityLabel(availability))
                            .font(.caption.monospaced())
                            .foregroundStyle(WeatherTheme.primaryText)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.vertical, 8)

                    if index < WeatherProduct.allCases.count - 1 {
                        Divider()
                            .overlay(WeatherTheme.divider)
                    }
                }
            }
        }
    }

    private func availabilityLabel(_ availability: WeatherProductAvailability) -> String {
        switch availability {
        case .available:
            "Available"
        case .loading:
            "Loading"
        case .unsupported:
            "Unsupported"
        case .unavailable:
            "Unavailable"
        }
    }

    private func availabilityColor(_ availability: WeatherProductAvailability) -> Color {
        switch availability {
        case .available:
            WeatherTheme.accent
        case .loading:
            .secondary
        case .unsupported:
            .secondary
        case .unavailable:
            .orange
        }
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    private var latestValidation: Date? {
        [
            store.screenState.current.validation?.validatedAt,
            store.screenState.hourly.validation?.validatedAt,
            store.screenState.daily.validation?.validatedAt,
            store.screenState.alerts.validation?.validatedAt,
            store.screenState.minutePrecipitation.validation?.validatedAt,
            store.screenState.uvIndex.validation?.validatedAt,
            store.screenState.solarEvents.validation?.validatedAt
        ]
        .compactMap { $0 }
        .max()
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
