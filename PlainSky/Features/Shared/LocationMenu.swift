import SwiftUI

struct LocationMenu<Content: View>: View {
    @Environment(WeatherStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var showingSearch = false

    @ViewBuilder let label: () -> Content

    var body: some View {
        Menu {
            Section {
                ForEach(store.savedLocations) { location in
                    Button {
                        store.selectAndRefresh(location)
                    } label: {
                        if WeatherRequestLocationKey(location)
                            == WeatherRequestLocationKey(store.screenState.location) {
                            Label(location.displayName, systemImage: "checkmark")
                        } else {
                            Label(
                                location.displayName,
                                systemImage: location.isCurrentLocation ? "location.fill" : "mappin"
                            )
                        }
                    }
                }
            }

            Section {
                Button {
                    showingSearch = true
                } label: {
                    Label("Add a Place…", systemImage: "plus")
                }

                Button {
                    router.selectedTab = .places
                } label: {
                    Label("Manage Places", systemImage: "list.bullet")
                }
            }
        } label: {
            label()
        }
        .accessibilityLabel("Location: \(store.screenState.location.displayName)")
        .accessibilityHint("Choose or add a place")
        .sheet(isPresented: $showingSearch) {
            NavigationStack {
                LocationSearchView()
            }
            .environment(store)
        }
    }
}
