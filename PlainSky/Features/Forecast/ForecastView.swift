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
            WeatherBackdrop(style: .current(for: store.snapshot))

            ScrollView {
                LazyVStack(spacing: WeatherTheme.sectionSpacing) {
                    header
                        .padding(.bottom, 10)

                    ForecastModePicker(selection: mode)

                    RefreshErrorBanner()

                    forecastContent
                }
                .padding(.horizontal, WeatherTheme.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await store.refresh()
            }
        }
        .overlay {
            if store.isShowingPlaceholderData {
                LiveWeatherLoadingView(title: "Loading live forecast")
            }
        }
        .navigationTitle("Forecast")
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
        let current = store.snapshot.current

        return HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Forecast")
                    .font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader)

                LocationMenu {
                    HStack(spacing: 6) {
                        Text(store.snapshot.location.displayName)
                            .font(.body.weight(.medium))
                            .lineLimit(1)

                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(WeatherTheme.heroText)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 8) {
                    ConditionIcon(
                        condition: current.condition,
                        isDaytime: WeatherDaylight.isDaytime(Date(), solar: store.snapshot.solar),
                        size: 30
                    )

                    Text(WeatherFormatters.temperature(current.temperature, unitSystem: store.unitSystem))
                        .font(.system(size: 40, weight: .semibold))
                        .monospacedDigit()
                }

                Text(current.conditionDescription)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }
        .foregroundStyle(WeatherTheme.heroText)
        .heroTextShadow()
        .padding(.top, 8)
    }
}

private struct ForecastModePicker: View {
    @Binding var selection: ForecastMode
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ForecastMode.allCases) { mode in
                let isSelected = selection == mode

                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        selection = mode
                    }
                } label: {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? WeatherTheme.primaryText : WeatherTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Color.white.opacity(0.92))
                                    .shadow(color: WeatherTheme.shadow, radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .weatherSurface(cornerRadius: 15)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Forecast view")
    }
}
