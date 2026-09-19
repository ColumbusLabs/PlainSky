import SwiftUI

@main
struct WeatherApp: App {
    @State private var store = AppEnvironment.makeWeatherStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
                .preferredColorScheme(store.preferredColorScheme)
        }
    }
}
