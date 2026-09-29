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
            // Same sky as Today so switching tabs feels continuous.
            WeatherBackdrop(style: .current(for: store.screenState))

            ScrollView {
                LazyVStack(spacing: WeatherTheme.sectionSpacing) {
                    header

                    PlacesSection()

                    NotificationSettingsCard()
                        .padding(.top, 8)

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

                    DataSourcesCard(state: store.screenState)

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

                            Text("PlainSky is free to use, with no ads or subscriptions. Weather requests send the selected place's coordinates to the National Weather Service and, for Apple WeatherKit features, to Apple. If any NWS alert category is enabled, the alert service stores a location rounded to about 1 km, the place name, alert choices, and this iPhone's APNs token. Turning off all NWS alert categories asks the service to delete that registration; the request needs an internet connection.")
                                .font(.caption)
                                .foregroundStyle(WeatherTheme.secondaryText)
                        }
                    }

                    WeatherCard {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "About PlainSky")

                            SettingsExternalLink(
                                icon: "hand.raised.fill",
                                title: "Privacy policy",
                                subtitle: "How location and notification data are used.",
                                url: URL(string: "https://github.com/ColumbusLabs/PlainSky/blob/main/docs/PRIVACY.md")!
                            )

                            SettingsExternalLink(
                                icon: "questionmark.circle.fill",
                                title: "Support",
                                subtitle: "Report a problem through GitHub Issues.",
                                url: URL(string: "https://github.com/ColumbusLabs/PlainSky/issues/new")!
                            )

                            SettingsExternalLink(
                                icon: "chevron.left.forwardslash.chevron.right",
                                title: "PlainSky on GitHub",
                                subtitle: "Browse the source repository.",
                                url: URL(string: "https://github.com/ColumbusLabs/PlainSky")!
                            )
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
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Settings")
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.largeTitle.bold())
                .foregroundStyle(WeatherTheme.heroText)
                .heroTextShadow()
                .accessibilityAddTraits(.isHeader)

            Spacer()

            if store.isRefreshing {
                ProgressView()
                    .tint(WeatherTheme.heroText)
            }
        }
    }
}

/// Section title that sits directly on the sky backdrop.
struct HeroSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundStyle(WeatherTheme.heroText)
            .heroTextShadow()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
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

private struct SettingsExternalLink: View {
    let icon: String
    let title: String
    let subtitle: String
    let url: URL

    var body: some View {
        Link(destination: url) {
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

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WeatherTheme.tertiaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
