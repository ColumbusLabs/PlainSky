import SwiftUI

struct RefreshErrorBanner: View {
    @Environment(WeatherStore.self) private var store

    var body: some View {
        if let message = store.lastRefreshError {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.title3)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Weather couldn't refresh")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WeatherTheme.primaryText)

                    Text(message)
                        .font(.caption)
                        .foregroundStyle(WeatherTheme.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button("Retry") {
                    Task {
                        await store.refresh()
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(WeatherTheme.accent)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.orange.opacity(0.22), lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
