import Foundation
import SwiftUI
import UserNotifications

@main
struct PlainSkyApp: App {
    @State private var store = AppEnvironment.makeWeatherStore()
    @AppStorage("hasCompletedWeatherOnboarding") private var hasCompletedOnboarding = false

    init() {
        UNUserNotificationCenter.current().delegate = WeatherNotificationDelegate.shared
    }

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
            .preferredColorScheme(.light)
        }
        .backgroundTask(.appRefresh(PlainSkyShared.backgroundRefreshTaskID)) {
            await WeatherBackgroundRefresh.perform()
        }
    }
}
