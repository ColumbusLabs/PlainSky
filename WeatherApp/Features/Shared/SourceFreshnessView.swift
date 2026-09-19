import SwiftUI

struct SourceFreshnessView: View {
    let metadata: WeatherSourceMetadata
    var compact = false

    private var referenceDate: Date {
        metadata.observedAt ?? metadata.issuedAt ?? metadata.fetchedAt
    }

    private var prefix: String {
        if metadata.observedAt != nil { return "Observed" }
        if metadata.issuedAt != nil { return "Issued" }
        return "Fetched"
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(metadata.isExpired ? Color.orange : WeatherTheme.accent)
                .frame(width: 6, height: 6)

            if !compact {
                Text(metadata.sourceName ?? metadata.provider.rawValue)
                    .lineLimit(1)

                Text("·")
                    .foregroundStyle(WeatherTheme.tertiaryText)
            }

            Text(prefix)
            Text(referenceDate, style: .relative)
        }
        .font(.caption)
        .foregroundStyle(WeatherTheme.secondaryText)
        .accessibilityElement(children: .combine)
    }
}
