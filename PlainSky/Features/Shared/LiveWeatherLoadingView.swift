import SwiftUI

struct LiveWeatherLoadingView: View {
    @Environment(WeatherStore.self) private var store

    let title: String

    var body: some View {
        ZStack {
            WeatherBackdrop(style: .clear)

            VStack(spacing: 18) {
                Spacer()

                WeatherCard {
                    VStack(spacing: 14) {
                        if store.isRefreshing || store.lastRefreshError == nil {
                            ProgressView()
                                .controlSize(.large)
                                .tint(WeatherTheme.accent)
                        } else {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 32))
                                .foregroundStyle(.orange)
                        }

                        VStack(spacing: 5) {
                            Text(
                                store.lastRefreshError == nil
                                    ? title
                                    : "Live weather unavailable"
                            )
                            .font(.headline)
                            .foregroundStyle(WeatherTheme.primaryText)

                            Text(store.screenState.location.displayName)
                                .font(.subheadline)
                                .foregroundStyle(WeatherTheme.secondaryText)

                            if let error = store.lastRefreshError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(WeatherTheme.tertiaryText)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 2)
                            }
                        }

                        if store.lastRefreshError != nil {
                            Button("Retry") {
                                Task { await store.refresh() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(WeatherTheme.accent)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, WeatherTheme.horizontalPadding)

                Spacer()
            }
        }
    }
}
