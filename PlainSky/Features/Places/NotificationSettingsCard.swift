import SwiftUI
import UIKit
import UserNotifications

struct NotificationSettingsCard: View {
    @Environment(WeatherStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var preferences = SharedWeatherSettings().notificationPreferences
    @State private var homePlaceID = SharedWeatherSettings().homePlaceID
    @State private var status: UNAuthorizationStatus = .notDetermined

    private var isAllowed: Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    var body: some View {
        WeatherCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "Notifications",
                    subtitle: "Official NWS alerts and next-hour precipitation"
                )

                if status == .denied {
                    permissionBanner(
                        message: "Notifications are turned off for PlainSky.",
                        action: "Open Settings"
                    ) {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } else if status == .notDetermined {
                    permissionBanner(
                        message: "Allow notifications to get weather alerts.",
                        action: "Allow"
                    ) {
                        Task {
                            await WeatherNotifier.shared.requestAuthorization()
                            await refreshStatus()
                        }
                    }
                }

                VStack(spacing: 0) {
                    toggle("Warnings", detail: "Tornado, severe thunderstorm, flash flood…", icon: "exclamationmark.triangle.fill", tint: .red, isOn: $preferences.warnings)
                    divider
                    toggle("Watches", detail: "Conditions favor a hazard developing", icon: "eye.fill", tint: .orange, isOn: $preferences.watches)
                    divider
                    toggle("Advisories", detail: "Heat, wind, dense fog, winter weather…", icon: "info.circle.fill", tint: .yellow, isOn: $preferences.advisories)
                    divider
                    toggle("Statements", detail: "Special weather statements and other notices", icon: "text.bubble.fill", tint: WeatherTheme.secondaryText, isOn: $preferences.statements)
                    divider
                    toggle("Precipitation starting", detail: "\"Rain begins around 1:25 PM\"", icon: "cloud.rain.fill", tint: WeatherTheme.accent, isOn: $preferences.precipitationStart)
                }
                .disabled(!isAllowed)
                .opacity(isAllowed ? 1 : 0.55)

                HStack {
                    Text("Place")
                        .font(.subheadline)
                        .foregroundStyle(WeatherTheme.primaryText)
                    Spacer()
                    Picker("Place", selection: $homePlaceID) {
                        Text("Current Location").tag(UUID?.none)
                        ForEach(store.savedLocations.filter { !$0.isCurrentLocation }) { location in
                            Text(location.displayName).tag(Optional(location.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(WeatherTheme.accent)
                    .fixedSize()
                }

                Text("Also used by the home screen widget. iOS decides how often PlainSky can check in the background, so alerts can arrive late or not at all if the app is force-quit. Always follow official warnings from local authorities.")
                    .font(.caption)
                    .foregroundStyle(WeatherTheme.tertiaryText)
            }
        }
        .task { await refreshStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshStatus() } }
        }
        .onChange(of: preferences) { _, newValue in
            SharedWeatherSettings().notificationPreferences = newValue
        }
        .onChange(of: homePlaceID) { _, newValue in
            SharedWeatherSettings().homePlaceID = newValue
            WeatherBackgroundRefresh.sync(
                savedLocations: store.savedLocations,
                selected: store.screenState.location,
                unitSystem: store.unitSystem
            )
        }
    }

    private var divider: some View {
        Divider().overlay(WeatherTheme.divider)
    }

    private func refreshStatus() async {
        status = await WeatherNotifier.shared.authorizationStatus()
    }

    private func toggle(
        _ title: String,
        detail: String,
        icon: String,
        tint: Color,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WeatherTheme.primaryText)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(WeatherTheme.secondaryText)
                }
            }
        }
        .tint(WeatherTheme.accent)
        .padding(.vertical, 9)
    }

    private func permissionBanner(message: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(WeatherTheme.secondaryText)
            Spacer(minLength: 8)
            Button(action, action: perform)
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(WeatherTheme.accent)
        }
        .padding(12)
        .weatherInsetSurface()
    }
}
