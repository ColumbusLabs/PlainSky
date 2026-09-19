import SwiftUI

@main
struct WeatherApp: App {
    @State private var store = AppEnvironment.makeWeatherStore()
    @AppStorage("hasCompletedWeatherOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    RootTabView()
                } else {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                }
            }
            .environment(store)
            .preferredColorScheme(store.preferredColorScheme)
        }
    }
}
