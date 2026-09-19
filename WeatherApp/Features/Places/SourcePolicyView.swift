import SwiftUI

struct SourcePolicyView: View {
    private let assignments: [SourceAssignment] = [
        .init(product: "Current conditions", provider: "NWS observation", icon: "thermometer.medium"),
        .init(product: "Hourly forecast", provider: "NWS forecast/grid", icon: "clock"),
        .init(product: "Daily forecast", provider: "NWS forecast", icon: "calendar"),
        .init(product: "Official alerts", provider: "NWS", icon: "exclamationmark.triangle.fill"),
        .init(product: "Radar", provider: "NOAA / NCEP", icon: "map.fill"),
        .init(product: "Next-hour precipitation", provider: "Apple WeatherKit", icon: "drop.fill"),
        .init(product: "UV", provider: "Apple WeatherKit", icon: "sun.max.fill"),
        .init(product: "Sunrise / sunset", provider: "Apple WeatherKit", icon: "sunrise.fill")
    ]

    var body: some View {
        ZStack {
            WeatherBackdrop(style: .night)

            ScrollView {
                VStack(spacing: 16) {
                    WeatherCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No homemade meteorology")
                                .font(.headline)
                                .foregroundStyle(WeatherTheme.primaryText)

                            Text("The app selects a provider for each product and displays that provider's supplied value. It does not average forecasts or manufacture missing weather.")
                                .font(.subheadline)
                                .foregroundStyle(WeatherTheme.secondaryText)
                        }
                    }

                    WeatherCard {
                        VStack(spacing: 0) {
                            ForEach(Array(assignments.enumerated()), id: \.element.id) { index, assignment in
                                HStack(spacing: 12) {
                                    Image(systemName: assignment.icon)
                                        .foregroundStyle(WeatherTheme.accent)
                                        .frame(width: 28)

                                    Text(assignment.product)
                                        .foregroundStyle(WeatherTheme.primaryText)

                                    Spacer()

                                    Text(assignment.provider)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(WeatherTheme.secondaryText)
                                        .multilineTextAlignment(.trailing)
                                }
                                .font(.subheadline)
                                .padding(.vertical, 13)

                                if index < assignments.count - 1 {
                                    Divider().overlay(WeatherTheme.divider)
                                }
                            }
                        }
                    }
                }
                .padding(WeatherTheme.horizontalPadding)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Weather Sources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
}

private struct SourceAssignment: Identifiable {
    let id = UUID()
    let product: String
    let provider: String
    let icon: String
}
