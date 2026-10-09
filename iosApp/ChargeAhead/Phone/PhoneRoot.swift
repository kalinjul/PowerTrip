import MapKit
import SwiftUI
import Shared

/// Holds a set of shared ViewModels for as long as the SwiftUI view that owns it.
final class ViewModelOwner: ObservableObject {
    let viewModels: PhoneViewModels

    init(feature: ChargeStopsFeature) {
        viewModels = PhoneViewModels(feature: feature)
    }

    deinit {
        viewModels.clear()
    }
}

/// The phone's location and charge state, and the map screen's ViewModels over it.
final class PhoneSession: ObservableObject {
    let feature: ChargeStopsFeature
    let viewModels: PhoneViewModels

    init() {
        feature = SharedEntry.newFeature()
        viewModels = PhoneViewModels(feature: feature)
    }

    deinit {
        viewModels.clear()
        feature.close()
    }
}

/// A sheet over the map or over the trip sheet; only one is up at a time.
enum PhoneOverlay: Identifiable, Equatable {
    case settings(SettingsPage?)
    case chargeNow
    case stopDetail
    case startLevel
    case arrivalLevel
    case replanLevel

    var id: String { "\(self)" }
}

enum PhoneAlert: Identifiable {
    case vehicleMissing
    case message(String)

    var id: String { "\(self)" }
}

enum PhonePage: Hashable {
    case activeRoute
}

/// The phone app: the map screen, the trip sheet over it, the active route page and the sheets around them.
struct PhoneRoot: View {
    @StateObject private var session = PhoneSession()
    @StateObject private var location = LocationAuthorization()
    @State private var query = ""
    @State private var path: [PhonePage] = []
    @State private var overlay: PhoneOverlay?
    @State private var alert: PhoneAlert?
    @State private var command: CameraCommand?
    @State private var tripDetent: PresentationDetent = TripSheetDetents.peek
    @Namespace private var mapScope

    var body: some View {
        let viewModels = session.viewModels
        let home = viewModels.home()
        let trip = viewModels.trip()
        let search = viewModels.search()
        let activeRoute = viewModels.activeRoute()
        let phoneApp = viewModels.phoneApp()
        Observing(home.uiState) { homeState in
            Observing(trip.uiState) { tripState in
                Observing(search.uiState) { searchState in
                    Observing(activeRoute.uiState) { committed in
                        Observing(phoneApp.uiState) { app in
                            let context = Context(home: homeState, trip: tripState, committed: committed, layout: app.tripLayout)
                            NavigationStack(path: $path) {
                                homeScreen(context, search: searchState)
                                    .toolbar(.hidden, for: .navigationBar)
                                    .navigationDestination(for: PhonePage.self) { _ in
                                        ActiveRouteView(
                                            state: committed,
                                            now: Date(),
                                            actions: activeRouteActions(activeRoute, committed: committed),
                                            onEnd: { activeRoute.endTrip() }
                                        )
                                    }
                            }
                            .modifier(PhoneOverlays(
                                enabled: !context.tripSheetShown(onPage: !path.isEmpty),
                                overlay: overlayBinding(context),
                                alert: $alert,
                                sheet: { overlaySheet($0, context) },
                                onAddCar: { overlay = .settings(.garage) }
                            ))
                            .sheet(isPresented: .constant(context.tripSheetShown(onPage: !path.isEmpty))) {
                                tripSheet(context)
                            }
                        }
                    }
                }
            }
        }
        .tint(Brand.primary)
        .mapScope(mapScope)
        .onChange(of: location.access, initial: true) { _, access in
            switch access {
            case .granted: home.onLocationPermissionGranted()
            case .unknown: location.request()
            case .denied: break
            }
        }
        .task { await collectTripEvents(trip) }
        .task { await collectActiveRouteEvents(activeRoute) }
    }

    // MARK: Map screen

