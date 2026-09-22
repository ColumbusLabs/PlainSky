import SwiftUI

struct SettingsView: View {
    @Environment(WeatherStore.self) private var store

    private var unitSystemBinding: Binding<WeatherUnitSystem> {
        Binding(
            get: { store.unitSystem },
            set: { store.unitSystem = $0 }
        )
    }

    var body: some View {
        ZStack {
            WeatherBackdrop(style: .calm)

            ScrollView {
                LazyVStack(spacing: WeatherTheme.sectionSpacing) {
                    WeatherCard {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: "Display units")

                            Picker("Units", selection: unitSystemBinding) {
                                ForEach(WeatherUnitSystem.allCases) { unitSystem in
                                    Text(unitSystem.title).tag(unitSystem)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text("Unit changes are presentation-only conversions. They do not alter the underlying forecast or derive new weather values.")
                                .font(.caption)
                                .foregroundStyle(WeatherTheme.tertiaryText)
                        }
                    }

                    DataSourcesCard(snapshot: store.snapshot)

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

                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        SettingsNavigationCard(
                            icon: "stethoscope",
                            title: "Diagnostics",
                            subtitle: "Inspect provider freshness, validity, and selected coordinates."
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
                            SettingsValueRow(label: "Version", value: AppEnvironment.appVersion)
                            SettingsValueRow(
                                label: "Data mode",
                                value: AppEnvironment.dataMode.title
                            )
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
