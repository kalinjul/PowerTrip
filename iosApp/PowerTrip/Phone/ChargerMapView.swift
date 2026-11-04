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

/// Apple's map with the shared ViewModel's chargers, or the planned trip's route, or "charge now"'s candidates instead of them.
struct ChargerMapView: View {
    let position: LatLon?
    let chargers: [MapCharger]
    let plan: TripPlan?
    /// The open "charge now" sheet: once it has candidates, they replace the other chargers.
    var chargeNow: ChargeNowSheetUiStateOpen? = nil
    let command: CameraCommand?
    /// Room a sheet takes at the bottom, so a fitted route or the candidates stay above it.
    let bottomInset: CGFloat
    let onViewportChanged: (BoundingBox?) -> Void
    let onChargerTapped: (MapCharger) -> Void
    let onStopTapped: (PlannedStop) -> Void
    /// A candidate's disc: selects it.
    var onCandidateTapped: (ChargeNowCandidate) -> Void = { _ in }
    /// The selected candidate's callout: opens its details.
    var onCandidateOpened: (ChargeNowCandidate) -> Void = { _ in }

    @State private var camera: MapCameraPosition = .automatic
    @State private var followedFirstFix = false
    @State private var compact = false
    @State private var region: MKCoordinateRegion?
    @State private var cameraBeforeChargeNow: MKCoordinateRegion?
    // Once the driver moves the map, the camera is theirs until the sheet closes.
    @State private var driverMovedWhileChargeNow = false
    // Camera moves of our own still owed their end callback, so they don't count as the driver's.
    @State private var ownMovesPending = 0

    var body: some View {
        GeometryReader { geometry in
            map(size: geometry.size)
        }
    }

    private func map(size: CGSize) -> some View {
        let widthPoints = size.width
        return Map(position: $camera) {
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
            } else if let chargeNow, let selected = chargeNow.selected, let rank = chargeNow.selectedRank {
                ForEach(Array(candidates.enumerated()), id: \.element.site.id) { index, candidate in
                    if candidate.site.id != selected.site.id {
                        Annotation(candidate.site.name, coordinate: candidate.site.position.coordinate, anchor: .center) {
                            Button { onCandidateTapped(candidate) } label: {
                                RankBadge(number: index + 1, color: Brand.operatorColor(candidate.site))
                                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                Annotation(selected.site.name, coordinate: selected.site.position.coordinate, anchor: .bottom) {
                    Button { onCandidateOpened(selected) } label: {
                        ChargeNowCallout(
                            rank: rank.intValue,
                            color: Brand.operatorColor(selected.site),
                            title: selected.site.operator ?? selected.site.name,
                            meta: chargeNowMeta(selected)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
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
            if ownMovesPending > 0 {
                ownMovesPending -= 1
            } else if chargeNow != nil {
                driverMovedWhileChargeNow = true
            }
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
        .onChange(of: plan.map { [$0.destination.name, "\($0.route.distanceKm)", "\($0.stops.count)"] }) {
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
        .onChange(of: chargeNow != nil) { _, open in
            if open {
                driverMovedWhileChargeNow = false
                ownMovesPending = 0
                cameraBeforeChargeNow = region
            } else if let back = cameraBeforeChargeNow {
                cameraBeforeChargeNow = nil
                // A route that took the map over meanwhile brings its own fit.
                if plan == nil { move(to: .region(back)) }
            }
        }
        .onChange(of: candidates.map(\.site.id)) { _, ids in
            if !ids.isEmpty && !driverMovedWhileChargeNow { fitCandidates() }
        }
        .onChange(of: chargeNow?.selectedSiteId) { _, picked in
            // Only the driver's pick: the nearest one, selected on its own, is part of the fit.
            guard let picked, let candidate = chargeNow?.selected, candidate.site.id == picked, let region else { return }
            let coordinate = candidate.site.position.coordinate
            if !inSight(coordinate, in: region, height: size.height) {
                move(to: .region(MKCoordinateRegion(center: coordinate, span: region.span)))
            }
        }
        .safeAreaPadding(.bottom, bottomInset)
    }

    private var candidates: [ChargeNowCandidate] {
        chargeNow?.result?.candidates ?? []
    }

    private func move(to target: MapCameraPosition) {
        ownMovesPending += 1
        withAnimation { camera = target }
    }

    private func fitRoute() {
        guard let points = plan?.route.points, !points.isEmpty else { return }
        withAnimation { camera = .rect(Self.bounds(of: points.map(\.coordinate), padding: 0.08)) }
    }

    /// The driver and the candidates, with room for the discs and the callout at the edges.
    private func fitCandidates() {
        var coordinates = candidates.map(\.site.position.coordinate)
        if let position { coordinates.append(position.coordinate) }
        guard !coordinates.isEmpty else { return }
        move(to: .rect(Self.bounds(of: coordinates, padding: 0.25)))
    }

    /// Whether the point is on the uncovered part of the map, with room above it for a callout.
    private func inSight(_ coordinate: CLLocationCoordinate2D, in region: MKCoordinateRegion, height: CGFloat) -> Bool {
        let span = region.span
        let covered = height > 0 ? Double(bottomInset / height) : 0
        let callout = 0.15
        let south = region.center.latitude - span.latitudeDelta / 2 + span.latitudeDelta * covered
        let north = region.center.latitude + span.latitudeDelta / 2 - span.latitudeDelta * callout
        let west = region.center.longitude - span.longitudeDelta / 2
        let east = region.center.longitude + span.longitudeDelta / 2
        return (south...north).contains(coordinate.latitude) && (west...east).contains(coordinate.longitude)
    }

    private static func bounds(of coordinates: [CLLocationCoordinate2D], padding: Double) -> MKMapRect {
        let rects = coordinates.map { MKMapRect(origin: MKMapPoint($0), size: MKMapSize(width: 0, height: 0)) }
        let bounds = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
        // A single point has no extent to pad; give it a few hundred metres either way.
        let width = max(bounds.width, 2_000)
        let height = max(bounds.height, 2_000)
        return MKMapRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
            .insetBy(dx: -width * padding, dy: -height * padding)
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
