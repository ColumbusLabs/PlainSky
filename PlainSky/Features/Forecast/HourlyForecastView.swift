import Charts
import SwiftUI

struct HourlyForecastView: View {
    @Environment(WeatherStore.self) private var store

    let items: [HourlyForecastItem]

    @State private var metric: HourlyMetric = .temperature
    @State private var horizon: HourlyHorizon = .twentyFour
    @State private var selectedHour: HourlyForecastItem?

    private var visibleItems: [HourlyForecastItem] {
        Array(items.prefix(horizon.hourCount))
    }

    var body: some View {
        VStack(spacing: 16) {
            WeatherCard {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "Hourly Trends")

                    Picker("Metric", selection: $metric) {
                        ForEach(HourlyMetric.allCases) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)

                    forecastChart

                    HStack {
                        Text("Showing")
                            .font(.caption)
                            .foregroundStyle(WeatherTheme.secondaryText)

                        Spacer()

                        Picker("Range", selection: $horizon) {
                            ForEach(HourlyHorizon.allCases) { horizon in
                                Text(horizon.title).tag(horizon)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 180)
                    }
                }
            }

            WeatherCard {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Hour by Hour")

                    HourlyDetailRows(
                        items: visibleItems,
                        unitSystem: store.unitSystem,
                        solar: store.screenState.solarEvents.value,
                        onSelect: { selectedHour = $0 }
                    )
                }
            }
        }
        .sheet(item: $selectedHour) { hour in
            HourlyForecastDetailSheet(item: hour)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var forecastChart: some View {
        switch metric {
        case .temperature:
            Chart(visibleItems) { item in
                let value = WeatherFormatters.temperatureValue(
                    item.temperature,
                    unitSystem: store.unitSystem
                )

                LineMark(
                    x: .value("Time", item.date),
                    y: .value("Temperature", value)
                )
                .foregroundStyle(WeatherTheme.accent)
                .lineStyle(.init(lineWidth: 2.5))

                PointMark(
                    x: .value("Time", item.date),
                    y: .value("Temperature", value)
                )
                .foregroundStyle(WeatherTheme.accent)
            }
            .chartYAxisLabel(store.unitSystem.temperatureSymbol)
            .weatherChartXAxis()
            .weatherChartFrame()

        case .precipitation:
            Chart(visibleItems) { item in
                BarMark(
                    x: .value("Time", item.date),
                    y: .value("Chance", (item.precipitationChance ?? 0) * 100)
                )
                .foregroundStyle(WeatherTheme.accent.gradient)
                .cornerRadius(3)
            }
            .chartYScale(domain: 0...100)
            .chartYAxisLabel("%")
            .weatherChartXAxis()
            .weatherChartFrame()

        case .wind:
            Chart(visibleItems) { item in
                let speed = WeatherFormatters.windSpeedValue(
                    item.windSpeed ?? 0,
                    unitSystem: store.unitSystem
                )

                LineMark(
                    x: .value("Time", item.date),
                    y: .value("Wind", speed)
                )
                .foregroundStyle(WeatherTheme.accent)
                .lineStyle(.init(lineWidth: 2.5))
            }
            .chartYAxisLabel(store.unitSystem.windUnit)
            .weatherChartXAxis()
            .weatherChartFrame()
        }
    }
}

struct HourlyDetailRows: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var timeWidth: CGFloat = 70

    let items: [HourlyForecastItem]
    let unitSystem: WeatherUnitSystem
    var solar: SolarWeather?
    var onSelect: ((HourlyForecastItem) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Group {
                    if let onSelect {
                        Button {
                            onSelect(item)
                        } label: {
                            row(item: item, index: index, showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        row(item: item, index: index, showsChevron: false)
                    }
                }

                if index < items.count - 1 {
                    Divider()
                        .overlay(WeatherTheme.divider)
                }
            }
        }
    }

    private func row(
        item: HourlyForecastItem,
        index: Int,
        showsChevron: Bool
    ) -> some View {
        let isDaytime = WeatherDaylight.isDaytime(item.date, solar: solar)

        return HStack(spacing: 8) {
            Text(WeatherFormatters.hour(item.date))
                .font(.subheadline)
                .foregroundStyle(WeatherTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: timeWidth, alignment: .leading)

            ConditionIcon(condition: item.condition, isDaytime: isDaytime, size: 20)
                .frame(width: 28)

            Text(
                WeatherFormatters.temperature(
                    item.temperature,
                    unitSystem: unitSystem
                )
            )
            .font(.headline.monospacedDigit())
            .foregroundStyle(WeatherTheme.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 42, alignment: .leading)

            // The condition fills the middle of the row when there's room for it,
            // and drops out on narrow phones or large text instead of truncating.
            if dynamicTypeSize < .xLarge {
                ViewThatFits(in: .horizontal) {
                    Text(item.condition.displayName(isDaytime: isDaytime))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(WeatherTheme.secondaryText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer(minLength: 0)
                }
            } else {
                Spacer(minLength: 0)
            }

            Label(
                WeatherFormatters.percent(item.precipitationChance),
                systemImage: "drop.fill"
            )
            .font(.caption)
            .foregroundStyle(WeatherTheme.accent)
            .lineLimit(1)
            .frame(width: 48, alignment: .trailing)

            Text(
                WeatherFormatters.wind(
                    speed: item.windSpeed,
                    direction: nil,
                    unitSystem: unitSystem
                )
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(WeatherTheme.secondaryText)
            .lineLimit(1)
            .frame(width: unitSystem == .us ? 50 : 64, alignment: .trailing)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WeatherTheme.tertiaryText)
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private enum HourlyMetric: String, CaseIterable, Identifiable {
    case temperature
    case precipitation
    case wind

    var id: Self { self }

    var title: String {
        switch self {
        case .temperature: "Temp"
        case .precipitation: "Rain"
        case .wind: "Wind"
        }
    }
}

private enum HourlyHorizon: String, CaseIterable, Identifiable {
    case twentyFour
    case fortyEight

    var id: Self { self }
    var hourCount: Int { self == .twentyFour ? 24 : 48 }
    var title: String { self == .twentyFour ? "24h" : "48h" }
}

private extension View {
    func weatherChartFrame() -> some View {
        frame(height: 220)
    }

    func weatherChartXAxis() -> some View {
        chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine()
                    .foregroundStyle(WeatherTheme.divider)
                AxisValueLabel(format: .dateTime.hour())
                    .foregroundStyle(WeatherTheme.tertiaryText)
            }
        }
    }
}
