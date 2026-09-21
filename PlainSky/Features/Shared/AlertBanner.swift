import SwiftUI

struct AlertBanner: View {
    let alert: WeatherAlert

    private var symbol: String {
        switch alert.severity {
        case .extreme, .severe: "exclamationmark.triangle.fill"
        case .moderate: "exclamationmark.circle.fill"
        case .minor, .unknown: "info.circle.fill"
        }
    }

    var body: some View {
        WeatherCard {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.yellow)

                VStack(alignment: .leading, spacing: 4) {
                    Text(alert.event)
                        .font(.headline)
                        .foregroundStyle(WeatherTheme.primaryText)

                    Text(alert.headline)
                        .font(.subheadline)
                        .foregroundStyle(WeatherTheme.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(WeatherTheme.tertiaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
