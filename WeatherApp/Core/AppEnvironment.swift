import Foundation

enum AppDataMode: String, Sendable {
    case preview
    case liveNWS

    var title: String {
        switch self {
        case .preview:
            "Preview"
        case .liveNWS:
            "Live NWS"
        }
    }
}

enum AppEnvironment {
    static var dataMode: AppDataMode {
        ProcessInfo.processInfo.arguments.contains("--live-nws")
            ? .liveNWS
            : .preview
    }

    @MainActor
    static func makeWeatherStore() -> WeatherStore {
        switch dataMode {
        case .preview:
            WeatherStore(repository: PreviewWeatherRepository())

        case .liveNWS:
            var initialSnapshot = MockWeather.snapshot
            initialSnapshot.fetchedAt = .distantPast

            return WeatherStore(
                repository: makeLiveRepository(),
                snapshot: initialSnapshot
            )
        }
    }

    @MainActor
    static func makeLiveRepository() -> LiveWeatherRepository {
        LiveWeatherRepository(
            primary: NWSWeatherProvider(),
            supplemental: WeatherKitSupplementalProvider()
        )
    }
}
