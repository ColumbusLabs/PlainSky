import Foundation
import UserNotifications

struct PlannedWeatherNotification: Equatable, Sendable {
    var id: String
    var title: String
    var subtitle: String
    var body: String
    var isTimeSensitive: Bool
}

/// Decides which notifications to send. Pure so it can be unit tested; the
/// caller persists `state` and delivers the result.
enum WeatherNotificationPlanner {
    /// How long after its start a precipitation notice suppresses another.
    static let precipitationCooldown: TimeInterval = 2 * 60 * 60
    /// Minimum chance (0–1) and intensity (mm/h) for a minute to count as wet.
    static let wetProbability = 0.5
    static let wetIntensity = 0.1
    /// Consecutive wet minutes required so a single noisy minute does not notify.
    static let sustainedMinutes = 5

    static func plan(
        alerts: [WeatherAlert]?,
        minutePrecipitation: [MinutePrecipitationSample]?,
        place: WeatherLocation,
        preferences: WeatherNotificationPreferences,
        state: inout WeatherNotifierState,
        now: Date,
        timeZone: TimeZone = .current
    ) -> [PlannedWeatherNotification] {
        state.notifiedAlerts = state.notifiedAlerts.filter { $0.value > now }

        var planned: [PlannedWeatherNotification] = []

        for alert in alerts ?? [] {
            if let expiresAt = alert.expiresAt, expiresAt <= now { continue }
            if state.notifiedAlerts[alert.id] != nil { continue }

            let forgetAt = max(alert.expiresAt ?? now, now).addingTimeInterval(12 * 60 * 60)
            let messageType = alert.messageType?.lowercased()

            // Cancellations and updates to something already sent are
            // remembered silently so the same hazard does not buzz twice.
            if messageType == "cancel" {
                state.notifiedAlerts[alert.id] = forgetAt
                continue
            }
            if messageType == "update",
               (alert.referencedIDs ?? []).contains(where: { state.notifiedAlerts[$0] != nil }) {
                state.notifiedAlerts[alert.id] = forgetAt
                continue
            }

            let category = WeatherAlertCategory(event: alert.event)
            guard preferences.allows(category) else { continue }

            planned.append(PlannedWeatherNotification(
                id: "alert-\(alert.id)",
                title: alert.event,
                subtitle: place.name,
                body: alert.headline,
                isTimeSensitive: category == .warning
                    || alert.severity == .severe
                    || alert.severity == .extreme
            ))
            state.notifiedAlerts[alert.id] = forgetAt
        }

        if preferences.precipitationStart,
           let notice = precipitationStart(
               samples: minutePrecipitation ?? [],
               place: place,
               state: state,
               now: now,
               timeZone: timeZone
           ) {
            planned.append(notice)
            state.lastPrecipitationNotificationAt = now
        }

        return planned
    }

    static func precipitationStart(
        samples: [MinutePrecipitationSample],
        place: WeatherLocation,
        state: WeatherNotifierState,
        now: Date,
        timeZone: TimeZone = .current
    ) -> PlannedWeatherNotification? {
        if let last = state.lastPrecipitationNotificationAt,
           now.timeIntervalSince(last) < precipitationCooldown {
            return nil
        }

        let upcoming = samples
            .filter { $0.date >= now.addingTimeInterval(-60) && $0.date <= now.addingTimeInterval(60 * 60) }
            .sorted { $0.date < $1.date }
        guard let first = upcoming.first, !isWet(first) else { return nil }

        guard let startIndex = upcoming.indices.first(where: { index in
            let window = upcoming[index..<min(index + sustainedMinutes, upcoming.count)]
            return window.count == sustainedMinutes && window.allSatisfy(isWet)
        }) else { return nil }

        let start = upcoming[startIndex]
        let minutesAway = Int((start.date.timeIntervalSince(now) / 60).rounded())
        guard minutesAway >= 2 else { return nil }

        let noun = precipitationNoun(start.kind)
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = timeZone
        let time = start.date.formatted(style)

        return PlannedWeatherNotification(
            id: "precipitation-\(Int(start.date.timeIntervalSince1970))",
            title: "\(noun) begins around \(time)",
            subtitle: place.name,
            body: "\(noun) is expected to start in about \(minutesAway) min.",
            isTimeSensitive: false
        )
    }

    static func isWet(_ sample: MinutePrecipitationSample) -> Bool {
        sample.probability >= wetProbability && (sample.intensity ?? wetIntensity) >= wetIntensity
    }

    private static func precipitationNoun(_ kind: String?) -> String {
        switch kind {
        case "rain": "Rain"
        case "snow": "Snow"
        case "sleet": "Sleet"
        case "hail": "Hail"
        default: "Precipitation"
        }
    }
}

@MainActor
final class WeatherNotifier {
    static let shared = WeatherNotifier()

    private let settings = SharedWeatherSettings()
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Sends anything new. `nil` inputs mean that product could not be
    /// checked, which is never treated as "nothing to report".
    func process(
        alerts: [WeatherAlert]?,
        minutePrecipitation: [MinutePrecipitationSample]?,
        place: WeatherLocation,
        now: Date = Date()
    ) async {
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let preferences = settings.notificationPreferences
        guard preferences.anyEnabled else { return }

        var state = settings.notifierState
        let planned = WeatherNotificationPlanner.plan(
            alerts: alerts,
            minutePrecipitation: minutePrecipitation,
            place: place,
            preferences: preferences,
            state: &state,
            now: now
        )
        settings.notifierState = state

        // Deliver least severe first so the most severe lands on top of the stack.
        for notification in planned.reversed() {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.subtitle = notification.subtitle
            content.body = notification.body
            content.sound = .default
            content.threadIdentifier = notification.id.hasPrefix("alert-") ? "alerts" : "precipitation"
            content.interruptionLevel = notification.isTimeSensitive ? .timeSensitive : .active

            let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}

/// Shows weather notifications as banners even while PlainSky is open.
final class WeatherNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WeatherNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
