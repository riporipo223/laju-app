import MapKit
import UIKit

/// Pure interpolation between two already-accepted GPS fixes. Purely a *display* concern: it never
/// creates, filters or stores a point — `RunViewModel` still decides which fixes exist, and distance/pace/points
/// are computed from those alone. This only decides where the marker and the head of the route line are drawn
/// *between* two such fixes.
struct MarkerTween {
    let from: CLLocationCoordinate2D
    let to: CLLocationCoordinate2D
    let startTime: TimeInterval
    let duration: TimeInterval

    /// Bounds for how long the marker takes to glide to a new fix. Kept short so the marker never trails far
    /// behind the runner: at 3 m/s the worst-case lag is ~2.4 m. The floor keeps bursts of fixes from
    /// turning into a jitter.
    static let minimumDuration: TimeInterval = 0.3
    static let maximumDuration: TimeInterval = 0.8
    /// A jump this big is not running — it is a resume after a pause or a first fix. Glide would only
    /// draw a long fake line across the map, so snap instead.
    static let snapDistanceMeters: CLLocationDistance = 100

    /// `nil` (no earlier fix to measure against) uses the upper bound.
    static func duration(sinceLastFix interval: TimeInterval?) -> TimeInterval {
        guard let interval else { return maximumDuration }
        return min(max(interval, minimumDuration), maximumDuration)
    }

    static func shouldSnap(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Bool {
        let start = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let end = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return start.distance(from: end) > snapDistanceMeters
    }

    func progress(at time: TimeInterval) -> Double {
        guard duration > 0 else { return 1 }
        return min(max((time - startTime) / duration, 0), 1)
    }

    func isFinished(at time: TimeInterval) -> Bool {
        progress(at: time) >= 1
    }

    /// Linear, not eased: a runner moves at roughly constant speed, and easing would make the marker
    /// visibly pulse on every fix. Sub-100 m distances, so plain lat/lng interpolation is exact enough.
    func coordinate(at time: TimeInterval) -> CLLocationCoordinate2D {
        let fraction = progress(at: time)
        return CLLocationCoordinate2D(
            latitude: from.latitude + (to.latitude - from.latitude) * fraction,
            longitude: from.longitude + (to.longitude - from.longitude) * fraction
        )
    }
}

/// The still-growing last segment of the route: from the previous fix to wherever the marker is *right now*.
/// Everything older is a normal immutable `MKPolyline`; only this one segment is redrawn per frame. Read by
/// MapKit's tile threads while the main thread mutates it, hence the lock.
final class TailOverlay: NSObject, MKOverlay, @unchecked Sendable {
    private let lock = NSLock()
    private var anchor = CLLocationCoordinate2D()
    private var head = CLLocationCoordinate2D()

    var coordinate: CLLocationCoordinate2D {
        segment().anchor
    }

    /// Whole world: the rect can't be kept in sync with a per-frame moving head, and drawing a two-point
    /// segment for each requested tile is trivially cheap.
    var boundingMapRect: MKMapRect {
        .world
    }

    func update(anchor: CLLocationCoordinate2D? = nil, head: CLLocationCoordinate2D? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let anchor {
            self.anchor = anchor
        }
        if let head {
            self.head = head
        }
    }

    func segment() -> (anchor: CLLocationCoordinate2D, head: CLLocationCoordinate2D) {
        lock.lock()
        defer { lock.unlock() }
        return (anchor, head)
    }
}

/// Draws `TailOverlay` with the same glow + core styling `RunMapView`'s `MKPolylineRenderer`s use.
final class TailRenderer: MKOverlayRenderer {
    private let accent: UIColor

    init(overlay: MKOverlay, accent: UIColor) {
        self.accent = accent
        super.init(overlay: overlay)
    }

