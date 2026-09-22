import SwiftUI

struct LocationMenu<Content: View>: View {
    @Environment(WeatherStore.self) private var store

    @ViewBuilder let label: () -> Content

    var body: some View {
        Menu {
            ForEach(store.savedLocations) { location in
                Button {
                    store.selectAndRefresh(location)
                } label: {
                    Label(
                        location.displayName,
                        systemImage: location.isCurrentLocation ? "location.fill" : "mappin"
                    )
                }
            }
        } label: {
            label()
        }
        .accessibilityLabel("Location: \(store.snapshot.location.displayName)")
        .accessibilityHint("Choose a saved place")
    }
}
