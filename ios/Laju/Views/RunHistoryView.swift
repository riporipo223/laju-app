import CoreData
import CoreLocation
@preconcurrency import MapKit
import SwiftUI
import UIKit

/// T1.5: local run history — product-spec.md §4.18 (promoted to
/// Must-have 2026-09-13, Round 7 finding N7-4 — T1.9's static map on this
/// screen is itself a Must-have AC, so this screen can no longer be cut).
/// `@FetchRequest` keeps this screen live-updating whenever a run is
/// added/changed, no manual refresh needed. **Restyled 2026-09-14** onto
/// the real design system (design-notes.md §5) — same data/fetch, dark
/// card rows with the top-accent-line signature. **T4.15 (2026-09-24):**
/// `RunHistoryRow` gained a "Post pencapaian" entry point on
/// validated/approved rows — see `SocialPostComposerView`'s own comment
/// for why here and not `RunSummaryView`.
struct RunHistoryView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Run.startedAt, ascending: false)]
    )
    private var runs: FetchedResults<Run>

    var body: some View {
        Group {
            if runs.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(runs) { run in
                            RunHistoryRow(run: run)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(LajuColor.background.ignoresSafeArea())
        .navigationTitle("Run History")
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.run")
                .font(.largeTitle)
                .foregroundStyle(LajuColor.accent)
            Text("No runs yet")
                .font(LajuFont.heading)
                .foregroundStyle(LajuColor.textPrimary)
            Text("Complete a run to see it here.")
                .font(.subheadline)
                .foregroundStyle(LajuColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LajuColor.background.ignoresSafeArea())
    }
}

private struct RunHistoryRow: View {
    /// `@ObservedObject` (not a plain `let`): T2.14d rewrites `serverStatus`/`anomalyFlags` on an existing row
    /// when a flagged run later resolves — the row must re-render on that attribute change, not only when the
    /// fetched list itself gains/loses a run.
    @ObservedObject var run: Run
    @State private var showPostSheet = false

    /// T4.15 v1 AC (phase-4-backlog.md): only a validated/approved run can be posted — checked against
    /// `serverStatus`, the server-confirmed outcome (never the local `estimatedPoints`/offline state, which
    /// says nothing about anti-cheat resolution).
    private var isPostable: Bool {
        run.serverRunId != nil && (run.serverStatus == "validated" || run.serverStatus == "approved")
    }

    var body: some View {
        HStack(spacing: 12) {
            RunRouteThumbnailView(gpsRouteData: run.gpsRoute)

            VStack(alignment: .leading, spacing: 4) {
                (
                    Text(run.startedAt ?? Date(), style: .date).foregroundColor(LajuColor.textPrimary)
                        + Text(" ").foregroundColor(LajuColor.textPrimary)
                        + Text(run.startedAt ?? Date(), style: .time).foregroundColor(LajuColor.textPrimary)
                )
                .font(.subheadline.weight(.semibold))

                HStack {
                    Text(DistanceFormatter.format(meters: run.distanceMeters))
                    Spacer()
                    Text(speedText)
                    Spacer()
                    Text(String(format: "%.1f pts", run.estimatedPoints))
                        .foregroundStyle(LajuColor.accent)
                }
                .font(.subheadline)
                .foregroundStyle(LajuColor.textSecondary)

                if let copy = run.statusCopy {
                    statusView(copy)
                }

                if isPostable {
                    Button("Post pencapaian") { showPostSheet = true }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LajuColor.accent)
                        .padding(.top, 2)
                }
            }
        }
        .padding(12)
        .background(LajuColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 1)
                .fill(LajuColor.accent)
                .frame(height: 2)
                .padding(.horizontal, 16)
                .padding(.top, 1)
        }
        .sheet(isPresented: $showPostSheet) {
            if let serverRunId = run.serverRunId {
                SocialPostComposerView(runId: serverRunId, onPosted: {})
            }
        }
    }

    /// T2.14b: status-appropriate copy from the local server-outcome attributes — never the raw status string
    /// or raw flag codes.
    private func statusView(_ copy: RunStatusCopy) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(copy.headline)
                .font(.caption.weight(.semibold))
                .foregroundStyle(run.serverStatus == "rejected" ? LajuColor.textPrimary : LajuColor.accent)
            ForEach(copy.reasons, id: \.self) { reason in
                Text("• \(reason)")
                    .font(.caption)
                    .foregroundStyle(LajuColor.textSecondary)
            }
        }
        .padding(.top, 2)
    }

    private var speedText: String {
        guard run.distanceMeters > 0 else { return "—" }
        let distanceKm = run.distanceMeters / 1000
        return SpeedFormatter.format(secPerKm: run.durationSeconds / distanceKm)
    }
}

/// T1.9: cached static-route thumbnail for Run History rows — a live
/// `MKMapView` per row is a known scroll-performance trap (tech-spec.md
/// §5.1, Round 7 finding N7-9), so this renders one `MKMapSnapshotter`
/// image instead, off the main thread via `.task`. `MKMapSnapshotter` has
/// no overlay support of its own, so the route polyline is drawn on top
/// of the raw snapshot manually.
private struct RunRouteThumbnailView: View {
    let gpsRouteData: Data?

    @State private var image: UIImage?
    @State private var hasNoRoute = false

    private static let size = CGSize(width: 60, height: 60)

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else if hasNoRoute {
                Image(systemName: "location.slash")
                    .foregroundStyle(LajuColor.textSecondary)
            } else {
                LajuColor.surfaceRaised
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task {
            let coordinates = GPSPoint.decodeRoute(from: gpsRouteData).map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
            }
            guard coordinates.count > 1 else {
                hasNoRoute = true
                return
            }
            image = await Self.renderSnapshot(routeCoordinates: coordinates)
        }
    }

    private static func renderSnapshot(routeCoordinates: [CLLocationCoordinate2D]) async -> UIImage? {
        let polyline = MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count)
        let options = MKMapSnapshotter.Options()
        options.mapRect = polyline.boundingMapRect
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)
            guard let context = UIGraphicsGetCurrentContext() else { return }
            context.setStrokeColor(UIColor(LajuColor.accent).cgColor)
            context.setLineWidth(3)
            let path = UIBezierPath()
            for (index, coordinate) in routeCoordinates.enumerated() {
                let point = snapshot.point(for: coordinate)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.stroke()
        }
    }
}

#Preview {
    NavigationStack {
        RunHistoryView()
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
    .preferredColorScheme(.dark)
}
