import BackgroundTasks
import Foundation
import WidgetKit

/// Keeps the widget and notifications current for the home place, both from
/// foreground refreshes and from iOS background app refresh.
@MainActor
enum WeatherBackgroundRefresh {
    private static let settings = SharedWeatherSettings()

    /// Asks iOS to wake the app again. iOS decides the actual time based on
    /// how often PlainSky is used, so this is best effort.
    static func schedule() {
        guard AppEnvironment.dataMode != .preview else { return }
        let request = BGAppRefreshTaskRequest(identifier: PlainSkyShared.backgroundRefreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func perform() async {
        schedule()
        await AlertPushRegistration.shared.sync()
        guard AppEnvironment.dataMode != .preview, let place = settings.homePlace else { return }

        // Alerts are fetched on their own so a failed forecast or observation
        // can never hide an active warning.
        async let alerts = fetchAlerts(for: place)
        let repository = AppEnvironment.makeLiveRepository(
            includeWeatherKit: AppEnvironment.dataMode == .liveNWSWeatherKit
        )
        let snapshot = try? await repository.load(location: place)
        let state = snapshot.map(WeatherScreenState.init(preview:))

        if let snapshot, let state {
            saveWidgetSnapshot(from: state, asOf: snapshot.fetchedAt)
        }

        await WeatherNotifier.shared.process(
            alerts: await alerts,
            minutePrecipitation: state?.minutePrecipitation.value,
            place: place
        )
    }

    /// Called after every foreground refresh. Only the home place feeds the
    /// widget and notifications.
    static func didRefresh(_ state: WeatherScreenState) async {
        guard AppEnvironment.dataMode != .preview,
              let place = settings.homePlace,
              WeatherRequestLocationKey(place) == WeatherRequestLocationKey(state.location) else { return }

        saveWidgetSnapshot(from: state, asOf: state.current.validation?.validatedAt ?? Date())
        await WeatherNotifier.shared.process(
            alerts: state.alerts.value,
            minutePrecipitation: state.minutePrecipitation.value,
            place: place
        )
    }

    /// Mirrors the app's saved places and units into the shared container.
    static func sync(savedLocations: [WeatherLocation], selected: WeatherLocation, unitSystem: WeatherUnitSystem) {
        if settings.unitSystem != unitSystem {
            settings.unitSystem = unitSystem
            WidgetCenter.shared.reloadTimelines(ofKind: PlainSkyShared.conditionsWidgetKind)
        }

        let resolved = settings.homePlaceID.flatMap { id in savedLocations.first { $0.id == id } }
            ?? savedLocations.first { $0.isCurrentLocation }
            ?? savedLocations.first
            ?? selected

        if settings.homePlace != resolved {
            settings.homePlace = resolved
            WidgetCenter.shared.reloadTimelines(ofKind: PlainSkyShared.conditionsWidgetKind)
        }
    }

    private static func saveWidgetSnapshot(from state: WeatherScreenState, asOf: Date) {
        guard let snapshot = WidgetWeatherSnapshot(state: state, asOf: asOf) else { return }
        settings.widgetSnapshot = snapshot
        WidgetCenter.shared.reloadTimelines(ofKind: PlainSkyShared.conditionsWidgetKind)
    }

    private static func fetchAlerts(for place: WeatherLocation) async -> [WeatherAlert]? {
        guard let response = try? await NWSAPIClient().activeAlerts(for: place) else { return nil }
        return NWSMapper.alerts(collection: response, fetchedAt: Date())
    }
}
