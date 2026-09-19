import MapKit
import SwiftUI

struct RadarMapView: View {
    let location: WeatherLocation
    @Binding var cameraPosition: MapCameraPosition

    var body: some View {
        Map(position: $cameraPosition, interactionModes: .all) {
            Marker(
                location.name,
                coordinate: CLLocationCoordinate2D(
                    latitude: location.latitude,
                    longitude: location.longitude
                )
            )
            .tint(WeatherTheme.accent)
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .background(Color.black.opacity(0.04))
        .clipShape(Rectangle())
    }
}
