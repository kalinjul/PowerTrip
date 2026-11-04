import MapKit
import SwiftUI
import Shared

/// Holds a set of shared ViewModels for as long as the SwiftUI view that owns it.
final class ViewModelOwner: ObservableObject {
    let viewModels: PhoneViewModels
    private let ownedFeature: ChargeStopsFeature?

    /// `owningFeature`: the feature is this owner's too, closed after its ViewModels are cleared.
    init(feature: ChargeStopsFeature, owningFeature: Bool = false) {
        viewModels = PhoneViewModels(feature: feature)
        ownedFeature = owningFeature ? feature : nil
    }

    deinit {
        viewModels.clear()
        ownedFeature?.close()
    }
}

/// The phone's location and charge state, and the map screen's ViewModels over it, resolved once.
final class PhoneSession: ObservableObject {
    let feature: ChargeStopsFeature
    let owner: ViewModelOwner
    let home: HomeViewModel
    let trip: TripViewModel
    let search: SearchViewModel
    let activeRoute: ActiveRouteViewModel
    let chargeNow: ChargeNowViewModel
    let settings: DrawerViewModel
    let phoneApp: PhoneAppViewModel

    init() {
        feature = SharedEntry.newFeature()
        owner = ViewModelOwner(feature: feature, owningFeature: true)
        let viewModels = owner.viewModels
        home = viewModels.home()
        trip = viewModels.trip()
        search = viewModels.search()
        activeRoute = viewModels.activeRoute()
        chargeNow = viewModels.chargeNow()
        settings = viewModels.drawer()
        phoneApp = viewModels.phoneApp()
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

    /// What is up: an open level editor or a selected charger come from the ViewModels and win over navigation.
    /// Over "charge now" the selected charger opens inside that sheet instead.
    static func shown(
        navigation: PhoneOverlay?,
        stopSelected: Bool,
        startLevelOpen: Bool,
        arrivalLevelOpen: Bool,
        replanLevelOpen: Bool
    ) -> PhoneOverlay? {
        if startLevelOpen { return .startLevel }
        if arrivalLevelOpen { return .arrivalLevel }
        if replanLevelOpen { return .replanLevel }
        if stopSelected && navigation != .chargeNow { return .stopDetail }
        return navigation
    }
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
    @StateObject private var session: PhoneSession
    @StateObject private var location: LocationAuthorization
    @State private var query = ""
    @State private var path: [PhonePage] = []
    @State private var overlay: PhoneOverlay?
    @State private var alert: PhoneAlert?
    @State private var command: CameraCommand?
    @State private var tripDetent: PresentationDetent = TripSheetDetents.peek
    @State private var navigationApp: NavigationApp = .appleMaps

    init() {
        let session = PhoneSession()
        _session = StateObject(wrappedValue: session)
        _location = StateObject(wrappedValue: LocationAuthorization(phoneApp: session.phoneApp, onSettled: { session.home.onLocateRequested() }))
    }

    var body: some View {
        Observing(session.trip.uiState, session.activeRoute.uiState, session.phoneApp.uiState) { trip, committed, app in
            let onPage = !path.isEmpty
            let sheetShown = (trip as? TripUiStateSheet) != nil && !onPage
            NavigationStack(path: $path) {
                HomeScreen(
                    session: session,
                    trip: trip,
                    committed: committed,
                    hasLocationPermission: app.hasLocationPermission?.boolValue,
                    query: $query,
                    command: $command,
                    onSettings: { overlay = .settings(nil) },
                    onChargeNow: {
                        session.chargeNow.onSheetOpened()
                        overlay = .chargeNow
                    },
                    onActiveRoute: { path = [.activeRoute] },
                    // The search panel would open under the sheet.
                    onSearchOpened: { if overlay == .chargeNow { overlay = nil } }
                )
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: PhonePage.self) { _ in
                    ActiveRouteView(
                        state: committed,
                        now: Date(),
                        actions: activeRouteActions(committed),
                        onEnd: { session.activeRoute.endTrip() }
                    )
                }
            }
            .modifier(PhoneOverlays(
                session: session,
                enabled: !sheetShown,
                trip: trip,
                committed: committed,
                onPage: onPage,
            handoffApp: handoffApp,
                navigation: $overlay,
                alert: $alert
            ))
            .sheet(isPresented: .constant(sheetShown)) {
                tripSheet(trip, layout: app.tripLayout, committed: committed)
            }
            .onChange(of: app.hasLocationPermission?.boolValue, initial: true) { _, granted in
                if granted == true { session.home.onLocationPermissionGranted() }
            }
        }
        .tint(Brand.primary)
        .task { await collectTripEvents() }
        .task {
            for await settings in session.settings.uiState {
                navigationApp = settings.navigationApp
            }
        }
        .task { await collectActiveRouteEvents() }
        .task {
            for await event in session.phoneApp.event {
                if let event { location.handle(event) }
            }
        }
    }

