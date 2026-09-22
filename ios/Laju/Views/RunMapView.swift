import MapKit
import SwiftUI

/// T1.8: live map during tracking (product-spec.md §4.8). `MKMapView` via
/// `UIViewRepresentable` is the locked choice, not SwiftUI `Map` —
/// `Map`'s polyline overlay support needs iOS 17+, but this app's
/// deployment target is iOS 16.0 (tech-spec.md §5.1, Round 7 finding
/// B7-7).
struct RunMapView: UIViewRepresentable {
    let currentCoordinate: CLLocationCoordinate2D?
    let routeCoordinates: [CLLocationCoordinate2D]

    /// Run Tracking Screen (Fase 1 UI): drives the annotation's heading
    /// cone. `nil` on the static (post-run) map — no heading to show for
    /// a finished route. Defaulted so `RunSummaryView`'s existing
    /// `RunMapView(currentCoordinate: nil, routeCoordinates:)` call site
    /// (T1.9) doesn't need updating.
    var headingDegrees: CLLocationDirection?

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        // Deliberately NOT showsUserLocation — that starts MapKit's own
        // internal location subscription, invisible at any
        // CLLocationManager call site and violating product-spec §4.8
        // AC3 ("no new GPS request") — see tech-spec.md §5.1, Round 7
        // finding B7-8. Position comes from `currentCoordinate` (a
        // custom annotation) instead, fed by RunViewModel.
        mapView.showsUserLocation = false
        mapView.delegate = context.coordinator
        // Dark-rendered map tiles (design-notes.md §1: Laju is dark-native app-wide, not system-following) —
        // MapKit's own dark style, not just a dark overlay on light tiles.
        mapView.overrideUserInterfaceStyle = .dark
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        updateAnnotation(on: mapView, coordinator: context.coordinator)
        updatePolyline(on: mapView, coordinator: context.coordinator)
        centerIfNeeded(on: mapView, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleUIView(_: MKMapView, coordinator: Coordinator) {
        coordinator.motion.stop()
    }

    /// Mutates one persistent annotation in place (coordinate + heading)
    /// rather than remove/re-add every update — removing and re-adding
    /// an `MKPointAnnotation` on every GPS fix (a few times/second at
    /// worst) causes the default annotation-add animation to replay each
    /// time, a visible "pop" the user would see on every live update.
    ///
    /// The *coordinate* is not assigned here: `RunMapMotion` glides the marker to each new fix over a few
    /// hundred ms (display only — the fix itself, and everything computed from it, is untouched).
    private func updateAnnotation(on mapView: MKMapView, coordinator: Coordinator) {
        guard let currentCoordinate else {
            if let existing = coordinator.userAnnotation {
                mapView.removeAnnotation(existing)
                coordinator.userAnnotation = nil
            }
            coordinator.motion.reset(on: mapView)
            return
        }
        if let existing = coordinator.userAnnotation {
            existing.headingDegrees = headingDegrees
            (mapView.view(for: existing) as? UserLocationAnnotationView)?.updateHeading(headingDegrees)
            coordinator.motion.moveMarker(to: currentCoordinate, annotation: existing, in: mapView)
        } else {
            let annotation = UserLocationAnnotation()
            annotation.coordinate = currentCoordinate
            annotation.headingDegrees = headingDegrees
            coordinator.userAnnotation = annotation
            mapView.addAnnotation(annotation)
            coordinator.motion.moveMarker(to: currentCoordinate, annotation: annotation, in: mapView)
        }
    }

    /// Two overlays with identical coordinates — a wide, low-alpha "glow" underlay added first, then the
    /// crisp core line on top (design-notes.md §3: route line glow effect). `GlowPolyline` is just a marker
    /// subclass so the renderer can tell which pass it's drawing.
    ///
    /// While live, the newest segment is NOT part of these overlays: it is `RunMapMotion`'s `TailOverlay`,
    /// drawn from the previous fix to the gliding marker so the line grows smoothly instead of appearing whole.
    /// Only rebuilt when the route actually changed (SwiftUI also re-runs this for unrelated state).
    private func updatePolyline(on mapView: MKMapView, coordinator: Coordinator) {
        let gliding = endsAtCurrentCoordinate && routeCoordinates.count >= 2
        let committed = gliding ? Array(routeCoordinates.dropLast()) : routeCoordinates
        let key = RunMapRouteKey(
            count: routeCoordinates.count,
            lastLatitude: routeCoordinates.last?.latitude,
            lastLongitude: routeCoordinates.last?.longitude,
            gliding: gliding
        )
        if key != coordinator.renderedRouteKey {
            mapView.removeOverlays(coordinator.committedOverlays)
            coordinator.committedOverlays = []
            if committed.count > 1 {
                let glow = GlowPolyline(coordinates: committed, count: committed.count)
                let core = MKPolyline(coordinates: committed, count: committed.count)
                coordinator.committedOverlays = [glow, core]
                mapView.addOverlays(coordinator.committedOverlays)
            }
            coordinator.renderedRouteKey = key
        }
        coordinator.motion.setTail(anchor: gliding ? committed.last : nil, on: mapView)
    }

    /// Live tracking: the marker's target is the route's newest point (RunViewModel appends the fix to the
    /// route and publishes it as `currentCoordinate` together). Anything else — a pre-run preview fix, a
    /// paused/finished run — draws the route in full with no gliding tail.
    private var endsAtCurrentCoordinate: Bool {
        guard let currentCoordinate, let last = routeCoordinates.last else { return false }
        return last.latitude == currentCoordinate.latitude && last.longitude == currentCoordinate.longitude
    }

    private func centerIfNeeded(on mapView: MKMapView, coordinator: Coordinator) {
        if currentCoordinate != nil {
            // Live tracking (T1.8): stay centered on the user's current position. While a glide is running the
            // camera is moved by the same display link as the marker; this only covers the idle case.
            coordinator.motion.recenterIfIdle(on: mapView)
            return
        }
        // Static map (T1.9, product-spec.md §4.9): no live position — fit
        // the WHOLE route once. Only once, not on every `updateUIView`
        // call, so it doesn't fight the user's own pan/zoom afterward.
        guard !coordinator.hasFitStaticRoute, routeCoordinates.count > 1 else { return }
        let polyline = MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
        mapView.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
            animated: false
        )
        coordinator.hasFitStaticRoute = true
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var hasFitStaticRoute = false
        var userAnnotation: UserLocationAnnotation?
        let motion = RunMapMotion()
        var committedOverlays: [MKOverlay] = []
        var renderedRouteKey: RunMapRouteKey?

        func mapView(_: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is TailOverlay {
                return TailRenderer(overlay: overlay, accent: UIColor(LajuColor.accent))
            }
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            let accent = UIColor(LajuColor.accent)
            if overlay is GlowPolyline {
                renderer.strokeColor = accent.withAlphaComponent(0.35)
                renderer.lineWidth = 14
            } else {
                renderer.strokeColor = accent
                renderer.lineWidth = 4
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? UserLocationAnnotation else { return nil }
            let identifier = "userLocation"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                as? UserLocationAnnotationView
                ?? UserLocationAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.updateHeading(annotation.headingDegrees)
            return view
        }
    }
}

/// What the committed route overlays were last built from — lets `updatePolyline` skip a rebuild when SwiftUI
/// re-runs `updateUIView` for unrelated state (the elapsed-time tick).
struct RunMapRouteKey: Equatable {
    let count: Int
    let lastLatitude: Double?
    let lastLongitude: Double?
    let gliding: Bool
}

/// Marker subclass distinguishing the glow-underlay pass from the crisp core line — see `updatePolyline`.
final class GlowPolyline: MKPolyline {}

/// Backs the map's position indicator. A plain `MKPointAnnotation`
/// can't also carry heading, and `MKAnnotation` conformance needs a
/// class (not a struct), so this is the minimal custom type — see
/// `UserLocationAnnotationView` for how heading is drawn.
final class UserLocationAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D = .init()
    var headingDegrees: CLLocationDirection?
}

