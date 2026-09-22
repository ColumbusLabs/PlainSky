import MapKit
import SwiftUI

struct RadarMapView: UIViewRepresentable {
    let location: WeatherLocation
    let frames: [RadarFrame]
    let selectedFrameID: String?
    let recenterToken: Int
    var isInteractive = true
    var regionMeters: CLLocationDistance = 180_000
    var legalInsets: UIEdgeInsets = .zero
    var onPrefetchUpdate: ((RadarPrefetchUpdate) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.mapType = .mutedStandard
        mapView.pointOfInterestFilter = .excludingAll
        mapView.isPitchEnabled = false
        mapView.showsScale = false
        mapView.register(
            LocationDotAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: LocationDotAnnotationView.reuseIdentifier
        )

        if isInteractive {
            mapView.showsCompass = true
            mapView.isRotateEnabled = true
        } else {
            mapView.isUserInteractionEnabled = false
            mapView.showsCompass = false
            mapView.isRotateEnabled = false
        }

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        if mapView.layoutMargins != legalInsets {
            mapView.layoutMargins = legalInsets
        }

        context.coordinator.onPrefetchUpdate = onPrefetchUpdate
        context.coordinator.updateLocation(
            location,
            recenterToken: recenterToken,
            regionMeters: regionMeters,
            on: mapView
        )
        context.coordinator.updateRadar(
            frames: frames,
            selectedFrameID: selectedFrameID,
            on: mapView
        )
    }

    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        coordinator.cancelPrefetch()
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        private static let radarAlpha: CGFloat = 0.8
        /// Long enough for the incoming frame's cached tiles to draw before the outgoing
        /// frame is removed, so frame changes never flash an empty map.
        private static let handoffDelay: TimeInterval = 0.25
        private static let maximumConcurrentTileLoads = 12
        private static let maximumTilesPerZoom = 48

        var onPrefetchUpdate: ((RadarPrefetchUpdate) -> Void)?

        private var annotation: MKPointAnnotation?
        private var frames: [RadarFrame] = []
        private var displayedFrameID: String?
        private var currentOverlay: (any RadarTileOverlay)?
        private var lastLocationID: UUID?
        private var lastRecenterToken = -1
        private var prefetchTask: Task<Void, Never>?
        private var regionPrefetchWork: DispatchWorkItem?
        private var lastKnownZoom: Int?

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

        func updateRadar(
            frames: [RadarFrame],
            selectedFrameID: String?,
            on mapView: MKMapView
        ) {
            if frames.map(\.id) != self.frames.map(\.id) {
                self.frames = frames
                requestPrefetch(on: mapView)

                if let displayedFrameID, !frames.contains(where: { $0.id == displayedFrameID }) {
                    show(frameID: nil, on: mapView)
                }
            }

            guard selectedFrameID != displayedFrameID else { return }
            show(frameID: selectedFrameID, on: mapView)
        }

        func cancelPrefetch() {
            prefetchTask?.cancel()
            regionPrefetchWork?.cancel()
        }

