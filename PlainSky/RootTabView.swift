import SwiftUI

struct RootTabView: View {
    @Environment(WeatherStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
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
                Label("Radar", systemImage: "scope")
            }

            NavigationStack {
                PlacesView()
            }
            .tag(AppTab.places)
            .tabItem {
                Label("Places", systemImage: "mappin")
            }
        }
        .environment(router)
        .tint(WeatherTheme.accent)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task {
            await store.refreshIfNeeded(trigger: .startup)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.prepareForActive()
                Task {
                    await store.refreshIfNeeded(trigger: .foreground)
                }
            } else {
                store.prepareForInactivity()
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    return
                }
                if store.expireProducts() {
                    await store.refreshIfNeeded(trigger: .automatic)
                }
            }
        }
        .overlay {
            if scenePhase != .active || store.isScreenMasked {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
        }
    }
}

#Preview {
    RootTabView()
        .environment(WeatherStore())
}