    private func homeScreen(_ context: Context, search: SearchUiState) -> some View {
        let viewModels = session.viewModels
        let home = viewModels.home()
        let trip = viewModels.trip()
        let searchModel = viewModels.search()
        let sheet = context.sheet
        let plan = (sheet as? TripUiStatePlanned)?.plan
        return HomeContent(
            home: context.home,
            search: search,
            query: $query,
            destination: sheet?.destination,
            plan: plan,
            planning: context.trip is TripUiStatePlanning,
            activeRouteEnabled: context.committed.trip != nil,
            locationAccess: location.access,
            actions: HomeActions(
                settings: { overlay = .settings(nil) },
                locate: {
                    if location.access == .granted { home.onLocateRequested() } else { location.request() }
                },
                recenter: { moveCamera(to: context.home.position.map { .position($0, meters: 5_000) }) },
                chargeNow: { overlay = .chargeNow },
                activeRoute: { path = [.activeRoute] },
                modeDismissed: { home.onModeDismissed() },
                searchOpened: { searchModel.onOpened(prefill: nil) },
                searchClosed: {
                    query = ""
                    searchModel.onClosed()
                },
                picked: { row in
                    query = ""
                    searchModel.onClosed()
                    trip.plan(destination: row.destination, socPercent: nil)
                },
                tripCleared: { trip.clear() },
                destinationTapped: { moveCamera(to: plan != nil ? .route : sheet.map { .position($0.destination.position, meters: 20_000) }) },
                permissionRequested: { location.request() },
                zoomHintTapped: { moveCamera(to: .pillZoom) }
            )
        ) {
            ChargerMapView(
                position: context.home.position,
                chargers: context.home.chargers,
                plan: plan,
                command: command,
                bottomInset: sheet != nil ? UIScreen.main.bounds.height * TripSheetDetents.peekFraction : 0,
                onViewportChanged: { home.onViewportChanged(viewport: $0) },
                onChargerTapped: { home.onChargerSelected(charger: $0) },
                onStopTapped: { home.onSiteSelected(site: $0.site) }
            )
        } compass: {
            MapCompass(scope: mapScope)
                .mapControlVisibility(.automatic)
        }
        .onChange(of: query) { _, text in
            if text != search.query { searchModel.onQueryChanged(query: text) }
        }
    }

    private func moveCamera(to target: CameraCommand.Target?) {
        guard let target else { return }
        command = CameraCommand(id: (command?.id ?? 0) + 1, target: target)
    }

    // MARK: Trip sheet