    // MARK: Trip sheet

    private func tripSheet(_ trip: TripUiState, layout: TripListLayout, committed: ActiveRouteUiState) -> some View {
        let model = session.trip
        let expandable = layout == .list && trip is TripUiStatePlanned
        return Group {
            if let sheet = trip as? TripUiStateSheet {
                TripSheetContent(
                    trip: sheet,
                    layout: layout,
                    now: Date(),
                    actions: TripActions(
                        replan: { model.onReplanRequested() },
                        layoutToggled: {
                            tripDetent = TripSheetDetents.peek
                            session.phoneApp.onTripLayoutChanged(layout: layout == .tiles ? .list : .tiles)
                        },
                        selectingToggled: { model.onSectionSelectingToggled() },
                        pointPicked: { model.onSectionPointPicked(index: Int32($0)) },
                        stopOpened: { session.home.onSiteSelected(site: $0.site) },
                        sentToMaps: {
                            guard let planned = sheet as? TripUiStatePlanned else { return }
                            openInMaps(planned.mapsUrl(app: handoffApp)) { opened in
                                if opened { model.commit() } else { alert = .message(localized("phone_detail_no_navigation")) }
                            }
                            model.onSectionSent()
                        },
                        startSocEdit: { model.onStartSocEditRequested() },
                        arrivalSocEdit: { model.onArrivalSocEditRequested() }
                    )
                )
            }
        }
        .presentationDetents(expandable ? [TripSheetDetents.peek, TripSheetDetents.full] : [TripSheetDetents.peek], selection: $tripDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: TripSheetDetents.peek))
        .presentationDragIndicator(expandable ? .visible : .hidden)
        .interactiveDismissDisabled()
        .modifier(PhoneOverlays(
            session: session,
            enabled: true,
            trip: trip,
            committed: committed,
            onPage: false,
            handoffApp: handoffApp,
            navigation: $overlay,
            alert: $alert
        ))
    }

    // MARK: Active route

    private func activeRouteActions(_ committed: ActiveRouteUiState) -> TripActions {
        let activeRoute = session.activeRoute
        return TripActions(
            replan: { activeRoute.onReplanRequested() },
            selectingToggled: { activeRoute.onSectionSelectingToggled() },
            pointPicked: { activeRoute.onSectionPointPicked(index: Int32($0)) },
            stopOpened: { session.home.onSiteSelected(site: $0.site) },
            sentToMaps: {
                if let url = committed.mapsUrl(app: handoffApp) {
                    openInMaps(url) { opened in
                        if !opened { alert = .message(localized("phone_detail_no_navigation")) }
                    }
                }
                activeRoute.onSectionSent()
            }
        )
    }

    private var handoffApp: NavigationApp {
        navigationApp.available(googleMapsInstalled: googleMapsInstalled())
    }

    // MARK: Events

    private func collectTripEvents() async {
        for await event in session.trip.event {
            guard let event else { continue }
            switch onEnum(of: event) {
            case .sheetReady:
                query = ""
                session.search.onClosed()
                tripDetent = TripSheetDetents.peek
            case .vehicleMissing:
                alert = .vehicleMissing
            case .noConnection:
                alert = .message(localized("plan_failed_no_connection"))
            case .tripCommitted:
                path = [.activeRoute]
            }
            session.trip.onEventHandled()
        }
    }

    private func collectActiveRouteEvents() async {
        for await event in session.activeRoute.event {
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
            session.activeRoute.onEventHandled()
        }
    }
}

/// The map screen with its own observation of the map and search state, so a new fix redraws only this.
private struct HomeScreen: View {
    let session: PhoneSession
    let trip: TripUiState
    let committed: ActiveRouteUiState
    let hasLocationPermission: Bool?
    @Binding var query: String
    @Binding var command: CameraCommand?
    let onSettings: () -> Void
    let onChargeNow: () -> Void
    let onActiveRoute: () -> Void
    let onSearchOpened: () -> Void

    @Namespace private var mapScope

