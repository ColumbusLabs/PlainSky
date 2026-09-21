import Charts
import SwiftUI

struct NextHourPrecipitationCard: View {
    let samples: [MinutePrecipitationSample]

    var body: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Next hour")

                HStack(alignment: .firstTextBaseline) {
                    Text("Precipitation probability")
                        .font(.headline)
                        .foregroundStyle(WeatherTheme.primaryText)

                    Spacer()

                    if let next = samples.first {
                        Text(WeatherFormatters.percent(next.probability))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(WeatherTheme.accent)
                    }
                }

                Chart(samples) { sample in
                    BarMark(
                        x: .value("Time", sample.date),
                        y: .value("Chance", sample.probability * 100)
                    )
                    .foregroundStyle(WeatherTheme.accent.gradient)
                    .cornerRadius(3)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        AxisGridLine()
                            .foregroundStyle(WeatherTheme.divider)
                        AxisValueLabel {
                            if let number = value.as(Int.self) {
                                Text("\(number)%")
                                    .font(.caption2)
                                    .foregroundStyle(WeatherTheme.tertiaryText)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .minute, count: 20)) { _ in
                        AxisValueLabel(format: .dateTime.hour().minute())
                            .font(.caption2)
                            .foregroundStyle(WeatherTheme.tertiaryText)
                    }
                }
                .frame(height: 120)

                if let source = samples.first?.source {
                    SourceFreshnessView(metadata: source)
                    WeatherProviderAttributionView(metadata: source)
                }
            }
        }
    }
}
