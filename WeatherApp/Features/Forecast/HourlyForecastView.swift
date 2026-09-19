import Charts
import SwiftUI

struct HourlyForecastView: View {
    let items: [HourlyForecastItem]

    @State private var metric: HourlyMetric = .temperature
    @State private var horizon: HourlyHorizon = .twentyFour

    private var visibleItems: [HourlyForecastItem] {
        Array(items.prefix(horizon.hourCount))
    }

    var body: some View {
        VStack(spacing: 16) {
            WeatherCard {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "Hourly trends")

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
                    SectionHeader(title: "Hour by hour")

                    HourlyDetailRows(items: visibleItems)
                }
            }
        }
    }

    @ViewBuilder
    private var forecastChart: some View {
        switch metric {
        case .temperature:
            Chart(visibleItems) { item in
                LineMark(
                    x: .value("Time", item.date),
                    y: .value("Temperature", item.temperature)
                )
                .foregroundStyle(WeatherTheme.accent)
                .lineStyle(.init(lineWidth: 2.5))

                PointMark(
                    x: .value("Time", item.date),
                    y: .value("Temperature", item.temperature)
                )
                .foregroundStyle(WeatherTheme.accent)
            }
            .chartYAxisLabel("°F")
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
                LineMark(
                    x: .value("Time", item.date),
                    y: .value("Wind", item.windSpeed ?? 0)
                )
                .foregroundStyle(WeatherTheme.accent)
                .lineStyle(.init(lineWidth: 2.5))
            }
            .chartYAxisLabel("mph")
            .weatherChartXAxis()
            .weatherChartFrame()
        }
    }
}

struct HourlyDetailRows: View {
    let items: [HourlyForecastItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 12) {
                    Text(index == 0 ? "Now" : WeatherFormatters.hour(item.date))
                        .font(.subheadline.weight(index == 0 ? .semibold : .regular))
                        .foregroundStyle(WeatherTheme.primaryText)
                        .frame(width: 62, alignment: .leading)

                    Image(systemName: item.condition.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 28)

                    Text(WeatherFormatters.temperature(item.temperature))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(WeatherTheme.primaryText)

                    Spacer()

                    Label(
                        WeatherFormatters.percent(item.precipitationChance),
                        systemImage: "drop.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(WeatherTheme.accent)
                    .frame(width: 58, alignment: .trailing)

                    Text(WeatherFormatters.wind(speed: item.windSpeed, direction: nil))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(WeatherTheme.secondaryText)
                        .frame(width: 54, alignment: .trailing)
                }
                .padding(.vertical, 11)

                if index < items.count - 1 {
                    Divider()
                        .overlay(WeatherTheme.divider)
                }
            }
        }
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