/// "White dot + lime ring/cone" position indicator (design-notes.md §1) — white core so it stays visually
/// distinct from the lime route line itself (both lime would blend together); the ring/cone still carry the
/// brand accent. The cone shows direction of travel (`CLLocation.course`) — the map itself never rotates (no
/// compass/heading tracking mode, which would require `showsUserLocation` and violate B7-8), so the cone's
/// own rotation is the only thing that encodes heading.
final class UserLocationAnnotationView: MKAnnotationView {
    private let coneLayer = CAShapeLayer()
    private let dotLayer = CAShapeLayer()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        backgroundColor = .clear
        setUpLayers()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) not used — this view is only ever created in code")
    }

    private func setUpLayers() {
        coneLayer.frame = bounds
        dotLayer.frame = bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        let coneWidth: CGFloat = 26
        let coneHeight: CGFloat = 22
        let conePath = UIBezierPath()
        conePath.move(to: CGPoint(x: center.x, y: center.y - coneHeight))
        conePath.addLine(to: CGPoint(x: center.x - coneWidth / 2, y: center.y))
        conePath.addLine(to: CGPoint(x: center.x + coneWidth / 2, y: center.y))
        conePath.close()
        let accent = UIColor(LajuColor.accent)
        coneLayer.path = conePath.cgPath
        coneLayer.fillColor = accent.withAlphaComponent(0.28).cgColor
        coneLayer.isHidden = true
        layer.addSublayer(coneLayer)

        let dotDiameter: CGFloat = 16
        let dotRect = CGRect(
            x: center.x - dotDiameter / 2,
            y: center.y - dotDiameter / 2,
            width: dotDiameter,
            height: dotDiameter
        )
        dotLayer.path = UIBezierPath(ovalIn: dotRect).cgPath
        dotLayer.fillColor = UIColor.white.cgColor
        dotLayer.strokeColor = accent.cgColor
        dotLayer.lineWidth = 3
        layer.addSublayer(dotLayer)
    }

    /// `degrees` is `CLLocation.course` — degrees clockwise from true
    /// north. The map is north-up and never rotates (see class doc), so
    /// rotating the cone by this amount directly is correct.
    func updateHeading(_ degrees: CLLocationDirection?) {
        guard let degrees, degrees >= 0 else {
            coneLayer.isHidden = true
            return
        }
        coneLayer.isHidden = false
        coneLayer.transform = CATransform3DMakeRotation(degrees * .pi / 180, 0, 0, 1)
    }
}
