import SwiftUI

struct WeatherUnavailableCard: View {
    let title: String
    let message: String
    var icon: String = "exclamationmark.circle"

    var body: some View {
        WeatherCard {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(WeatherTheme.accent)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WeatherTheme.primaryText)

                    Text(message)
                        .font(.caption)
                        .foregroundStyle(WeatherTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }
}
