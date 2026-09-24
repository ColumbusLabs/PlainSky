import SwiftUI

struct WeatherLoadingCard: View {
    let title: String

    var body: some View {
        WeatherCard {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(WeatherTheme.secondaryText)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
        }
    }
}
