import Foundation

enum AppEnvironment {
    @MainActor
    static func makeWeatherStore() -> WeatherStore {
        WeatherStore(repository: PreviewWeatherRepository())
    }

    @MainActor
    static func makeLiveRepository() -> LiveWeatherRepository {
        LiveWeatherRepository(
            primary: NWSWeatherProvider(),
            supplemental: WeatherKitSupplementalProvider()
        )
    }
}
