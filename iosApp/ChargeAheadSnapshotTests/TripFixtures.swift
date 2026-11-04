import Foundation
import Shared
@testable import ChargeAhead

/// Hamburg → München with three stops, the same trip as Android's goldens.
extension Fixtures {

    /// The clock every golden reads; wall time must never leak into a reference image.
    static let now: Date = Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!

    static let hamburg = LatLon(lat: 53.5511, lon: 9.9937)
    static let munich = LatLon(lat: 48.1351, lon: 11.5820)

    static func addressedSite(_ id: String, _ name: String, _ operatorName: String, kw: Double, lat: Double, lon: Double, street: String, town: String) -> ChargeSite {
        ChargeSite(
            id: id,
            name: name,
            operator: operatorName,
            operatorId: nil,
            position: LatLon(lat: lat, lon: lon),
            connectors: [Connector(type: .ccs2, maxPowerKw: kw, count: 4)],
            address: Address(street: street, postalCode: nil, town: town),
            sources: [],
            liveStatusId: nil,
            networkKey: nil,
            adHocTariffs: []
        )
    }

    static let ionity = addressedSite("ocm:1", "Ionity Hildesheimer Börde", "Ionity", kw: 350, lat: 52.10, lon: 9.95, street: "Rasthof Hildesheimer Börde West", town: "31185 Söhlde")
    static let enbw = addressedSite("ocm:2", "EnBW Ladepark Kassel", "EnBW", kw: 300, lat: 51.30, lon: 9.45, street: "Am Rasthof 3", town: "34266 Niestetal")
    static let aral = addressedSite("ocm:3", "Aral pulse Nürnberg-Feucht", "Aral pulse", kw: 300, lat: 49.38, lon: 11.20, street: "Autobahnraststätte Nürnberg-Feucht Ost", town: "90537 Feucht")

    static let munichDestination = Destination(name: "München", position: munich, address: "Marienplatz 1, 80331 München")

    private static func stop(_ site: ChargeSite, km: Double, arrival: Double, departure: Double, kwh: Double, minutes: Double, drive: Double) -> PlannedStop {
        PlannedStop(
            site: site,
            kmFromStart: km,
            arrivalSocPercent: arrival,
            departureSocPercent: departure,
            chargeKwh: kwh,
            chargeMinutes: minutes,
            etaMinutesFromStart: drive + minutes + 5,
            maxPowerKw: site.connectors.first?.maxPowerKw ?? 0,
            stopMinutes: 5,
            savesMinutes: nil,
            siteMissing: false
        )
    }

    static let plan = plan(route: Route(points: [hamburg, munich], distanceKm: 776, durationMinutes: 452, segments: [], weatherAttribution: nil))

    /// The same trip with a forecast at both ends and the notice that must stand next to it.
    static let planWithForecast = plan(route: Route(
        points: [hamburg, munich],
        distanceKm: 776,
        durationMinutes: 452,
        segments: [
            RouteSegment(fromKm: 0, distanceKm: 388, durationMinutes: 226, ascentM: 120, descentM: 80, temperatureC: 12),
            RouteSegment(fromKm: 388, distanceKm: 388, durationMinutes: 226, ascentM: 310, descentM: 140, temperatureC: 4),
        ],
        weatherAttribution: "Wetterdaten: Deutscher Wetterdienst"
    ))

    private static func plan(route: Route) -> TripPlan {
        TripPlan(
            route: route,
            destination: munichDestination,
            stops: [
                stop(ionity, km: 168, arrival: 24, departure: 78, kwh: 41, minutes: 22, drive: 98),
                stop(enbw, km: 398, arrival: 18, departure: 80, kwh: 47, minutes: 27, drive: 260),
                stop(aral, km: 612, arrival: 21, departure: 65, kwh: 33, minutes: 18, drive: 403),
            ],
            driveMinutes: 452,
            chargeMinutes: 67,
            arrivalSocPercent: 15,
            stopMinutes: 15,
            startAddress: "Feldstraße 66, Hamburg"
        )
    }

    static let noSelection = SectionSelection(selecting: false, a: nil, b: nil)

    static func planned(_ plan: TripPlan = plan, selection: SectionSelection = noSelection) -> TripUiStatePlanned {
        TripUiStatePlanned(
            plan: plan,
            startPosition: hamburg,
            startSocPercent: 80,
            selection: selection,
            socInput: nil,
            arrivalSocInput: nil,
            socAskedForReplan: false
        )
    }

    static func unreachable(_ why: UnreachableTrip) -> TripUiStateUnreachable {
        TripUiStateUnreachable(destination: munichDestination, why: why, startSocPercent: 12, socInput: nil, arrivalSocInput: nil, socAskedForReplan: false)
    }

    static func home(
        position: LatLon? = hamburg,
        belowMinZoom: Bool = false,
        mode: ChargeMode = .normal,
        searchingLocation: Bool = false,
        locationUnavailable: Bool = false,
        loadingSites: Bool = false
    ) -> HomeUiState {
        HomeUiState(
            position: position,
            chargers: [],
            belowMinZoom: belowMinZoom,
            selectedStop: nil,
            selectedStopLive: nil,
            filtersCustomized: false,
            mode: mode,
            searchingLocation: searchingLocation,
            locationUnavailable: locationUnavailable,
            loadingSites: loadingSites
        )
    }

    static func search(expanded: Bool = false, query: String = "", rows: [SearchRow] = [], searching: Bool = false, failed: Bool = false) -> SearchUiState {
        SearchUiState(expanded: expanded, query: query, rows: rows, searching: searching, failed: failed, hasVehicle: true, results: [])
    }

    static func row(_ title: String, _ detail: String?, km: Double?, recent: Bool) -> SearchRow {
        SearchRow(
            destination: Destination(name: title, position: munich, address: detail),
            title: title,
            detail: detail,
            distanceKm: km.map { KotlinDouble(value: $0) },
            recent: recent
        )
    }

    static func chargeStop(_ site: ChargeSite, km: Double) -> ChargeStop {
        ChargeStop(site: site, distanceKm: km, reachability: .unknown, socOnArrivalPercent: nil, primaryConnector: nil)
    }

    static func candidate(_ site: ChargeSite, km: Double) -> ChargeNowCandidate {
        ChargeNowCandidate(site: site, distanceKm: km, maxPowerKw: site.connectors.first?.maxPowerKw ?? 0)
    }
}
