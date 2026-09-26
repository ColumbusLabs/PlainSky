import SwiftUI

/// Search, current location, and saved places. Shown at the top of Settings.
struct PlacesSection: View {
    @Environment(WeatherStore.self) private var store
    @State private var showingSearch = false
    @State private var locationService = LocationService()
    @State private var renameTarget: WeatherLocation?
    @State private var renameText = ""
    @State private var showingRename = false

    var body: some View {
        VStack(spacing: WeatherTheme.sectionSpacing) {
            HeroSectionTitle("Places")

            Button {
                showingSearch = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(WeatherTheme.accent)

                    Text("Search city or ZIP code")
                        .foregroundStyle(WeatherTheme.secondaryText)

                    Spacer()
                }
                .padding(16)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            }
            .buttonStyle(.plain)

            currentLocationControl

            if let errorMessage = locationService.errorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "location.slash.fill")
                        .foregroundStyle(.orange)

                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(WeatherTheme.secondaryText)

                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            }

            savedPlaces
        }
        .sheet(isPresented: $showingSearch) {
            NavigationStack {
                LocationSearchView()
            }
            .environment(store)
        }
        .alert("Rename Place", isPresented: $showingRename) {
            TextField("Place name", text: $renameText)

            Button("Cancel", role: .cancel) {
                renameTarget = nil
                renameText = ""
            }

            Button("Save") {
                if let renameTarget {
                    store.renameLocation(renameTarget, to: renameText)
                }
                self.renameTarget = nil
                renameText = ""
            }
        } message: {
            Text("This changes only the local label in your saved places.")
        }
        .onChange(of: locationService.currentLocation) { _, location in
            guard let location else { return }
            store.setCurrentLocationAndRefresh(location)
        }
    }

    private var currentLocationControl: some View {
        Button {
            locationService.requestCurrentLocation()
        } label: {
            WeatherCard {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(WeatherTheme.accent.opacity(0.12))
                            .frame(width: 42, height: 42)

                        if locationService.isResolving {
                            ProgressView()
                                .tint(WeatherTheme.accent)
                        } else {
                            Image(systemName: "location.fill")
                                .foregroundStyle(WeatherTheme.accent)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            locationService.isResolving
                                ? "Updating current location…"
                                : "Update Current Location"
                        )
                        .font(.headline)
                        .foregroundStyle(WeatherTheme.primaryText)

                        if let current = store.savedLocations.first(where: { $0.isCurrentLocation }),
                           current.displayName != "Current Location" {
                            Text("Currently \(current.displayName)")
                                .font(.caption)
                                .foregroundStyle(WeatherTheme.secondaryText)
                        } else {
                            Text("Use your iPhone location for local weather")
                                .font(.caption)
                                .foregroundStyle(WeatherTheme.secondaryText)
                        }
                    }

                    Spacer()

                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WeatherTheme.tertiaryText)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(locationService.isResolving)
        .accessibilityHint("Requests your current location and refreshes weather")
    }

    private var savedPlaces: some View {
        WeatherCard {
            VStack(spacing: 0) {
                SectionHeader(title: "Saved places")
                    .padding(.bottom, 8)

                ForEach(Array(store.savedLocations.enumerated()), id: \.element.id) { index, location in
                    Button {
                        store.selectAndRefresh(location)
                    } label: {
                        PlaceRow(
                            location: location,
                            isSelected: WeatherRequestLocationKey(location)
                                == WeatherRequestLocationKey(store.screenState.location)
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !location.isCurrentLocation {
                            Button {
                                renameTarget = location
                                renameText = location.name
                                showingRename = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }

                            Button {
                                store.moveLocation(location, offset: -1)
                            } label: {
                                Label("Move Up", systemImage: "arrow.up")
                            }
                            .disabled(!store.canMoveLocation(location, offset: -1))

                            Button {
                                store.moveLocation(location, offset: 1)
                            } label: {
                                Label("Move Down", systemImage: "arrow.down")
                            }
                            .disabled(!store.canMoveLocation(location, offset: 1))

                            Divider()

                            Button(role: .destructive) {
                                store.removeLocation(location)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }

                    if index < store.savedLocations.count - 1 {
                        Divider()
                            .overlay(WeatherTheme.divider)
                    }
                }
            }
        }
    }
}

private struct PlaceRow: View {
    let location: WeatherLocation
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: location.isCurrentLocation ? "location.fill" : "mappin.circle.fill")
                .font(.title3)
                .foregroundStyle(isSelected ? WeatherTheme.accent : WeatherTheme.secondaryText)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(location.name)
                    .font(.headline)
                    .foregroundStyle(WeatherTheme.primaryText)

                if !location.region.isEmpty {
                    Text(location.region)
                        .font(.caption)
                        .foregroundStyle(WeatherTheme.secondaryText)
                }
            }

            Spacer()

            if isSelected {
                Text("Viewing")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WeatherTheme.accent)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(WeatherTheme.tertiaryText)
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}
