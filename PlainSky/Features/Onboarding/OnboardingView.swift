import SwiftUI

struct OnboardingView: View {
    @Environment(WeatherStore.self) private var store
    @Binding var hasCompletedOnboarding: Bool
    @State private var locationService = LocationService()
    @State private var showingSearch = false

    var body: some View {
        ZStack {
            WeatherBackdrop(style: .clear)

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(WeatherTheme.accent.opacity(0.14))
                        .frame(width: 190, height: 190)
                        .blur(radius: 3)

                    Image(systemName: "cloud.sun.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 86, weight: .medium))
                }
                .padding(.bottom, 34)

                VStack(spacing: 12) {
                    Text("Weather without the noise.")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(WeatherTheme.primaryText)
                        .multilineTextAlignment(.center)

                    Text("Fast forecasts, official alerts, and radar. No ads, accounts, or feed to fight through.")
                        .font(.body)
                        .foregroundStyle(WeatherTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        locationService.requestCurrentLocation()
                    } label: {
                        HStack(spacing: 10) {
                            if locationService.isResolving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "location.fill")
                            }

                            Text(locationService.isResolving ? "Finding your location…" : "Use Current Location")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(WeatherTheme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .disabled(locationService.isResolving)

                    Button {
                        showingSearch = true
                    } label: {
                        Label("Search for a Place", systemImage: "magnifyingglass")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .foregroundStyle(WeatherTheme.primaryText)
                    }

                    if let errorMessage = locationService.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(WeatherTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }

                    Text("Your selected coordinates are only used to request weather and map data.")
                        .font(.caption2)
                        .foregroundStyle(WeatherTheme.tertiaryText)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .onChange(of: locationService.currentLocation) { _, newLocation in
            guard let newLocation else { return }
            store.setCurrentLocationAndRefresh(newLocation)
            hasCompletedOnboarding = true
        }
        .sheet(isPresented: $showingSearch) {
            NavigationStack {
                LocationSearchView { _ in
                    hasCompletedOnboarding = true
                }
            }
            .environment(store)
        }
    }
}
