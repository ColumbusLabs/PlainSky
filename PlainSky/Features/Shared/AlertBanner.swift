import SwiftUI

struct AlertBanner: View {
    let alert: WeatherAlert
    var showsHeadline = false

    private var symbol: String {
        switch alert.severity {
        case .extreme, .severe, .moderate: "exclamationmark.triangle.fill"
        case .minor, .unknown: "info.circle.fill"
        }
    }

    private var tint: Color {
        switch alert.severity {
        case .extreme, .severe: Color(red: 0.88, green: 0.33, blue: 0.16)
        case .moderate, .minor, .unknown: WeatherTheme.accent
        }
    }

    private var subtitle: String {
        if showsHeadline {
            return alert.headline
        }

        if let expiresAt = alert.expiresAt {
            let until = expiresAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            return "Until \(until)"
        }

        return alert.headline
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(alert.event)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WeatherTheme.primaryText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(WeatherTheme.secondaryText)
                    .lineLimit(showsHeadline ? 2 : 1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WeatherTheme.tertiaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .weatherSurface(cornerRadius: WeatherTheme.smallRadius + 2)
        .accessibilityElement(children: .combine)
    }
}