    override func draw(_: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let tail = overlay as? TailOverlay else { return }
        let segment = tail.segment()
        let start = point(for: MKMapPoint(segment.anchor))
        let end = point(for: MKMapPoint(segment.head))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        // (screen-point width, alpha): glow underlay first, crisp core on top — line widths are given in
        // screen points, so divide by the zoom scale to get map-point units.
        for (width, alpha) in [(14.0, 0.35), (4.0, 1.0)] {
            context.setStrokeColor(accent.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(width / zoomScale)
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        }
    }
}

/// Drives the smooth movement on `MKMapView`. One `CADisplayLink` interpolates a single display position and
/// applies it to three things in the same frame — the marker, the head of the route line, and the follow camera —
/// so they can never drift apart. Idle (link paused) between fixes, so it costs nothing while standing still.
@MainActor
final class RunMapMotion: NSObject {
    /// Same 500 m framing `RunMapView` has always used for the live follow camera.
    private static let followSpanMeters: CLLocationDistance = 500

    let tail = TailOverlay()
    private var tailIsOnMap = false
    private var tween: MarkerTween?
    private var lastTarget: CLLocationCoordinate2D?
    private var lastFixTime: CFTimeInterval?
    private var displayLink: CADisplayLink?
    private weak var mapView: MKMapView?
    private weak var annotation: UserLocationAnnotation?

    /// Glide to `target` — a fix that already passed every filter. Ignores repeats of the same coordinate
    /// (SwiftUI re-runs `updateUIView` for unrelated state, e.g. the elapsed-time tick).
    func moveMarker(to target: CLLocationCoordinate2D, annotation: UserLocationAnnotation, in mapView: MKMapView) {
        self.mapView = mapView
        self.annotation = annotation
        if let last = lastTarget, last.latitude == target.latitude, last.longitude == target.longitude {
            return
        }

        let now = CACurrentMediaTime()
        let interval = lastFixTime.map { now - $0 }
        let isFirstFix = lastTarget == nil
        lastTarget = target
        lastFixTime = now

        let from = annotation.coordinate
        if isFirstFix || UIAccessibility.isReduceMotionEnabled || MarkerTween.shouldSnap(from: from, to: target) {
            tween = nil
            display(target)
            return
        }
        // Retargets from where the marker is *now*, so a fix arriving mid-glide never makes it jump back.
        tween = MarkerTween(
            from: from,
            to: target,
            startTime: now,
            duration: MarkerTween.duration(sinceLastFix: interval)
        )
        displayLinkForFrames().isPaused = false
    }

    /// Show the still-growing last segment, or take it off the map when there is nothing to grow.
    func setTail(anchor: CLLocationCoordinate2D?, on mapView: MKMapView) {
        guard let anchor else {
            if tailIsOnMap {
                mapView.removeOverlay(tail)
                tailIsOnMap = false
            }
            return
        }
        tail.update(anchor: anchor, head: annotation?.coordinate ?? anchor)
        if tailIsOnMap {
            (mapView.renderer(for: tail) as? TailRenderer)?.setNeedsDisplay()
        } else {
            mapView.addOverlay(tail)
            tailIsOnMap = true
        }
    }

    /// Keep the follow camera on the displayed position when SwiftUI re-renders without a new fix.
    func recenterIfIdle(on mapView: MKMapView) {
        guard tween == nil, let coordinate = annotation?.coordinate ?? lastTarget else { return }
        mapView.setRegion(Self.followRegion(around: coordinate), animated: false)
    }

    /// The live position went away (run ended): forget it, so the next run's first fix snaps into place
    /// instead of gliding across the map from wherever the previous one stopped.
    func reset(on mapView: MKMapView) {
        tween = nil
        lastTarget = nil
        lastFixTime = nil
        displayLink?.isPaused = true
        setTail(anchor: nil, on: mapView)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        tween = nil
    }

    private func displayLinkForFrames() -> CADisplayLink {
        if let displayLink {
            return displayLink
        }
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
        return link
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let tween else {
            link.isPaused = true
            return
        }
        let now = CACurrentMediaTime()
        display(tween.coordinate(at: now))
        if tween.isFinished(at: now) {
            self.tween = nil
            link.isPaused = true
        }
    }

    private func display(_ coordinate: CLLocationCoordinate2D) {
        annotation?.coordinate = coordinate
        guard let mapView else { return }
        tail.update(head: coordinate)
        (mapView.renderer(for: tail) as? TailRenderer)?.setNeedsDisplay()
        mapView.setRegion(Self.followRegion(around: coordinate), animated: false)
    }

    private static func followRegion(around center: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            latitudinalMeters: followSpanMeters,
            longitudinalMeters: followSpanMeters
        )
    }
}
