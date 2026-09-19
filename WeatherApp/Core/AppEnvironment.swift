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
    static var dataMode: AppDataMode {
        let arguments = ProcessInfo.processInfo.arguments

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
            var initialSnapshot = MockWeather.snapshot
            initialSnapshot.fetchedAt = .distantPast

            return WeatherStore(
                repository: makeLiveRepository(
                    includeWeatherKit: dataMode == .liveNWSWeatherKit
                ),
                snapshot: initialSnapshot,
                isShowingPlaceholderData: true,
                masksStaleLocationData: true
            )
        }
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