    private func tripSheet(_ context: Context) -> some View {
        let trip = session.viewModels.trip()
        let phoneApp = session.viewModels.phoneApp()
        let home = session.viewModels.home()
        let expandable = context.layout == .list && context.trip is TripUiStatePlanned
        return Group {
            if let sheet = context.sheet {
                TripSheetContent(
                    trip: sheet,
                    layout: context.layout,
                    now: Date(),
                    actions: TripActions(
                        replan: { trip.onReplanRequested() },
                        layoutToggled: {
                            tripDetent = TripSheetDetents.peek
                            phoneApp.onTripLayoutChanged(layout: context.layout == .tiles ? .list : .tiles)
                        },
                        selectingToggled: { trip.onSectionSelectingToggled() },
                        pointPicked: { trip.onSectionPointPicked(index: Int32($0)) },
                        stopOpened: { home.onSiteSelected(site: $0.site) },
                        sentToMaps: {
                            guard let planned = sheet as? TripUiStatePlanned else { return }
                            openInMaps(planned.mapsUrl) { opened in
                                if opened { trip.commit() } else { alert = .message(localized("phone_detail_no_navigation")) }
                            }
                            trip.onSectionSent()
                        },
                        startSocEdit: { trip.onStartSocEditRequested() },
                        arrivalSocEdit: { trip.onArrivalSocEditRequested() }
                    )
                )
            }
        }
        .presentationDetents(expandable ? [TripSheetDetents.peek, TripSheetDetents.full] : [TripSheetDetents.peek], selection: $tripDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: TripSheetDetents.peek))
        .presentationDragIndicator(expandable ? .visible : .hidden)
        .interactiveDismissDisabled()
        .modifier(PhoneOverlays(
            enabled: true,
            overlay: overlayBinding(context),
            alert: $alert,
            sheet: { overlaySheet($0, context) },
            onAddCar: { overlay = .settings(.garage) }
        ))
    }

    // MARK: Overlays

    /// What is up: a selected charger or an open level editor comes from the ViewModels, the rest is navigation.
    private func overlayBinding(_ context: Context) -> Binding<PhoneOverlay?> {
        let viewModels = session.viewModels
        let shown: PhoneOverlay? = {
            if context.home.selectedStop != nil && overlay != .chargeNow { return .stopDetail }
            if context.sheet?.socInput != nil { return .startLevel }
            if context.sheet?.arrivalSocInput != nil { return .arrivalLevel }
            if context.committed.socInput != nil { return .replanLevel }
            return overlay
        }()
        return Binding(
            get: { shown },
            set: { value in
                guard value == nil else { overlay = value; return }
                switch shown {
                case .stopDetail: viewModels.home().onSelectedStopDismissed()
                case .startLevel: viewModels.trip().onStartSocEditDismissed()
                case .arrivalLevel: viewModels.trip().onArrivalSocEditDismissed()
                case .replanLevel: viewModels.activeRoute().onSocEditDismissed()
                default: overlay = nil
                }
            }
        )
    }

    @ViewBuilder
    private func overlaySheet(_ shown: PhoneOverlay, _ context: Context) -> some View {
        let viewModels = session.viewModels
        let trip = viewModels.trip()
        switch shown {
        case .settings(let page):
            SettingsView(feature: session.feature, startPage: page)
        case .chargeNow:
            ChargeNowView(
                feature: session.feature,
                onNavigate: { candidate in openNavigation(to: candidate.site.position) },
                onOpen: { candidate in viewModels.home().onSiteSelected(site: candidate.site) }
            )
            .sheet(item: Binding(
                get: { context.home.selectedStop.map { SelectedStop(stop: $0) } },
                set: { if $0 == nil { viewModels.home().onSelectedStopDismissed() } }
            )) { selected in
                stopDetail(selected.stop, context)
            }
            .presentationDetents([.medium, .large])
        case .stopDetail:
            if let stop = context.home.selectedStop {
                stopDetail(stop, context)
            }
        case .startLevel:
            LevelSheet(
                title: localized("soc_dialog_title"),
                hint: context.sheet?.socAskedForReplan == true ? localized("soc_dialog_car_silent") : nil,
                percent: context.sheet?.socInput.flatMap { Int($0) },
                range: TripPlanKt.SOC_RANGE,
                applyLabel: localized("trip_soc_confirm"),
                onChange: { trip.onStartSocInputChanged(input: String($0)) },
                onApply: { trip.onStartSocConfirmed() },
                onCancel: { trip.onStartSocEditDismissed() }
            )
        case .arrivalLevel:
            LevelSheet(
                title: localized("garage_arrival_title"),
                hint: localized("garage_arrival_sheet_hint"),
                percent: context.sheet?.arrivalSocInput.flatMap { Int($0) },
                range: GarageViewModelKt.ARRIVAL_SOC_RANGE,
                applyLabel: localized("trip_soc_confirm"),
                onChange: { trip.onArrivalSocInputChanged(input: String($0)) },
                onApply: { trip.onArrivalSocConfirmed() },
                onCancel: { trip.onArrivalSocEditDismissed() }
            )
        case .replanLevel:
            let activeRoute = viewModels.activeRoute()
            LevelSheet(
                title: localized("soc_dialog_title"),
                hint: localized("soc_dialog_car_silent"),
                percent: context.committed.socInput.flatMap { Int($0) },
                range: TripPlanKt.SOC_RANGE,
                applyLabel: localized("trip_soc_confirm"),
                onChange: { activeRoute.onSocInputChanged(input: String($0)) },
                onApply: { activeRoute.onSocConfirmed() },
                onCancel: { activeRoute.onSocEditDismissed() }
            )
        }
    }

    private func stopDetail(_ stop: ChargeStop, _ context: Context) -> some View {
        StopDetailSheet(
            stop: stop,
            live: context.home.selectedStopLive,
            tripLine: tripLine(for: stop, context),
            onNavigate: {
                session.viewModels.home().onSelectedStopDismissed()
                openNavigation(to: stop.site.position)
            }
        )
        .presentationDetents([.medium, .large])
    }

    /// Arrival and departure, when the charger is a stop of the plan on screen.
    private func tripLine(for selected: ChargeStop, _ context: Context) -> String? {
        let plan = path.isEmpty ? (context.sheet as? TripUiStatePlanned)?.plan : context.committed.trip?.plan
        guard let stop = plan?.stops.first(where: { $0.site.id == selected.site.id }) else { return nil }
        let now = Date()
        return localized(
            "trip_stop_times",
            etaText(stop.arrivalMinutesFromStart, now: now),
            etaText(stop.arrivalMinutesFromStart + stop.chargeMinutes, now: now)
        )
    }

    // MARK: Active route

    private func activeRouteActions(_ activeRoute: ActiveRouteViewModel, committed: ActiveRouteUiState) -> TripActions {
        TripActions(
            replan: { activeRoute.onReplanRequested() },
            selectingToggled: { activeRoute.onSectionSelectingToggled() },
            pointPicked: { activeRoute.onSectionPointPicked(index: Int32($0)) },
            stopOpened: { session.viewModels.home().onSiteSelected(site: $0.site) },
            sentToMaps: {
                if let url = committed.mapsUrl {
                    openInMaps(url) { opened in
                        if !opened { alert = .message(localized("phone_detail_no_navigation")) }
                    }
                }
                activeRoute.onSectionSent()
            }
        )
    }

    // MARK: Events

    private func collectTripEvents(_ trip: TripViewModel) async {
        for await event in trip.event {
            guard let event else { continue }
            switch onEnum(of: event) {
            case .sheetReady:
                query = ""
                session.viewModels.search().onClosed()
                tripDetent = TripSheetDetents.peek
            case .vehicleMissing:
                alert = .vehicleMissing
            case .noConnection:
                alert = .message(localized("plan_failed_no_connection"))
            case .tripCommitted:
                path = [.activeRoute]
            }
            trip.onEventHandled()
        }
    }

    private func collectActiveRouteEvents(_ activeRoute: ActiveRouteViewModel) async {
        for await event in activeRoute.event {
            guard let event else { continue }
            switch onEnum(of: event) {
            case .replanned:
                break
            case .replanFailed(let failed):
                alert = .message(ChargeStopFormatter.shared.unreachableMessage(why: failed.why))
            case .vehicleMissing:
                alert = .vehicleMissing
            case .ended:
                path = []
            }
            activeRoute.onEventHandled()
        }
    }

    private func openNavigation(to position: LatLon) {
        openInMaps(MapsHandoff.shared.navigateUrl(target: position)) { opened in
            if !opened { alert = .message(localized("phone_detail_no_navigation")) }
        }
    }

    /// The states the screens are drawn from, read together.
    struct Context {
        let home: HomeUiState
        let trip: TripUiState
        let committed: ActiveRouteUiState
        let layout: TripListLayout

        var sheet: TripUiStateSheet? { trip as? TripUiStateSheet }

        func tripSheetShown(onPage: Bool) -> Bool { sheet != nil && !onPage }
    }
}

