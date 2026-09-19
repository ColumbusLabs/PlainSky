import SwiftUI

struct RootTabView: View {
    @State private var selection: AppTab = .today

    var body: some View {
        TabView(selection: $selection) {
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
        .tint(WeatherTheme.accent)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

enum AppTab: Hashable {
    case today
    case forecast
    case radar
    case places
}

#Preview {
    RootTabView()
        .environment(WeatherStore())
}
