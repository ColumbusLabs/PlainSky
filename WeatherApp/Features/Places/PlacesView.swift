import SwiftUI

struct PlacesView: View {
    @Environment(WeatherStore.self) private var store
    @State private var showingSearch = false

    var body: some View {
        ZStack {
            WeatherBackdrop(style: .night)

            ScrollView {
                LazyVStack(spacing: 16) {
                    header

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
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    savedPlaces

                    NavigationLink {
                        SettingsView()
                    } label: {
                        WeatherCard {
                            HStack(spacing: 14) {
                                Image(systemName: "gearshape.fill")
                                    .font(.title3)
                                    .foregroundStyle(WeatherTheme.accent)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Settings")
                                        .font(.headline)
                                        .foregroundStyle(WeatherTheme.primaryText)

                                    Text("Appearance, sources, privacy, and diagnostics")
                                        .font(.caption)
                                        .foregroundStyle(WeatherTheme.secondaryText)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(WeatherTheme.tertiaryText)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, WeatherTheme.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingSearch) {
            NavigationStack {
                LocationSearchView()
            }
            .environment(store)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Places")
                    .font(.largeTitle.bold())
                    .foregroundStyle(WeatherTheme.primaryText)

                Text("Weather where you care about it.")
                    .font(.subheadline)
                    .foregroundStyle(WeatherTheme.secondaryText)
            }

            Spacer()

            if store.isRefreshing {
                ProgressView()
                    .tint(WeatherTheme.primaryText)
            }
        }
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
                            isSelected: location.id == store.snapshot.location.id
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !location.isCurrentLocation {
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
