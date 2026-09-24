import Foundation

enum AppDataMode: String, Sendable {
    case preview
    case liveNWS
    case liveNWSWeatherKit

    var title: String {
        switch self {
        case .preview:
            "Preview"
        case .liveNWS:
            "Live NWS + NOAA"
        case .liveNWSWeatherKit:
            "Live NWS + NOAA + WeatherKit"
        }
    }
}

enum AppEnvironment {
    /// Retained only for preview and legacy snapshot compatibility tests. Live
    /// startup no longer calls this policy or restores weather values.
    static let maximumRestorableSnapshotAge: TimeInterval = 6 * 60 * 60

    static var dataMode: AppDataMode {
        dataMode(for: ProcessInfo.processInfo.arguments)
    }

    static func dataMode(for arguments: [String]) -> AppDataMode {
        if arguments.contains("--preview-data") {
            return .preview
        }

        if arguments.contains("--live-nws") {
            return .liveNWS
        }

        return .liveNWSWeatherKit
    }

    @MainActor
    static func makeWeatherStore() -> WeatherStore {
        switch dataMode {
        case .preview:
            return WeatherStore(repository: PreviewWeatherRepository())

        case .liveNWS, .liveNWSWeatherKit:
            return makeLiveWeatherStore(
                includeWeatherKit: dataMode == .liveNWSWeatherKit,
                preferences: .live
            )
        }
    }

    @MainActor
    static func makeLiveWeatherStore(
        includeWeatherKit: Bool,
        preferences: WeatherPreferences
    ) -> WeatherStore {
        let selectedLocation = preferences.loadLastLocation()
            ?? MockWeather.snapshot.location
        var compatibilitySnapshot = MockWeather.snapshot
        compatibilitySnapshot.location = selectedLocation
        compatibilitySnapshot.fetchedAt = .distantPast

        return WeatherStore(
            repository: makeLiveRepository(includeWeatherKit: includeWeatherKit),
            snapshot: compatibilitySnapshot,
            preferences: preferences,
            initialScreenState: WeatherScreenState(location: selectedLocation),
            usesFreshOnlyState: true
        )
    }

    static func isRestorable(_ snapshot: WeatherSnapshot, now: Date = Date()) -> Bool {
        let cacheAge = now.timeIntervalSince(snapshot.fetchedAt)
        return cacheAge >= 0 && cacheAge <= maximumRestorableSnapshotAge
    }

    static var appVersion: String {
        guard let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String,
        !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Unknown"
        }

        return version
    }

    @MainActor
    static func makeLiveRepository(
        includeWeatherKit: Bool
    ) -> LiveWeatherRepository {
        let supplemental: any SupplementalWeatherProviding = includeWeatherKit
            ? WeatherKitSupplementalProvider()
            : DisabledWeatherKitSupplementalProvider()

        return LiveWeatherRepository(
            primary: NWSWeatherProvider(metadataCache: .live),
            supplemental: supplemental
        )
    }
}
