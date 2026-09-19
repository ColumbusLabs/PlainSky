import SwiftUI

struct ForecastView: View {
    @Environment(WeatherStore.self) private var store
    @State private var mode: ForecastMode = .daily

    var body: some View {
        ZStack {
            WeatherBackdrop(style: .clear)

            ScrollView {
                LazyVStack(spacing: 16) {
                    header

                    Picker("Forecast view", selection: $mode) {
                        ForEach(ForecastMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Forecast view")

                    switch mode {
                    case .daily:
                        DailyForecastList(items: store.snapshot.daily)
                    case .hourly:
                        HourlyForecastView(items: store.snapshot.hourly)
                    }

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

enum ForecastMode: String, CaseIterable, Identifiable {
    case daily
    case hourly

    var id: Self { self }

    var title: String {
        switch self {
        case .daily: "Daily"
        case .hourly: "Hourly"
        }
    }
}
