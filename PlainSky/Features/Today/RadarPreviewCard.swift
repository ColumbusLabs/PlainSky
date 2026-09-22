import SwiftUI

struct RadarPreviewCard: View {
    let location: WeatherLocation
    let availability: WeatherProductAvailability
    var onOpen: (() -> Void)?

    @State private var latestFrame: RadarFrame?

    private let radarProvider = NOAARadarProvider()

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: WeatherTheme.cardRadius, style: .continuous)
    }

    var body: some View {
        Button {
            onOpen?()
        } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Radar")
                        .font(.headline)
                        .foregroundStyle(WeatherTheme.primaryText)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(availability.message == nil ? "See what's happening near you" : "Radar preview unavailable")
                            .font(.caption)
                            .foregroundStyle(WeatherTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        if onOpen != nil {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(WeatherTheme.tertiaryText)
                        }
                    }
                }
                .padding(WeatherTheme.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)

                RadarMapView(
                    location: location,
                    frame: latestFrame,
                    recenterToken: 0,
                    isInteractive: false
                )
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            }
            .frame(height: 104)
            .clipShape(cardShape)
            .weatherSurface()
            .overlay(cardShape.strokeBorder(WeatherTheme.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(onOpen == nil)
        .accessibilityLabel("Open radar for \(location.displayName)")
        .task(id: location.id) {
            await loadLatestFrame()
        }
    }

    @MainActor
    private func loadLatestFrame() async {
        guard availability.message == nil else {
            latestFrame = nil
            return
        }

        let frames = (try? await radarProvider.frames(for: location)) ?? []
        latestFrame = frames.max { $0.timestamp < $1.timestamp }
    }
}
