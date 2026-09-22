import SwiftUI

struct NextHourPrecipitationCard: View {
    let samples: [MinutePrecipitationSample]

    private var peakProbability: Double {
        samples.map(\.probability).max() ?? 0
    }

    private var summary: String {
        switch peakProbability {
        case ..<0.2: "Low chance of precipitation"
        case ..<0.5: "Precipitation possible"
        default: "Precipitation likely"
        }
    }

    private var spanMinutes: Int {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return Int((last.date.timeIntervalSince(first.date) / 60).rounded())
    }

    private var timeLabels: [String] {
        if spanMinutes >= 55 {
            return ["Now", "10m", "20m", "30m", "40m", "50m", "1h"]
        }
        return ["Now", "\(spanMinutes)m"]
    }

    var body: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    SectionHeader(title: "Next Hour", subtitle: summary)

                    Text(WeatherFormatters.percent(peakProbability))
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(WeatherTheme.accent)
                }

                PrecipitationBars(samples: samples)
                    .frame(height: 36)

                HStack(spacing: 0) {
                    ForEach(Array(timeLabels.enumerated()), id: \.offset) { index, label in
                        Text(label)
                        if index < timeLabels.count - 1 {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .font(.caption2)
                .foregroundStyle(WeatherTheme.tertiaryText)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Next hour: \(summary), up to \(WeatherFormatters.percent(peakProbability))"
        )
    }
}

private struct PrecipitationBars: View {
    let samples: [MinutePrecipitationSample]

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: samples.count > 30 ? 1.5 : 3) {
                ForEach(samples) { sample in
                    let probability = min(max(sample.probability, 0), 1)

                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(WeatherTheme.accent.opacity(0.12))

                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(WeatherTheme.accent.opacity(0.45 + 0.55 * probability))
                            .frame(height: max(3, proxy.size.height * probability))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
