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
                SettingsView()
            }
            .tag(AppTab.settings)
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .environment(router)
        .tint(WeatherTheme.accent)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task {
            syncSharedState()
            WeatherBackgroundRefresh.schedule()
            if await WeatherNotifier.shared.authorizationStatus() == .notDetermined {
                await WeatherNotifier.shared.requestAuthorization()
            }
        }
        .task {
            await store.refreshIfNeeded(trigger: .startup)
        }
        .onChange(of: store.savedLocations) { _, _ in syncSharedState() }
        .onChange(of: store.unitSystem) { _, _ in syncSharedState() }
        .onChange(of: store.isRefreshing) { wasRefreshing, isRefreshing in
            guard wasRefreshing, !isRefreshing else { return }
            let state = store.screenState
            Task { await WeatherBackgroundRefresh.didRefresh(state) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.prepareForActive()
                Task {
                    await store.refreshIfNeeded(trigger: .foreground)
                }
            } else {
                store.prepareForInactivity()
                if phase == .background {
                    WeatherBackgroundRefresh.schedule()
                }
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

extension RootTabView {
    private func syncSharedState() {
        WeatherBackgroundRefresh.sync(
            savedLocations: store.savedLocations,
            selected: store.screenState.location,
            unitSystem: store.unitSystem
        )
    }
}

#Preview {
    RootTabView()
        .environment(WeatherStore())
}
