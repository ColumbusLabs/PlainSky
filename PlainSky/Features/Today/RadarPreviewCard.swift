import SwiftUI

struct RadarPreviewCard: View {
    let location: WeatherLocation
    let availability: WeatherProductAvailability
    var onOpen: (() -> Void)?

    @State private var latestFrame: RadarFrame?

    private let radarProvider = NOAARadarProvider(capabilitiesCache: .shared)

    var body: some View {
        Button {
            onOpen?()
        } label: {
            WeatherCard(padding: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(
                        title: "Live Radar",
                        subtitle: availability.message == nil
                            ? "See what's happening near you"
                            : "Radar preview unavailable",
                        showsChevron: onOpen != nil
                    )
                    .padding(.horizontal, 4)
                    .padding(.top, 2)

                    RadarMapView(
                        location: location,
                        frames: latestFrame.map { [$0] } ?? [],
                        selectedFrameID: latestFrame?.id,
                        recenterToken: 0,
                        isInteractive: false,
                        regionMeters: 220_000
                    )
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: WeatherTheme.smallRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: WeatherTheme.smallRadius, style: .continuous)
                            .strokeBorder(WeatherTheme.insetStroke, lineWidth: 1)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
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
