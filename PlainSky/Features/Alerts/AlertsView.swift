import SwiftUI

struct AlertsView: View {
    @Environment(WeatherStore.self) private var store

    var body: some View {
        ZStack {
            WeatherBackdrop(style: store.screenState.alerts.value?.isEmpty == false ? .rain : .clear)

            ScrollView {
                LazyVStack(spacing: 14) {
                    if let error = store.lastRefreshError {
                        RefreshErrorBanner()
                            .accessibilityHint(error)
                    }

                    if store.screenState.alerts.isLoading {
                        checkingState
                    } else if let message = store.screenState.alerts.message {
                        WeatherUnavailableCard(
                            title: "Alert status unavailable",
                            message: message,
                            icon: "exclamationmark.shield.fill"
                        )
                    } else if store.screenState.alerts.value?.isEmpty != false {
                        emptyState
                    } else {
                        activeAlertHeader

                        ForEach(store.screenState.alerts.value ?? []) { alert in
                            NavigationLink {
                                AlertDetailView(alert: alert)
                            } label: {
                                AlertBanner(alert: alert, showsHeadline: true)
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
                    "\(store.screenState.alerts.value?.count ?? 0) active \((store.screenState.alerts.value?.count ?? 0) == 1 ? "alert" : "alerts")",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.headline)
                .foregroundStyle(WeatherTheme.primaryText)

                Text(store.screenState.location.displayName)
                    .font(.subheadline)
                    .foregroundStyle(WeatherTheme.secondaryText)

                Text("Official National Weather Service products are shown without rewriting their hazard instructions.")
                    .font(.caption)
                    .foregroundStyle(WeatherTheme.tertiaryText)
                    .padding(.top, 2)
            }
        }
    }

    private var checkingState: some View {
        WeatherCard {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(WeatherTheme.accent)

                Text("Checking for active alerts")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WeatherTheme.primaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
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

                    Text("The latest successful National Weather Service alert check returned no active alerts for \(store.screenState.location.displayName).")
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
