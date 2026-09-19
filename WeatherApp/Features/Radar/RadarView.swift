import MapKit
import SwiftUI

struct RadarView: View {
    @Environment(WeatherStore.self) private var store
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var playback = RadarPlaybackState()

    var body: some View {
        ZStack {
            RadarMapView(
                location: store.snapshot.location,
                cameraPosition: $cameraPosition
            )

            VStack(spacing: 12) {
                RadarHeader(
                    location: store.snapshot.location,
                    onRecenter: recenter
                )

                Spacer()

                if playback.frames.isEmpty {
                    RadarUnavailableCard()
                }

                RadarPlaybackControls(playback: playback)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: store.snapshot.location.id) {
            recenter()
        }
    }

    private func recenter() {
        cameraPosition = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: store.snapshot.location.latitude,
                    longitude: store.snapshot.location.longitude
                ),
                latitudinalMeters: 180_000,
                longitudinalMeters: 180_000
            )
        )
    }
}

private struct RadarHeader: View {
    let location: WeatherLocation
    let onRecenter: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Radar")
                    .font(.title2.bold())

                Text(location.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("NOAA")
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.thinMaterial, in: Capsule())

            Button(action: onRecenter) {
                Image(systemName: "location.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("Recenter radar map")
        }
        .foregroundStyle(.primary)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct RadarUnavailableCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(WeatherTheme.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text("Radar feed ready for connection")
                    .font(.subheadline.weight(.semibold))

                Text("The map and playback surface are built. NOAA frame discovery is intentionally not enabled yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
