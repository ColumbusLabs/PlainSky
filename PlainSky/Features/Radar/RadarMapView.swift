import MapKit
import SwiftUI

struct RadarMapView: UIViewRepresentable {
    let location: WeatherLocation
    let frame: RadarFrame?
    let recenterToken: Int
    var isInteractive = true

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.mapType = .mutedStandard
        mapView.isPitchEnabled = false

        if isInteractive {
            mapView.showsCompass = true
            mapView.showsScale = true
            mapView.pointOfInterestFilter = .includingAll
            mapView.isRotateEnabled = true
        } else {
            mapView.isUserInteractionEnabled = false
            mapView.showsCompass = false
            mapView.showsScale = false
            mapView.pointOfInterestFilter = .excludingAll
            mapView.isRotateEnabled = false
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.updateLocation(
            location,
            recenterToken: recenterToken,
            regionMeters: isInteractive ? 180_000 : 90_000,
            on: mapView
        )
        context.coordinator.updateRadarFrame(frame, on: mapView)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var annotation: MKPointAnnotation?
        private var radarOverlay: RadarWMSTileOverlay?
        private var lastLocationID: UUID?
        private var lastRecenterToken = -1
        private var lastFrameID: String?

        func updateLocation(
            _ location: WeatherLocation,
            recenterToken: Int,
            regionMeters: CLLocationDistance,
            on mapView: MKMapView
        ) {
            let coordinate = CLLocationCoordinate2D(
                latitude: location.latitude,
                longitude: location.longitude
            )

            if annotation == nil {
                let annotation = MKPointAnnotation()
                self.annotation = annotation
                mapView.addAnnotation(annotation)
            }

            annotation?.coordinate = coordinate
            annotation?.title = location.name

            let locationChanged = lastLocationID != location.id
            let recenterRequested = lastRecenterToken != recenterToken

            if locationChanged || recenterRequested {
                mapView.setRegion(
                    MKCoordinateRegion(
                        center: coordinate,
                        latitudinalMeters: regionMeters,
                        longitudinalMeters: regionMeters
                    ),
                    animated: !locationChanged
                )

                lastLocationID = location.id
                lastRecenterToken = recenterToken
            }
        }

        func updateRadarFrame(
            _ frame: RadarFrame?,
            on mapView: MKMapView
        ) {
            guard lastFrameID != frame?.id else { return }

            if let radarOverlay {
                mapView.removeOverlay(radarOverlay)
                self.radarOverlay = nil
            }

            lastFrameID = frame?.id

            guard let frame else { return }

            let overlay = RadarWMSTileOverlay(frame: frame)
            radarOverlay = overlay
            mapView.addOverlay(overlay, level: .aboveRoads)
        }

        func mapView(
            _ mapView: MKMapView,
            rendererFor overlay: MKOverlay
        ) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? RadarWMSTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
                renderer.alpha = 0.76
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
