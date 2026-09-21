import SwiftUI

struct AlertsView: View {
    @Environment(WeatherStore.self) private var store

    private var alertAvailability: WeatherProductAvailability {
        store.snapshot.availability(for: .alerts)
    }

    var body: some View {
        ZStack {
            WeatherBackdrop(style: store.snapshot.alerts.isEmpty ? .clear : .rain)

            ScrollView {
                LazyVStack(spacing: 14) {
                    if let error = store.lastRefreshError {
                        RefreshErrorBanner()
                            .accessibilityHint(error)
                    }

                    if let message = alertAvailability.message {
                        WeatherUnavailableCard(
                            title: "Alert status unavailable",
                            message: message,
                            icon: "exclamationmark.shield.fill"
                        )
                    } else if store.snapshot.alerts.isEmpty {
                        emptyState
                    } else {
                        activeAlertHeader

                        ForEach(store.snapshot.alerts) { alert in
                            NavigationLink {
                                AlertDetailView(alert: alert)
                            } label: {
                                AlertBanner(alert: alert)
                            }
                            .buttonStyle(.plain)
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
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }

    private var activeAlertHeader: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 7) {
                Label(
                    "\(store.snapshot.alerts.count) active \(store.snapshot.alerts.count == 1 ? "alert" : "alerts")",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.headline)
                .foregroundStyle(WeatherTheme.primaryText)

                Text(store.snapshot.location.displayName)
                    .font(.subheadline)
                    .foregroundStyle(WeatherTheme.secondaryText)

                Text("Official National Weather Service products are shown without rewriting their hazard instructions.")
                    .font(.caption)
                    .foregroundStyle(WeatherTheme.tertiaryText)
                    .padding(.top, 2)
            }
        }
    }

    private var emptyState: some View {
        WeatherCard {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(WeatherTheme.accent)

                VStack(spacing: 6) {
                    Text("No active alerts")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(WeatherTheme.primaryText)

                    Text("The latest successful National Weather Service alert check returned no active alerts for \(store.snapshot.location.displayName).")
                        .font(.subheadline)
                        .foregroundStyle(WeatherTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                Text("Provider failures are shown as unavailable and are never converted into an all-clear.")
                    .font(.caption)
                    .foregroundStyle(WeatherTheme.tertiaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
        }
    }
}
