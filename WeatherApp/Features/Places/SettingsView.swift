import SwiftUI

struct SettingsView: View {
    @Environment(WeatherStore.self) private var store

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { store.appearance },
            set: { store.appearance = $0 }
        )
    }

    var body: some View {
        ZStack {
            WeatherBackdrop(style: .night)

            ScrollView {
                LazyVStack(spacing: 16) {
                    WeatherCard {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: "Appearance")

                            Picker("Appearance", selection: appearanceBinding) {
                                ForEach(AppAppearance.allCases) { appearance in
                                    Text(appearance.title).tag(appearance)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    NavigationLink {
                        SourcePolicyView()
                    } label: {
                        SettingsNavigationCard(
                            icon: "point.3.connected.trianglepath.dotted",
                            title: "Weather sources",
                            subtitle: "See exactly which provider owns each product."
                        )
                    }
                    .buttonStyle(.plain)

                    WeatherCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Privacy")

                            Label {
                                Text("No ads or third-party analytics are part of the app architecture.")
                            } icon: {
                                Image(systemName: "hand.raised.fill")
                                    .foregroundStyle(WeatherTheme.accent)
                            }
                            .font(.subheadline)
                            .foregroundStyle(WeatherTheme.primaryText)

                            Text("When live data is enabled, selected coordinates will necessarily be sent to the weather and map providers needed to answer the request.")
                                .font(.caption)
                                .foregroundStyle(WeatherTheme.secondaryText)
                        }
                    }

                    WeatherCard {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Build")
                            SettingsValueRow(label: "Version", value: "0.1.0")
                            SettingsValueRow(label: "Data mode", value: "Preview")
                            SettingsValueRow(label: "Minimum iOS", value: "17.0")
                        }
                    }
                }
                .padding(.horizontal, WeatherTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
}

private struct SettingsNavigationCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        WeatherCard {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(WeatherTheme.accent)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(WeatherTheme.primaryText)

                    Text(subtitle)
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
}

private struct SettingsValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(WeatherTheme.secondaryText)
            Spacer()
            Text(value)
                .foregroundStyle(WeatherTheme.primaryText)
        }
        .font(.subheadline)
        .padding(.vertical, 3)
    }
}
