import Foundation

/// Identifiers and storage shared by the app, its background refresh task,
/// and the home screen widget.
enum PlainSkyShared {
    static let appGroupID = "group.com.columbuslabs.weatherapp"
    static let backgroundRefreshTaskID = "com.columbuslabs.weatherapp.refresh"
    static let conditionsWidgetKind = "PlainSkyConditionsWidget"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}

/// Which notification types the person wants. Everything except general
/// statements is on by default.
struct WeatherNotificationPreferences: Codable, Hashable, Sendable {
    var warnings = true
    var watches = true
    var advisories = true
    var statements = false
    var precipitationStart = true

    var anyEnabled: Bool {
        warnings || watches || advisories || statements || precipitationStart
    }

    func allows(_ category: WeatherAlertCategory) -> Bool {
        switch category {
        case .warning: warnings
        case .watch: watches
        case .advisory: advisories
        case .statement: statements
        }
    }
}

enum WeatherAlertCategory: String, Codable, Sendable {
    case warning
    case watch
    case advisory
    case statement

    /// NWS event names carry their tier as the final word, e.g.
    /// "Tornado Warning", "Flood Watch", "Heat Advisory".
    init(event: String) {
        let lowered = event.lowercased()
        if lowered.hasSuffix("warning")
            || lowered.contains("emergency")
            || lowered.hasPrefix("evacuation") {
            self = .warning
        } else if lowered.hasSuffix("watch") {
            self = .watch
        } else if lowered.hasSuffix("advisory") {
            self = .advisory
        } else {
            self = .statement
        }
    }
}

/// Compact, already-validated values for the home screen widget.
struct WidgetWeatherSnapshot: Codable, Hashable, Sendable {
    struct Hour: Codable, Hashable, Sendable {
        var date: Date
        var temperature: Double
    }

    var location: WeatherLocation
    var temperature: Double?
    var conditionDescription: String?
    var condition: WeatherCondition?
    var high: Double?
    var low: Double?
    var hours: [Hour]
    var solar: SolarWeather?
    var asOf: Date

    /// Builds from fresh screen state only; unavailable products stay empty
    /// rather than being filled with placeholder values.
    init?(state: WeatherScreenState, asOf: Date) {
        let current = state.current.value
        let hourly = state.hourly.value ?? []
        guard current != nil || !hourly.isEmpty else { return nil }

        let today = state.daily.value?.first
        location = state.location
        temperature = current?.temperature
        // The widget has room for real conditions only, not the generic
        // placeholder used when a station sends no text.
        conditionDescription = current?.conditionDescription == NWSMapper.genericObservationDescription
            ? nil
            : current?.conditionDescription
        condition = current?.condition
        high = today?.daytimeHigh
        low = today?.overnightLow
        hours = hourly.map { Hour(date: $0.date, temperature: $0.temperature) }
        solar = state.solarEvents.value
        self.asOf = asOf
    }

    init(
        location: WeatherLocation,
        temperature: Double?,
        conditionDescription: String?,
        condition: WeatherCondition?,
        high: Double?,
        low: Double?,
        hours: [Hour],
        solar: SolarWeather? = nil,
        asOf: Date
    ) {
        self.location = location
        self.temperature = temperature
        self.conditionDescription = conditionDescription
        self.condition = condition
        self.high = high
        self.low = low
        self.hours = hours
        self.solar = solar
        self.asOf = asOf
    }

    /// The next `count` whole hours after `date`.
    func upcomingHours(after date: Date, count: Int = 3) -> [Hour] {
        Array(hours.filter { $0.date > date }.prefix(count))
    }
}

/// Bookkeeping so each alert and each precipitation start notifies once.
struct WeatherNotifierState: Codable, Hashable, Sendable {
    /// Alert ID → when it can be forgotten.
    var notifiedAlerts: [String: Date] = [:]
    var lastPrecipitationNotificationAt: Date?
}

struct SharedWeatherSettings: @unchecked Sendable {
    private enum Key {
        static let homePlaceID = "shared.homePlaceID"
        static let homePlace = "shared.homePlace"
        static let unitSystem = "shared.unitSystem"
        static let widgetSnapshot = "shared.widgetSnapshot"
        static let notificationPreferences = "shared.notificationPreferences"
        static let notifierState = "shared.notifierState"
        static let pushToken = "shared.pushToken"
        static let serverAlertsRegistered = "shared.serverAlertsRegistered"
        static let registrationFingerprint = "shared.registrationFingerprint"
        static let registeredAt = "shared.registeredAt"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = PlainSkyShared.defaults) {
        self.defaults = defaults
    }

    /// The saved place chosen for notifications and the widget; nil means
    /// "follow Current Location".
    var homePlaceID: UUID? {
        get { defaults.string(forKey: Key.homePlaceID).flatMap(UUID.init(uuidString:)) }
        nonmutating set { defaults.set(newValue?.uuidString, forKey: Key.homePlaceID) }
    }

    /// Resolved copy of the home place so the widget and background task
    /// have coordinates without the app's saved-place list.
    var homePlace: WeatherLocation? {
        get { decode(WeatherLocation.self, key: Key.homePlace) }
        nonmutating set { encode(newValue, key: Key.homePlace) }
    }

    var unitSystem: WeatherUnitSystem {
        get { defaults.string(forKey: Key.unitSystem).flatMap(WeatherUnitSystem.init(rawValue:)) ?? .us }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.unitSystem) }
    }

    var widgetSnapshot: WidgetWeatherSnapshot? {
        get { decode(WidgetWeatherSnapshot.self, key: Key.widgetSnapshot) }
        nonmutating set { encode(newValue, key: Key.widgetSnapshot) }
    }

    var notificationPreferences: WeatherNotificationPreferences {
        get { decode(WeatherNotificationPreferences.self, key: Key.notificationPreferences) ?? .init() }
        nonmutating set { encode(newValue, key: Key.notificationPreferences) }
    }

    var notifierState: WeatherNotifierState {
        get { decode(WeatherNotifierState.self, key: Key.notifierState) ?? .init() }
        nonmutating set { encode(newValue, key: Key.notifierState) }
    }

    /// Hex APNs device token for this install.
    var pushToken: String? {
        get { defaults.string(forKey: Key.pushToken) }
        nonmutating set { defaults.set(newValue, forKey: Key.pushToken) }
    }

    /// True once the alerts server accepted this device, so on-device alert
    /// checks stand down and alerts are not delivered twice.
    var serverAlertsRegistered: Bool {
        get { defaults.bool(forKey: Key.serverAlertsRegistered) }
        nonmutating set { defaults.set(newValue, forKey: Key.serverAlertsRegistered) }
    }

    var registrationFingerprint: String? {
        get { defaults.string(forKey: Key.registrationFingerprint) }
        nonmutating set { defaults.set(newValue, forKey: Key.registrationFingerprint) }
    }

    var registeredAt: Date? {
        get { defaults.object(forKey: Key.registeredAt) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.registeredAt) }
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T?, key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