    var body: some View {
        let home = session.home
        let search = session.search
        let sheet = trip as? TripUiStateSheet
        let plan = (sheet as? TripUiStatePlanned)?.plan
        GeometryReader { geometry in
            Observing(home.uiState, search.uiState, session.chargeNow.uiState) { homeState, searchState, chargeNowState in
                let chargeNow = chargeNowState as? ChargeNowSheetUiStateOpen
                let height = geometry.size.height + geometry.safeAreaInsets.bottom
                HomeContent(
                    home: homeState,
                    search: searchState,
                    query: $query,
                    destination: sheet?.destination,
                    plan: plan,
                    planning: trip is TripUiStatePlanning,
                    activeRouteEnabled: committed.trip != nil,
                    hasLocationPermission: hasLocationPermission,
                    actions: HomeActions(
                        settings: onSettings,
                        locate: { session.phoneApp.onLocateRequested() },
                        recenter: { moveCamera(to: homeState.position.map { .position($0, meters: 5_000) }) },
                        chargeNow: onChargeNow,
                        activeRoute: onActiveRoute,
                        modeDismissed: { home.onModeDismissed() },
                        searchOpened: {
                            onSearchOpened()
                            search.onOpened(prefill: nil)
                        },
                        searchClosed: {
                            query = ""
                            search.onClosed()
                        },
                        picked: { row in
                            query = ""
                            search.onClosed()
                            session.trip.plan(destination: row.destination, socPercent: nil)
                        },
                        tripCleared: { session.trip.clear() },
                        destinationTapped: { moveCamera(to: plan != nil ? .route : sheet.map { .position($0.destination.position, meters: 20_000) }) },
                        permissionRequested: { session.phoneApp.onLocationPermissionRequested() },
                        zoomHintTapped: { moveCamera(to: .pillZoom) }
                    )
                ) {
                    ChargerMapView(
                        position: homeState.position,
                        chargers: homeState.chargers,
                        plan: plan,
                        chargeNow: chargeNow,
                        command: command,
                        bottomInset: sheet != nil ? height * TripSheetDetents.peekFraction : (chargeNow != nil ? height * ChargeNowSheetDetents.mediumFraction : 0),
                        onViewportChanged: { home.onViewportChanged(viewport: $0) },
                        onChargerTapped: { home.onChargerSelected(charger: $0) },
                        onStopTapped: { home.onSiteSelected(site: $0.site) },
                        onCandidateTapped: { session.chargeNow.onCandidateSelected(siteId: $0.site.id) },
                        onCandidateOpened: { candidate in
                            session.chargeNow.onCandidateSelected(siteId: candidate.site.id)
                            home.onSiteSelected(site: candidate.site)
                        }
                    )
                } compass: {
                    MapCompass(scope: mapScope)
                        .mapControlVisibility(.automatic)
                }
                .onChange(of: query) { _, text in
                    if text != searchState.query { search.onQueryChanged(query: text) }
                }
            }
        }
        .mapScope(mapScope)
    }

    private func moveCamera(to target: CameraCommand.Target?) {
        guard let target else { return }
        command = CameraCommand(id: (command?.id ?? 0) + 1, target: target)
    }
}

enum TripSheetDetents {
    static let peekFraction: CGFloat = 1 / 3
    static let peek = PresentationDetent.fraction(peekFraction)
    static let full = PresentationDetent.fraction(0.85)
}

/// "Charge now" sits at half height over the live map, like the trip sheet at its peek.
enum ChargeNowSheetDetents {
    static let mediumFraction: CGFloat = 1 / 2
    static let medium = PresentationDetent.fraction(mediumFraction)
}

/// The overlay sheet and the alerts, attached to whichever view presents on top right now.
/// It observes the map state itself, so a selected charger doesn't redraw what it is attached to.
private struct PhoneOverlays: ViewModifier {
    let session: PhoneSession
    let enabled: Bool
    let trip: TripUiState
    let committed: ActiveRouteUiState
    let onPage: Bool
    let handoffApp: NavigationApp
    @Binding var navigation: PhoneOverlay?
    @Binding var alert: PhoneAlert?

    func body(content: Content) -> some View {
        Observing(session.home.uiState) { home in
            content
                .sheet(item: enabled ? binding(home) : .constant(nil)) { shown in
                    sheet(shown, home)
                }
                .alert(
                    alertTitle,
                    isPresented: Binding(
                        get: { enabled && alert != nil },
                        set: { if !$0 { alert = nil } }
                    ),
                    presenting: alert
                ) { shown in
                    if case .vehicleMissing = shown {
                        Button(localized("plan_vehicle_missing_action")) { navigation = .settings(.garage) }
                        Button(localized("soc_dialog_cancel"), role: .cancel) {}
                    } else {
                        Button(localized("ios_ok"), role: .cancel) {}
                    }
                }
        }
    }

    private var sheetState: TripUiStateSheet? { trip as? TripUiStateSheet }

    private func binding(_ home: HomeUiState) -> Binding<PhoneOverlay?> {
        let shown = PhoneOverlay.shown(
            navigation: navigation,
            stopSelected: home.selectedStop != nil,
            startLevelOpen: sheetState?.socInput != nil,
            arrivalLevelOpen: sheetState?.arrivalSocInput != nil,
            replanLevelOpen: committed.socInput != nil
        )
        return Binding(
            get: { shown },
            set: { value in
                guard value == nil else { navigation = value; return }
                switch shown {
                case .stopDetail: session.home.onSelectedStopDismissed()
                case .startLevel: session.trip.onStartSocEditDismissed()
                case .arrivalLevel: session.trip.onArrivalSocEditDismissed()
                case .replanLevel: session.activeRoute.onSocEditDismissed()
                default: navigation = nil
                }
            }
        )
    }

