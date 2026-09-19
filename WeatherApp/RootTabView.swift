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
                PlaceholderScreen(
                    icon: "chart.xyaxis.line",
                    title: "Forecast",
                    subtitle: "Hours and days, without the noise."
                )
            }
            .tag(AppTab.forecast)
            .tabItem {
                Label("Forecast", systemImage: "calendar")
            }

            NavigationStack {
                PlaceholderScreen(
                    icon: "map.fill",
                    title: "Radar",
                    subtitle: "See what is actually moving toward you."
                )
            }
            .tag(AppTab.radar)
            .tabItem {
                Label("Radar", systemImage: "map")
            }

            NavigationStack {
                PlaceholderScreen(
                    icon: "location.fill",
                    title: "Places",
                    subtitle: "Current location, saved places, and settings."
                )
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
