import SwiftUI

struct ForecastView: View {
    @Environment(WeatherStore.self) private var store
    @Environment(AppRouter.self) private var router

    private var mode: Binding<ForecastMode> {
        Binding(
            get: { router.forecastMode },
            set: { router.forecastMode = $0 }
        )
    }

    var body: some View {
        ZStack {
            WeatherBackdrop(style: .clear)

            ScrollView {
                LazyVStack(spacing: 16) {
                    header

                    RefreshErrorBanner()

                    Picker("Forecast view", selection: mode) {
                        ForEach(ForecastMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Forecast view")

                    forecastContent

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

    @ViewBuilder
    private var forecastContent: some View {
        switch router.forecastMode {
        case .daily:
            if store.snapshot.daily.isEmpty {
                WeatherUnavailableCard(
                    title: "Daily forecast unavailable",
                    message: store.snapshot
                        .availability(for: .dailyForecast)
                        .message ?? "No daily forecast data was returned."
                )
            } else {
                DailyForecastList(items: store.snapshot.daily)
            }

        case .hourly:
            if store.snapshot.hourly.isEmpty {
                WeatherUnavailableCard(
                    title: "Hourly forecast unavailable",
                    message: store.snapshot
                        .availability(for: .hourlyForecast)
                        .message ?? "No hourly forecast data was returned."
                )
            } else {
                HourlyForecastView(items: store.snapshot.hourly)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Forecast")
                    .font(.largeTitle.bold())
                    .foregroundStyle(WeatherTheme.primaryText)

                Text(store.snapshot.location.displayName)
                    .font(.subheadline)
                    .foregroundStyle(WeatherTheme.secondaryText)
            }

            Spacer()

            Image(systemName: store.snapshot.current.condition.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.title2)
        }
    }
}
