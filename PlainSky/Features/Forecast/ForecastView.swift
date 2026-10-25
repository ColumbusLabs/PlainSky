import SwiftUI

struct ForecastView: View {
    @Environment(WeatherStore.self) private var store
    @Environment(AppRouter.self) private var router

    /// Height of everything above the forecast content. The daily list uses the
    /// rest of the screen so its rows fill the space on any phone size.
    @State private var chromeHeight: CGFloat = 0

    private let topPadding: CGFloat = 4
    private let bottomPadding: CGFloat = 24

    private var mode: Binding<ForecastMode> {
        Binding(
            get: { router.forecastMode },
            set: { router.forecastMode = $0 }
        )
    }

    var body: some View {
        ZStack {
            WeatherBackdrop(style: .current(for: store.screenState))

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: WeatherTheme.sectionSpacing) {
                        VStack(spacing: WeatherTheme.sectionSpacing) {
                            header
                                .padding(.bottom, 10)

                            if let source = store.screenState.current.validation?.source,
                               source.provider == .weatherKit,
                               source.attributionLegalURL != nil {
                                WeatherCard {
                                    WeatherProviderAttributionView(metadata: source)
                                }
                            }

                            ForecastModePicker(selection: mode)

                            RefreshErrorBanner()
                        }
                        .background {
                            GeometryReader { chrome in
                                Color.clear.onChange(of: chrome.size.height, initial: true) { _, height in
                                    chromeHeight = height
                                }
                            }
                        }

                        forecastContent(
                            // Wait for the first measurement so rows don't flash oversized.
                            availableHeight: chromeHeight > 0
                                ? proxy.size.height - topPadding - bottomPadding
                                    - chromeHeight - WeatherTheme.sectionSpacing
                                : 0
                        )
                    }
                    .padding(.horizontal, WeatherTheme.horizontalPadding)
                    .padding(.top, topPadding)
                    .padding(.bottom, bottomPadding)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await store.refresh()
                }
            }
        }
        .navigationTitle("Forecast")
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func forecastContent(availableHeight: CGFloat) -> some View {
        switch router.forecastMode {
        case .daily:
            if let daily = store.screenState.daily.value {
                DailyForecastList(items: daily, minimumHeight: availableHeight)
            } else if store.screenState.daily.isLoading {
                WeatherLoadingCard(title: "Loading daily forecast")
            } else {
                WeatherUnavailableCard(
                    title: "Daily forecast unavailable",
                    message: store.screenState.daily.message
                        ?? "No daily forecast data was returned."
                )
            }

        case .hourly:
            if let hourly = store.screenState.hourly.value {
                HourlyForecastView(items: hourly)
            } else if store.screenState.hourly.isLoading {
                WeatherLoadingCard(title: "Loading hourly forecast")
            } else {
                WeatherUnavailableCard(
                    title: "Hourly forecast unavailable",
                    message: store.screenState.hourly.message
                        ?? "No hourly forecast data was returned."
                )
            }
        }
    }

    private var header: some View {
        let current = store.screenState.current.value

        return HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Forecast")
                    .font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader)

                LocationMenu {
                    HStack(spacing: 6) {
                        Text(store.screenState.location.displayName)
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
                if let current {
                    HStack(spacing: 8) {
                        ConditionIcon(
                            condition: current.condition,
                            isDaytime: WeatherDaylight.isDaytime(
                                Date(),
                                solar: store.screenState.solarEvents.value
                            ),
                            size: 30
                        )

                        Text(WeatherFormatters.temperature(
                            current.temperature,
                            unitSystem: store.unitSystem
                        ))
                        .font(.system(size: 40, weight: .semibold))
                        .monospacedDigit()
                    }

                    Text(current.conditionDescription)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                } else {
                    Text("—")
                        .font(.system(size: 40, weight: .semibold))
                        .monospacedDigit()
                    Text(store.screenState.current.isLoading
                        ? "Checking conditions"
                        : "Current conditions unavailable")
                        .font(.caption)
                        .lineLimit(1)
                }
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
