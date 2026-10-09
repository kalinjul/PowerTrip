import MapKit
import SwiftUI
import Shared

/// Where the home screen wants the camera; each command carries its own id so the same target can be asked for twice.
struct CameraCommand: Equatable {
    enum Target: Equatable {
        case position(LatLon, meters: Double)
        case route
        /// Close enough for full markers, around the current centre.
        case pillZoom
    }

    let id: Int
    let target: Target
}

/// Apple's map with the shared ViewModel's chargers, or the planned trip's route instead of them.
struct ChargerMapView: View {
    let position: LatLon?
    let chargers: [MapCharger]
    let plan: TripPlan?
    let command: CameraCommand?
    /// Room the trip sheet takes at the bottom, so a fitted route stays above it.
    let bottomInset: CGFloat
    let onViewportChanged: (BoundingBox?) -> Void
    let onChargerTapped: (MapCharger) -> Void
    let onStopTapped: (PlannedStop) -> Void

    @State private var camera: MapCameraPosition = .automatic
    @State private var followedFirstFix = false
    @State private var compact = false
    @State private var region: MKCoordinateRegion?

    var body: some View {
        GeometryReader { geometry in
            map(widthPoints: geometry.size.width)
        }
    }

    private func map(widthPoints: CGFloat) -> some View {
        Map(position: $camera) {
            UserAnnotation()
            if let plan {
                MapPolyline(coordinates: plan.route.points.map(\.coordinate))
                    .stroke(Brand.primary, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                ForEach(Array(plan.stops.enumerated()), id: \.element.site.id) { index, stop in
                    Annotation(stop.site.operator ?? stop.site.name, coordinate: stop.site.position.coordinate, anchor: .center) {
                        Button { onStopTapped(stop) } label: {
                            RankBadge(number: index + 1, color: Brand.operatorColor(stop.site))
                                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)
                }
                Marker(plan.destination.name, systemImage: "flag.checkered", coordinate: plan.destination.position.coordinate)
                    .tint(Brand.error)
            } else {
                // TODO cluster dense areas (SwiftUI's Map has none; MKMapView's clusteringIdentifier does)
                ForEach(chargers, id: \.site.id) { charger in
                    Annotation(charger.site.name, coordinate: charger.site.position.coordinate, anchor: .center) {
                        Button { onChargerTapped(charger) } label: {
                            Group {
                                if compact {
                                    ChargerDot(charger: charger)
                                } else {
                                    ChargerPill(charger: charger)
                                }
                            }
                            // Larger text than this would bury the map under its own markers.
                            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        }
                        .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapControls {
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            region = context.region
            let degreesPerPoint = context.region.span.longitudeDelta / max(widthPoints, 1)
            compact = degreesPerPoint > Self.degreesPerPoint(atZoom: Self.pillZoom)
            onViewportChanged(degreesPerPoint > Self.degreesPerPoint(atZoom: Self.minChargerZoom) ? nil : Self.viewport(of: context.region))
        }
        .onChange(of: position == nil, initial: true) {
            // The first fix centres the map; after that the camera is the driver's.
            guard !followedFirstFix, let fix = position else { return }
            followedFirstFix = true
            camera = .region(MKCoordinateRegion(center: fix.coordinate, latitudinalMeters: 20_000, longitudinalMeters: 20_000))
        }
        .onChange(of: plan?.route.points.count) {
            if plan != nil { fitRoute() }
        }
        .onChange(of: command) { _, command in
            guard let command else { return }
            withAnimation {
                switch command.target {
                case .position(let target, let meters):
                    camera = .region(MKCoordinateRegion(center: target.coordinate, latitudinalMeters: meters, longitudinalMeters: meters))
                case .route:
                    fitRoute()
                case .pillZoom:
                    guard let region else { return }
                    let longitudeDelta = Self.degreesPerPoint(atZoom: Self.pillZoom) * widthPoints * 0.9
                    let scale = longitudeDelta / max(region.span.longitudeDelta, .ulpOfOne)
                    camera = .region(MKCoordinateRegion(
                        center: region.center,
                        span: MKCoordinateSpan(latitudeDelta: region.span.latitudeDelta * scale, longitudeDelta: longitudeDelta)
                    ))
                }
            }
        }
        .safeAreaPadding(.bottom, bottomInset)
    }

    private func fitRoute() {
        guard let points = plan?.route.points, !points.isEmpty else { return }
        let rects = points.map { MKMapRect(origin: MKMapPoint($0.coordinate), size: MKMapSize(width: 0, height: 0)) }
        let bounds = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        let padded = bounds.insetBy(dx: -bounds.width * 0.08, dy: -bounds.height * 0.08)
        withAnimation { camera = .rect(padded) }
    }

    /// Android's MIN_CHARGER_ZOOM and PILL_ZOOM: below the first nothing loads, below the second pills become dots.
    private static let minChargerZoom = 10.0
    private static let pillZoom = 11.0

    /// What a web-mercator zoom level shows per point, so the thresholds hold on any screen width.
    private static func degreesPerPoint(atZoom zoom: Double) -> Double {
        360 / (256 * pow(2, zoom))
    }

    static func viewport(of region: MKCoordinateRegion) -> BoundingBox {
        let span = region.span
        return BoundingBox(
            south: region.center.latitude - span.latitudeDelta / 2,
            west: region.center.longitude - span.longitudeDelta / 2,
            north: region.center.latitude + span.latitudeDelta / 2,
            east: region.center.longitude + span.longitudeDelta / 2
        )
    }
}

extension LatLon {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}
