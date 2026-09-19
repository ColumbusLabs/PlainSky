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

                    if !store.snapshot.minutePrecipitation.isEmpty {
                        NextHourPrecipitationCard(samples: store.snapshot.minutePrecipitation)
                    }

                    HourlyForecastStrip(
                        items: Array(store.snapshot.hourly.prefix(12)),
                        onSeeAll: router.showHourlyForecast
                    )

                    DailyForecastPreview(
                        items: Array(store.snapshot.daily.prefix(3)),
                        onSeeAll: router.showDailyForecast
                    )

                    RadarPreviewCard(
                        location: store.snapshot.location,
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
        .toolbar(.hidden, for: .navigationBar)
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
                        }
                    }
                }
                .accessibilityLabel(
                    store.snapshot.alerts.isEmpty
                        ? "Weather alerts"
                        : "\(store.snapshot.alerts.count) active weather alerts"
                )
            }
        }
        .padding(.top, 4)
    }
}
