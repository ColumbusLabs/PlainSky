import Foundation
import SwiftUI

@main
struct PlainSkyApp: App {
    @State private var store = AppEnvironment.makeWeatherStore()
    @AppStorage("hasCompletedWeatherOnboarding") private var hasCompletedOnboarding = false

    private var bypassOnboardingForValidation: Bool {
        ProcessInfo.processInfo.arguments.contains("--skip-onboarding")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding || bypassOnboardingForValidation {
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
