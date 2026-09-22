import SwiftUI

struct TodayView: View {
    @Environment(WeatherStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        ZStack {
            WeatherBackdrop(style: .current(for: store.snapshot))

            ScrollView {
                LazyVStack(spacing: WeatherTheme.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        TodayLocationHeader()

                        CurrentConditionsHero(
                            current: store.snapshot.current,
                            today: store.snapshot.daily.first
                        )
                    }
                    .padding(.bottom, 10)

                    RefreshErrorBanner()

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
            HourlyForecastStrip(items: Array(store.snapshot.hourly.prefix(12)))
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
                items: Array(store.snapshot.daily.prefix(5)),
                onSeeAll: router.showDailyForecast
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
                        Text(store.snapshot.location.name)
                            .font(.title.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Image(systemName: "chevron.down")
                            .font(.headline.weight(.semibold))
                    }

                    if !store.snapshot.location.region.isEmpty {
                        Text(store.snapshot.location.region)
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
            } else {
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

                        if let badgeColor {
                            Circle()
                                .fill(badgeColor)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        }
                    }
                }
                .accessibilityLabel(alertAccessibilityLabel)
            }
        }
        .padding(.top, 8)
    }

    private var badgeColor: Color? {
        if !store.snapshot.alerts.isEmpty { return .red }
        if store.snapshot.availability(for: .alerts).message != nil { return .orange }
        return nil
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
