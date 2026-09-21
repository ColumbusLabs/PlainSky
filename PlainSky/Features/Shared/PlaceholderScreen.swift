import SwiftUI

struct PlaceholderScreen: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            WeatherBackdrop()

            VStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 44, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(WeatherTheme.accent)

                VStack(spacing: 7) {
                    Text(title)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(WeatherTheme.primaryText)

                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(WeatherTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}
