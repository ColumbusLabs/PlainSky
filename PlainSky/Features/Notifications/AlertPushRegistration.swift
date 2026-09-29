import Foundation
import UIKit
import UserNotifications

/// Registers this phone with the PlainSky alerts server (a Cloudflare Worker
/// that checks NWS every minute and sends pushes through APNs).
///
/// Sends the selected alert place rounded to two decimal places (~1 km), the
/// NWS alert toggles, and the APNs device token to the alerts server. The
/// server rounds the coordinates again before storing them. Turning off every
/// NWS alert category removes the server registration; precipitation notices
/// remain local to this device.
@MainActor
final class AlertPushRegistration {
    static let shared = AlertPushRegistration()

    static let endpoint = URL(string: "https://plainsky-alerts.zspringhorn.workers.dev")!
    /// Re-register at least this often so a lost server record heals itself.
    private static let refreshInterval: TimeInterval = 12 * 60 * 60

    private let settings: SharedWeatherSettings
    private let session: URLSession
    private let authorizationStatusProvider: @MainActor () async -> UNAuthorizationStatus
    private let isPreview: @MainActor () -> Bool
    private var isSyncing = false
    private var hasPendingSync = false
    private var pendingSyncForce = false

    init(
        settings: SharedWeatherSettings = SharedWeatherSettings(),
        session: URLSession = .shared,
        authorizationStatusProvider: @escaping @MainActor () async -> UNAuthorizationStatus = {
            await WeatherNotifier.shared.authorizationStatus()
        },
        isPreview: @escaping @MainActor () -> Bool = {
            AppEnvironment.dataMode == .preview
        }
    ) {
        self.settings = settings
        self.session = session
        self.authorizationStatusProvider = authorizationStatusProvider
        self.isPreview = isPreview
    }

    private static var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    private struct Registration: Codable, Equatable {
        struct Preferences: Codable, Equatable {
            var warnings: Bool
            var watches: Bool
            var advisories: Bool
            var statements: Bool
        }

        var token: String
        var environment: String
        var latitude: Double
        var longitude: Double
        var placeName: String
        var preferences: Preferences
    }

    /// Asks iOS for an APNs token once notifications are allowed.
    func registerForRemoteNotificationsIfAllowed() async {
        guard !isPreview() else { return }
        let status = await authorizationStatusProvider()
        if status == .authorized || status == .provisional || status == .ephemeral {
            UIApplication.shared.registerForRemoteNotifications()
        } else {
            await sync()
        }
    }

    func didReceive(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        let changed = settings.pushToken != token
        settings.pushToken = token
        Task { await sync(force: changed) }
    }

    /// Sends the current alert place and toggles when they changed or the
    /// last registration is getting old.
    func sync(force: Bool = false) async {
        guard !isPreview() else { return }
        if isSyncing {
            hasPendingSync = true
            pendingSyncForce = pendingSyncForce || force
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        var nextForce = force
        while true {
            let passForce = nextForce || pendingSyncForce
            nextForce = false
            hasPendingSync = false
            pendingSyncForce = false
            await syncOnce(force: passForce)
            guard hasPendingSync else { return }
        }
    }

    private func syncOnce(force: Bool) async {
        guard let token = settings.pushToken else { return }
        let status = await authorizationStatusProvider()
        guard status == .authorized || status == .provisional || status == .ephemeral,
              let place = settings.homePlace else {
            await unregister(token: token)
            return
        }

        let preferences = settings.notificationPreferences
        guard preferences.warnings || preferences.watches || preferences.advisories || preferences.statements else {
            await unregister(token: token)
            return
        }

        let registration = Registration(
            token: token,
            environment: Self.environment,
            latitude: Self.roundForAlertRegistration(place.latitude),
            longitude: Self.roundForAlertRegistration(place.longitude),
            placeName: place.name,
            preferences: .init(
                warnings: preferences.warnings,
                watches: preferences.watches,
                advisories: preferences.advisories,
                statements: preferences.statements
            )
        )

        guard let body = try? JSONEncoder().encode(registration) else { return }
        let fingerprint = body.base64EncodedString()
        if !force,
           settings.serverAlertsRegistered,
           settings.registrationFingerprint == fingerprint,
           let registeredAt = settings.registeredAt,
           Date().timeIntervalSince(registeredAt) < Self.refreshInterval {
            return
        }

        var request = URLRequest(url: Self.endpoint.appending(path: "v1/devices"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 20

        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            // Leave the previous state alone; on-device checks keep covering
            // alerts until the server confirms this device.
            return
        }

        settings.serverAlertsRegistered = true
        settings.registrationFingerprint = fingerprint
        settings.registeredAt = Date()
    }

    private func unregister(token: String) async {
        guard settings.serverAlertsRegistered else { return }
        var request = URLRequest(url: Self.endpoint.appending(path: "v1/devices/\(token)"))
        request.httpMethod = "DELETE"
        request.timeoutInterval = 20
        if let (_, response) = try? await session.data(for: request),
           let http = response as? HTTPURLResponse,
           (200..<300).contains(http.statusCode) {
            settings.serverAlertsRegistered = false
            settings.registrationFingerprint = nil
            settings.registeredAt = nil
        }
    }

    /// Mirrors JavaScript Math.round(value * 100) / 100 in the worker.
    private static func roundForAlertRegistration(_ value: Double) -> Double {
        floor(value * 100 + 0.5) / 100
    }
}

final class PlainSkyAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            AlertPushRegistration.shared.didReceive(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Remote notification registration failed: \(error.localizedDescription)")
    }
}