        private func show(frameID: String?, on mapView: MKMapView) {
            displayedFrameID = frameID
            let outgoing = currentOverlay

            if let frameID, let frame = frames.first(where: { $0.id == frameID }) {
                let overlay = RadarTileOverlayFactory.overlay(for: frame)
                currentOverlay = overlay
                mapView.addOverlay(overlay, level: .aboveRoads)
            } else {
                currentOverlay = nil
            }

            guard let outgoing else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.handoffDelay) { [weak mapView] in
                mapView?.removeOverlay(outgoing)
            }
        }

        // MARK: Prefetching

        /// Debounced so MapKit has requested tiles for the visible frame first, which tells
        /// prefetching exactly which zoom level to load.
        private func requestPrefetch(on mapView: MKMapView) {
            regionPrefetchWork?.cancel()
            let work = DispatchWorkItem { [weak self, weak mapView] in
                guard let self, let mapView else { return }
                self.schedulePrefetch(on: mapView)
            }
            regionPrefetchWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }

        private func schedulePrefetch(on mapView: MKMapView) {
            prefetchTask?.cancel()

            if let zoom = currentOverlay?.zoomRecorder.lastRequestedZoom {
                lastKnownZoom = zoom
            }

            let frames = Self.playbackOrder(self.frames, after: displayedFrameID)
            let tiles = Self.visibleTilePaths(for: mapView, knownZoom: lastKnownZoom)

            guard frames.count > 1, !tiles.primary.isEmpty else {
                report(RadarPrefetchUpdate(progress: 1, readyFrameIDs: Set(self.frames.map(\.id))))
                return
            }

            let overlays = Dictionary(uniqueKeysWithValues: frames.map {
                ($0.id, RadarTileOverlayFactory.overlay(for: $0))
            })
            let primaryJobs = frames.flatMap { frame in
                tiles.primary.map { PrefetchJob(frameID: frame.id, path: $0, gatesReadiness: true) }
            }
            let secondaryJobs = frames.flatMap { frame in
                tiles.secondary.map { PrefetchJob(frameID: frame.id, path: $0, gatesReadiness: false) }
            }
            let jobs = primaryJobs + secondaryJobs
            let tilesPerFrame = tiles.primary.count

            let initiallyReady: Set<String> = displayedFrameID.map { [$0] } ?? []
            report(RadarPrefetchUpdate(progress: 0, readyFrameIDs: initiallyReady))

            prefetchTask = Task { [weak self] in
                var ready = initiallyReady
                var remaining = Dictionary(uniqueKeysWithValues: frames.map { ($0.id, tilesPerFrame) })
                var completedPrimary = 0

                await withTaskGroup(of: PrefetchJob.self) { group in
                    var iterator = jobs.makeIterator()

                    for _ in 0..<Self.maximumConcurrentTileLoads {
                        guard let job = iterator.next(), let overlay = overlays[job.frameID] else { break }
                        group.addTask { await Self.load(job.path, from: overlay); return job }
                    }

                    while let finished = await group.next() {
                        guard !Task.isCancelled else {
                            group.cancelAll()
                            return
                        }

                        if finished.gatesReadiness {
                            completedPrimary += 1
                            remaining[finished.frameID, default: 1] -= 1

                            if remaining[finished.frameID] == 0 {
                                ready.insert(finished.frameID)
                                self?.report(RadarPrefetchUpdate(
                                    progress: Double(completedPrimary) / Double(primaryJobs.count),
                                    readyFrameIDs: ready
                                ))
                            }
                        }

                        if let job = iterator.next(), let overlay = overlays[job.frameID] {
                            group.addTask { await Self.load(job.path, from: overlay); return job }
                        }
                    }
                }
            }
        }

        /// Frames in the order playback will reach them, starting after the one on screen.
        private static func playbackOrder(_ frames: [RadarFrame], after frameID: String?) -> [RadarFrame] {
            guard let frameID, let index = frames.firstIndex(where: { $0.id == frameID }) else {
                return frames
            }
            return Array(frames[(index + 1)...] + frames[...index])
        }

        /// Deferred so updates never mutate SwiftUI state during `updateUIView`.
        private func report(_ update: RadarPrefetchUpdate) {
            DispatchQueue.main.async { [weak self] in
                self?.onPrefetchUpdate?(update)
            }
        }

        private nonisolated static func load(
            _ path: MKTileOverlayPath,
            from overlay: any RadarTileOverlay
        ) async {
            await withCheckedContinuation { continuation in
                overlay.prefetchTile(at: path) { _, _ in
                    continuation.resume()
                }
            }
        }

        /// Tiles MapKit will request for the current viewport. Once MapKit's zoom level is
        /// known only that level is loaded; before then the nearest level gates playback and
        /// the neighboring level loads afterward as a fallback.
        private static func visibleTilePaths(
            for mapView: MKMapView,
            knownZoom: Int?
        ) -> (primary: [MKTileOverlayPath], secondary: [MKTileOverlayPath]) {
            let visible = mapView.visibleMapRect
            guard mapView.bounds.width > 0, visible.size.width > 0 else { return ([], []) }

            let rect = visible.insetBy(dx: -visible.size.width * 0.05, dy: -visible.size.height * 0.05)
            let worldWidth = MKMapSize.world.width
            let pointsPerMapPoint = Double(mapView.bounds.width) / visible.size.width
            let exactZoom = log2(worldWidth * pointsPerMapPoint / 256)
            let scale = mapView.traitCollection.displayScale

            func clamp(_ zoom: Double) -> Int { min(max(Int(zoom), 2), 14) }

            func paths(at zoom: Int) -> [MKTileOverlayPath] {
                let tileCount = 1 << zoom
                let tileSpan = worldWidth / Double(tileCount)
                let minX = max(0, Int(floor(rect.minX / tileSpan)))
                let maxX = min(tileCount - 1, Int(floor(rect.maxX / tileSpan)))
                let minY = max(0, Int(floor(rect.minY / tileSpan)))
                let maxY = min(tileCount - 1, Int(floor(rect.maxY / tileSpan)))
                guard minX <= maxX, minY <= maxY else { return [] }

                var paths: [MKTileOverlayPath] = []
                for x in minX...maxX {
                    for y in minY...maxY {
                        paths.append(MKTileOverlayPath(x: x, y: y, z: zoom, contentScaleFactor: scale))
                    }
                }
                return Array(paths.prefix(maximumTilesPerZoom))
            }

            if let knownZoom, abs(Double(knownZoom) - exactZoom) < 1.5 {
                return (paths(at: knownZoom), [])
            }

            let nearest = clamp(exactZoom.rounded())
            let neighbor = clamp(exactZoom.rounded() == exactZoom.rounded(.down)
                ? exactZoom.rounded(.up)
                : exactZoom.rounded(.down))
            return (paths(at: nearest), neighbor == nearest ? [] : paths(at: neighbor))
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard frames.count > 1 else { return }
            requestPrefetch(on: mapView)
        }

        func mapView(
            _ mapView: MKMapView,
            rendererFor overlay: MKOverlay
        ) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? any RadarTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
                renderer.alpha = Self.radarAlpha
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(
            _ mapView: MKMapView,
            viewFor annotation: MKAnnotation
        ) -> MKAnnotationView? {
            mapView.dequeueReusableAnnotationView(
                withIdentifier: LocationDotAnnotationView.reuseIdentifier,
                for: annotation
            )
        }
    }
}

struct RadarPrefetchUpdate: Equatable {
    let progress: Double
    let readyFrameIDs: Set<String>
}

private struct PrefetchJob {
    let frameID: String
    let path: MKTileOverlayPath
    let gatesReadiness: Bool
}

private final class LocationDotAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "LocationDot"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        let size: CGFloat = 20
        frame = CGRect(x: 0, y: 0, width: size, height: size)
        canShowCallout = false

        let ring = UIView(frame: bounds)
        ring.backgroundColor = .white
        ring.layer.cornerRadius = size / 2
        ring.layer.shadowColor = UIColor.black.cgColor
        ring.layer.shadowOpacity = 0.25
        ring.layer.shadowRadius = 3
        ring.layer.shadowOffset = CGSize(width: 0, height: 1)

        let dot = UIView(frame: bounds.insetBy(dx: 4, dy: 4))
        dot.backgroundColor = UIColor(WeatherTheme.accent)
        dot.layer.cornerRadius = (size - 8) / 2

        addSubview(ring)
        addSubview(dot)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
