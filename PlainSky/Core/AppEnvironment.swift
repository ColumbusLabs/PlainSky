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
    /// Cached weather is useful for launch continuity, but should not become an
    /// indefinite source of weather data when a provider is unavailable.
    static let maximumRestorableSnapshotAge: TimeInterval = 6 * 60 * 60

    static var dataMode: AppDataMode {
        dataMode(for: ProcessInfo.processInfo.arguments)
    }

    static func dataMode(for arguments: [String]) -> AppDataMode {
        if arguments.contains("--preview-data") {
            return .preview
        }

        if arguments.contains("--live-weatherkit") {
            return .liveNWSWeatherKit
        }

        return .liveNWS
    }

    @MainActor
    static func makeWeatherStore() -> WeatherStore {
        switch dataMode {
        case .preview:
            return WeatherStore(repository: PreviewWeatherRepository())

        case .liveNWS, .liveNWSWeatherKit:
            let preferences = WeatherPreferences.live
            var initialSnapshot = MockWeather.snapshot
            let restoredSnapshot = restorableSnapshot(from: preferences)

            if let restoredSnapshot {
                initialSnapshot = restoredSnapshot
            } else {
                initialSnapshot.fetchedAt = .distantPast
            }

            return WeatherStore(
                repository: makeLiveRepository(
                    includeWeatherKit: dataMode == .liveNWSWeatherKit
                ),
                snapshot: initialSnapshot,
                preferences: preferences,
                isShowingPlaceholderData: restoredSnapshot == nil,
                masksStaleLocationData: true,
                cachesSnapshots: true
            )
        }
    }

    @MainActor
    static func restorableSnapshot(
        from preferences: WeatherPreferences,
        now: Date = Date()
    ) -> WeatherSnapshot? {
        guard let cached = preferences.loadCachedSnapshot() else { return nil }

        let cacheAge = now.timeIntervalSince(cached.fetchedAt)
        guard cacheAge >= 0,
              cacheAge <= maximumRestorableSnapshotAge else {
            return nil
        }

        if let lastLocation = preferences.loadLastLocation(),
           lastLocation.id != cached.location.id {
            return nil
        }

        return cached.restoringFromCache()
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
            primary: NWSWeatherProvider(),
            supplemental: supplemental
        )
    }
}
