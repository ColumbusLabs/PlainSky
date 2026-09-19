import SwiftUI

struct TodayView: View {
    @Environment(WeatherStore.self) private var store
    @Environment(AppRouter.self) private var router

    private var backdropStyle: WeatherBackdropStyle {
        switch store.snapshot.current.condition {
        case .rain, .heavyRain, .thunderstorm:
            .rain
        case .cloudy, .fog:
            .cloudy
        default:
            .clear
        }
    }

    var body: some View {
        ZStack {
            WeatherBackdrop(style: backdropStyle)

            ScrollView {
                LazyVStack(spacing: 16) {
                    TodayLocationHeader()

                    RefreshErrorBanner()

                    CurrentConditionsHero(
                        current: store.snapshot.current,
                        today: store.snapshot.daily.first
                    )

                    if store.snapshot.alerts.isEmpty,
                       let alertMessage = store.snapshot.availability(for: .alerts).message {
                        WeatherUnavailableCard(
                            title: "Alert status unavailable",
                            message: alertMessage,
                            icon: "exclamationmark.shield.fill"
                        )
                    }

                    ForEach(store.snapshot.alerts.prefix(2)) { alert in
                        NavigationLink {
                            AlertDetailView(alert: alert)
                        } label: {
                            AlertBanner(alert: alert)
                        }
                        .buttonStyle(.plain)
                    }

                    if store.snapshot.alerts.count > 2 {
                        NavigationLink {
                            AlertsView()
                        } label: {
                            Text("View all \(store.snapshot.alerts.count) active alerts")
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
                        location: store.snapshot.location,
                        availability: store.snapshot.availability(for: .radar),
                        onOpen: router.showRadar
                    )

                    WeatherMetricsGrid(
                        current: store.snapshot.current,
                        solar: store.snapshot.solar
                    )

                    SourceSummaryCard(snapshot: store.snapshot)
                }
                .padding(.horizontal, WeatherTheme.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await store.refresh()
            }
        }
        .overlay {
            if store.isShowingPlaceholderData {
                LiveWeatherLoadingView(title: "Loading live weather")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var minutePrecipitationSection: some View {
        if !store.snapshot.minutePrecipitation.isEmpty {
            NextHourPrecipitationCard(samples: store.snapshot.minutePrecipitation)
        } else if let message = store.snapshot
            .availability(for: .minutePrecipitation)
            .message {
            WeatherUnavailableCard(
                title: "Next-hour precipitation unavailable",
                message: message,
                icon: "drop.triangle"
            )
        }
    }

    @ViewBuilder
    private var hourlySection: some View {
        if store.snapshot.hourly.isEmpty {
            WeatherUnavailableCard(
                title: "Hourly forecast unavailable",
                message: store.snapshot
                    .availability(for: .hourlyForecast)
                    .message ?? "No hourly forecast data was returned.",
                icon: "clock.badge.exclamationmark"
            )
        } else {
            HourlyForecastStrip(
                items: Array(store.snapshot.hourly.prefix(12)),
                onSeeAll: router.showHourlyForecast
            )
        }
    }

    @ViewBuilder
    private var dailySection: some View {
        if store.snapshot.daily.isEmpty {
            WeatherUnavailableCard(
                title: "Daily forecast unavailable",
                message: store.snapshot
                    .availability(for: .dailyForecast)
                    .message ?? "No daily forecast data was returned.",
                icon: "calendar.badge.exclamationmark"
            )
        } else {
            DailyForecastPreview(
                items: Array(store.snapshot.daily.prefix(3)),
                onSeeAll: router.showDailyForecast
            )
        }
    }
}

private struct TodayLocationHeader: View {
    @Environment(WeatherStore.self) private var store

    var body: some View {
        HStack {
            Menu {
                ForEach(store.savedLocations) { location in
                    Button {
                        store.selectAndRefresh(location)
                    } label: {
                        Label(
                            location.displayName,
                            systemImage: location.isCurrentLocation ? "location.fill" : "mappin"
                        )
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.snapshot.location.name)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(WeatherTheme.primaryText)

                        if !store.snapshot.location.region.isEmpty {
                            Text(store.snapshot.location.region)
                                .font(.caption)
                                .foregroundStyle(WeatherTheme.secondaryText)
                        }
                    }

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WeatherTheme.secondaryText)
                }
            }

            Spacer()

            if store.isRefreshing {
                ProgressView()
                    .tint(WeatherTheme.primaryText)
                    .frame(width: 40, height: 40)
                    .accessibilityLabel("Refreshing weather")
            } else {
                NavigationLink {
                    AlertsView()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                            .foregroundStyle(WeatherTheme.primaryText)

                        if !store.snapshot.alerts.isEmpty {
                            Circle()
                                .fill(.red)
                                .frame(width: 9, height: 9)
                                .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                        } else if store.snapshot.availability(for: .alerts).message != nil {
                            Circle()
                                .fill(.orange)
                                .frame(width: 9, height: 9)
                                .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                        }
                    }
                }
                .accessibilityLabel(alertAccessibilityLabel)
            }
        }
        .padding(.top, 4)
    }

    private var alertAccessibilityLabel: String {
        if !store.snapshot.alerts.isEmpty {
            return "\(store.snapshot.alerts.count) active weather alerts"
        }

        if store.snapshot.availability(for: .alerts).message != nil {
            return "Weather alert status unavailable"
        }

        return "Weather alerts"
    }
}
