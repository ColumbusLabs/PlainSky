import SwiftUI

struct TodayView: View {
    @Environment(WeatherStore.self) private var store

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

                    CurrentConditionsHero(
                        current: store.snapshot.current,
                        today: store.snapshot.daily.first
                    )

                    ForEach(store.snapshot.alerts) { alert in
                        NavigationLink {
                            AlertDetailPlaceholder(alert: alert)
                        } label: {
                            AlertBanner(alert: alert)
                        }
                        .buttonStyle(.plain)
                    }

                    if !store.snapshot.minutePrecipitation.isEmpty {
                        NextHourPrecipitationCard(samples: store.snapshot.minutePrecipitation)
                    }

                    HourlyForecastStrip(items: Array(store.snapshot.hourly.prefix(12)))

                    DailyForecastPreview(items: Array(store.snapshot.daily.prefix(3)))

                    RadarPreviewCard(location: store.snapshot.location)

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
                        store.select(location)
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

            Button {
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
            .accessibilityLabel("Weather alerts")
        }
        .padding(.top, 4)
    }
}

private struct AlertDetailPlaceholder: View {
    let alert: WeatherAlert

    var body: some View {
        ZStack {
            WeatherBackdrop(style: .rain)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(alert.event)
                        .font(.largeTitle.bold())

                    Text(alert.headline)
                        .font(.headline)
                        .foregroundStyle(WeatherTheme.secondaryText)

                    Text(alert.description)
                        .font(.body)

                    if let instructions = alert.instructions {
                        Text("Instructions")
                            .font(.headline)
                            .padding(.top, 8)

                        Text(instructions)
                    }

                    SourceFreshnessView(metadata: alert.source)
                        .padding(.top, 8)
                }
                .foregroundStyle(WeatherTheme.primaryText)
                .padding(WeatherTheme.horizontalPadding)
            }
        }
        .navigationTitle("Alert")
        .navigationBarTitleDisplayMode(.inline)
    }
}
