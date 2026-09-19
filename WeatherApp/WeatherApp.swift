import SwiftUI

@main
struct WeatherApp: App {
    @State private var store = WeatherStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
                .preferredColorScheme(store.preferredColorScheme)
        }
    }
}
