import SwiftUI

struct RootTabView: View {
    @State private var router = AppRouter()

    private var selection: Binding<AppTab> {
        Binding(
            get: { router.selectedTab },
            set: { router.selectedTab = $0 }
        )
    }

    var body: some View {
        TabView(selection: selection) {
            NavigationStack {
                TodayView()
            }
            .tag(AppTab.today)
            .tabItem {
                Label("Today", systemImage: "sun.max")
            }

            NavigationStack {
                ForecastView()
            }
            .tag(AppTab.forecast)
            .tabItem {
                Label("Forecast", systemImage: "calendar")
            }

            NavigationStack {
                RadarView()
            }
            .tag(AppTab.radar)
            .tabItem {
                Label("Radar", systemImage: "map")
            }

            NavigationStack {
                PlacesView()
            }
            .tag(AppTab.places)
            .tabItem {
                Label("Places", systemImage: "location")
            }
        }
        .environment(router)
        .tint(WeatherTheme.accent)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

#Preview {
    RootTabView()
        .environment(WeatherStore())
}