    @ViewBuilder
    private func sheet(_ shown: PhoneOverlay, _ home: HomeUiState) -> some View {
        let trip = session.trip
        switch shown {
        case .settings(let page):
            SettingsView(feature: session.feature, startPage: page)
        case .chargeNow:
            ChargeNowView(
                model: session.chargeNow,
                onNavigate: { openNavigation(to: $0.site.position) },
                onOpen: { candidate in
                    session.chargeNow.onCandidateSelected(siteId: candidate.site.id)
                    session.home.onSiteSelected(site: candidate.site)
                }
            )
            .sheet(item: Binding(
                get: { home.selectedStop.map { SelectedStop(stop: $0) } },
                set: { if $0 == nil { session.home.onSelectedStopDismissed() } }
            )) { selected in
                stopDetail(selected.stop, home)
            }
            .presentationDetents([ChargeNowSheetDetents.medium, .large])
            .presentationBackgroundInteraction(.enabled(upThrough: ChargeNowSheetDetents.medium))
        case .stopDetail:
            if let stop = home.selectedStop {
                stopDetail(stop, home)
            }
        case .startLevel:
            LevelSheet(
                title: localized("soc_dialog_title"),
                hint: sheetState?.socAskedForReplan == true ? localized("soc_dialog_car_silent") : nil,
                percent: sheetState?.socInput.flatMap { Int($0) },
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
                percent: sheetState?.arrivalSocInput.flatMap { Int($0) },
                range: GarageViewModelKt.ARRIVAL_SOC_RANGE,
                applyLabel: localized("trip_soc_confirm"),
                onChange: { trip.onArrivalSocInputChanged(input: String($0)) },
                onApply: { trip.onArrivalSocConfirmed() },
                onCancel: { trip.onArrivalSocEditDismissed() }
            )
        case .replanLevel:
            let activeRoute = session.activeRoute
            LevelSheet(
                title: localized("soc_dialog_title"),
                hint: localized("soc_dialog_car_silent"),
                percent: committed.socInput.flatMap { Int($0) },
                range: TripPlanKt.SOC_RANGE,
                applyLabel: localized("trip_soc_confirm"),
                onChange: { activeRoute.onSocInputChanged(input: String($0)) },
                onApply: { activeRoute.onSocConfirmed() },
                onCancel: { activeRoute.onSocEditDismissed() }
            )
        }
    }

    private func stopDetail(_ stop: ChargeStop, _ home: HomeUiState) -> some View {
        StopDetailSheet(
            stop: stop,
            live: home.selectedStopLive,
            tripLine: tripLine(for: stop),
            onNavigate: {
                session.home.onSelectedStopDismissed()
                openNavigation(to: stop.site.position)
            }
        )
        .presentationDetents([.medium, .large])
    }

    /// Arrival and departure, when the charger is a stop of the plan on screen.
    private func tripLine(for selected: ChargeStop) -> String? {
        let plan = onPage ? committed.trip?.plan : (sheetState as? TripUiStatePlanned)?.plan
        guard let stop = plan?.stops.first(where: { $0.site.id == selected.site.id }) else { return nil }
        let now = Date()
        return localized(
            "trip_stop_times",
            etaText(stop.arrivalMinutesFromStart, now: now),
            etaText(stop.arrivalMinutesFromStart + stop.chargeMinutes, now: now)
        )
    }

    private func openNavigation(to position: LatLon) {
        openInMaps(MapsHandoff.shared.navigateUrl(target: position, app: handoffApp)) { opened in
            if !opened { alert = .message(localized("phone_detail_no_navigation")) }
        }
    }

    private var alertTitle: String {
        switch alert {
        case .vehicleMissing: return localized("plan_vehicle_missing")
        case .message(let text): return text
        case nil: return ""
        }
    }
}

private struct SelectedStop: Identifiable {
    let stop: ChargeStop
    var id: String { stop.site.id }
}

/// Hands a link to whatever app opens it; `false` when none does.
func openInMaps(_ url: String, completion: @escaping (Bool) -> Void = { _ in }) {
    guard let parsed = URL(string: url) else {
        completion(false)
        return
    }
    UIApplication.shared.open(parsed, options: [:], completionHandler: completion)
}

/// Google Maps can take a hand-off only while it is installed; asking needs `comgooglemaps` in LSApplicationQueriesSchemes.
func googleMapsInstalled() -> Bool {
    guard let scheme = URL(string: "comgooglemaps://") else { return false }
    return UIApplication.shared.canOpenURL(scheme)
}
