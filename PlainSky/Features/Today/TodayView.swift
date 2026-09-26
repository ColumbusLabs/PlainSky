import SwiftUI

struct TodayView: View {
    @Environment(WeatherStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        let weather = store.screenState
        let alerts = weather.alerts.value ?? []

        ZStack {
            WeatherBackdrop(style: .current(for: weather))

            ScrollView {
                LazyVStack(spacing: WeatherTheme.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        TodayLocationHeader()

                        CurrentConditionsHero(
                            current: weather.current,
                            today: weather.daily.value?.first
                        )
                    }
                    .padding(.bottom, 10)

                    RefreshErrorBanner()

                    if alerts.isEmpty,
                       !weather.alerts.isLoading,
                       let alertMessage = weather.alerts.message,
                       alertMessage != store.lastRefreshError {
                        WeatherUnavailableCard(
                            title: "Alert status unavailable",
                            message: alertMessage,
                            icon: "exclamationmark.shield.fill"
                        )
                    }

                    ForEach(alerts.prefix(2)) { alert in
                        NavigationLink {
                            AlertDetailView(alert: alert)
                        } label: {
                            AlertBanner(alert: alert)
                        }
                        .buttonStyle(.plain)
                    }

                    if alerts.count > 2 {
                        NavigationLink {
                            AlertsView()
                        } label: {
                            Text("View all \(alerts.count) active alerts")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(WeatherTheme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                    }

                    minutePrecipitationSection
                    hourlySection
                    dailySection

                    RadarPreviewCard(
                        location: weather.location,
                        availability: weather.radar.availability,
                        onOpen: router.showRadar
                    )

                    WeatherMetricsGrid(
                        current: weather.current,
                        uvIndex: weather.uvIndex,
                        solar: weather.solarEvents
                    )
                }
                .padding(.horizontal, WeatherTheme.horizontalPadding)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await store.refresh()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var minutePrecipitationSection: some View {
        let state = store.screenState.minutePrecipitation
        if let samples = state.value, !samples.isEmpty {
            NextHourPrecipitationCard(samples: samples)
        } else if state.isLoading {
            WeatherLoadingCard(title: "Checking next-hour precipitation")
        } else if let message = state.message, message != store.lastRefreshError {
            WeatherUnavailableCard(title: "Next-hour precipitation unavailable", message: message, icon: "drop.triangle")
        }
    }

    @ViewBuilder
    private var hourlySection: some View {
        let state = store.screenState.hourly
        if state.isLoading {
            WeatherLoadingCard(title: "Loading hourly forecast")
        } else if let items = state.value, !items.isEmpty {
            HourlyForecastStrip(items: Array(items.prefix(12)))
        } else {
            WeatherUnavailableCard(
                title: "Hourly forecast unavailable",
                message: state.message ?? "No hourly forecast data was returned.",
                icon: "clock.badge.exclamationmark"
            )
        }
    }

    @ViewBuilder
    private var dailySection: some View {
        let state = store.screenState.daily
        if state.isLoading {
            WeatherLoadingCard(title: "Loading daily forecast")
        } else if let items = state.value, !items.isEmpty {
            DailyForecastPreview(
                items: Array(items.prefix(5)),
                onSeeAll: router.showDailyForecast
            )
        } else {
            WeatherUnavailableCard(
                title: "Daily forecast unavailable",
                message: state.message ?? "No daily forecast data was returned.",
                icon: "calendar.badge.exclamationmark"
            )
        }
    }
}

private struct TodayLocationHeader: View {
    @Environment(WeatherStore.self) private var store

    var body: some View {
        HStack(alignment: .top) {
            LocationMenu {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(store.screenState.location.name)
                            .font(.title.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Image(systemName: "chevron.down")
                            .font(.headline.weight(.semibold))
                    }

                    if !store.screenState.location.region.isEmpty {
                        Text(store.screenState.location.region)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(WeatherTheme.heroSecondaryText)
                    }
                }
                .foregroundStyle(WeatherTheme.heroText)
                .heroTextShadow()
            }

            Spacer(minLength: 12)

            if store.isRefreshing {
                ProgressView()
                    .tint(WeatherTheme.heroText)
                    .frame(width: 40, height: 40)
                    .accessibilityLabel("Refreshing weather")
            } else if activeAlertCount > 0 {
                NavigationLink {
                    AlertsView()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(WeatherTheme.heroText)
                            .frame(width: 40, height: 40)
                            .background {
                                Circle()
                                    .fill(Color.white.opacity(0.24))
                                    .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                            }

                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    }
                }
                .accessibilityLabel(
                    "\(activeAlertCount) active weather \(activeAlertCount == 1 ? "alert" : "alerts")"
                )
            }
        }
        .padding(.top, 8)
    }

    /// The bell only appears when there is something to open. Alert-check
    /// failures are surfaced inline on the Today screen instead.
    private var activeAlertCount: Int {
        store.screenState.alerts.value?.count ?? 0
    }
}