private struct SelectedStop: Identifiable {
    let stop: ChargeStop
    var id: String { stop.site.id }
}

enum TripSheetDetents {
    static let peekFraction: CGFloat = 1 / 3
    static let peek = PresentationDetent.fraction(peekFraction)
    static let full = PresentationDetent.fraction(0.85)
}

/// The overlay sheet and the alerts, attached to whichever view presents on top right now.
private struct PhoneOverlays<Sheet: View>: ViewModifier {
    let enabled: Bool
    let overlay: Binding<PhoneOverlay?>
    let alert: Binding<PhoneAlert?>
    @ViewBuilder let sheet: (PhoneOverlay) -> Sheet
    let onAddCar: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: enabled ? overlay : .constant(nil)) { shown in
                sheet(shown)
            }
            .alert(
                alertTitle,
                isPresented: Binding(
                    get: { enabled && alert.wrappedValue != nil },
                    set: { if !$0 { alert.wrappedValue = nil } }
                ),
                presenting: alert.wrappedValue
            ) { shown in
                if case .vehicleMissing = shown {
                    Button(localized("plan_vehicle_missing_action"), action: onAddCar)
                    Button(localized("soc_dialog_cancel"), role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            }
    }

    private var alertTitle: String {
        switch alert.wrappedValue {
        case .vehicleMissing: return localized("plan_vehicle_missing")
        case .message(let text): return text
        case nil: return ""
        }
    }
}

/// Hands a link to whatever app opens it; `false` when none does.
func openInMaps(_ url: String, completion: @escaping (Bool) -> Void = { _ in }) {
    guard let parsed = URL(string: url) else {
        completion(false)
        return
    }
    UIApplication.shared.open(parsed, options: [:], completionHandler: completion)
}
