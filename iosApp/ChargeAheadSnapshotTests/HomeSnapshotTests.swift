import Shared
import SwiftUI
import XCTest
@testable import ChargeAhead

/// The map screen over a plain backdrop: maps don't render in a golden.
@MainActor
final class HomeSnapshotTests: XCTestCase {

    private func home(
        _ state: HomeUiState = Fixtures.home(),
        search: SearchUiState = Fixtures.search(),
        query: String = "",
        destination: Destination? = nil,
        plan: TripPlan? = nil,
        planning: Bool = false,
        activeRouteEnabled: Bool = true,
        access: LocationAccess = .granted
    ) -> some View {
        HomeContent(
            home: state,
            search: search,
            query: .constant(query),
            destination: destination,
            plan: plan,
            planning: planning,
            activeRouteEnabled: activeRouteEnabled,
            locationAccess: access,
            actions: .none
        ) {
            Color(.systemGray5)
        } compass: {
            EmptyView()
        }
    }

    func testBrowsing() {
        assertLightAndDark(home(), named: "home", frame: .phone)
    }

    func testZoomedOutLoadingWithoutActiveRoute() {
        assertLightAndDark(home(Fixtures.home(belowMinZoom: true, loadingSites: true), activeRouteEnabled: false), named: "home", frame: .phone)
    }

    func testLocationUnavailable() {
        assertLightAndDark(home(Fixtures.home(position: nil, searchingLocation: true, locationUnavailable: true)), named: "home", frame: .phone)
    }

    func testWithoutPermission() {
        assertLightAndDark(home(Fixtures.home(position: nil), access: .denied), named: "home", frame: .phone)
    }

    func testPlanning() {
        assertLightAndDark(home(planning: true), named: "home", frame: .phone)
    }

    func testAcMode() {
        assertLightAndDark(home(Fixtures.home(mode: .ac)), named: "home", frame: .phone)
    }

    func testBrowseMode() {
        assertLightAndDark(home(Fixtures.home(mode: .browse)), named: "home", frame: .phone)
    }

    func testDestinationHeaderWithPlan() {
        assertLightAndDark(home(destination: Fixtures.munichDestination, plan: Fixtures.plan), named: "home", frame: .phone)
    }

    func testSearchRecents() {
        let rows = [
            Fixtures.row("München", "Marienplatz 1, 80331 München", km: 612, recent: true),
            Fixtures.row("Ikea Altona", "Große Bergstraße 164, 22767 Hamburg", km: 4.2, recent: true),
        ]
        assertLightAndDark(home(search: Fixtures.search(expanded: true, rows: rows)), named: "home", frame: .phone)
    }

    func testSearchHits() {
        let rows = [
            Fixtures.row("Berlin", "Deutschland", km: 255, recent: false),
            Fixtures.row("Berlin Hauptbahnhof", "Europaplatz 1, 10557 Berlin", km: 257, recent: false),
            Fixtures.row("Berliner Tor", "20099 Hamburg", km: 0.4, recent: false),
        ]
        assertLightAndDark(home(search: Fixtures.search(expanded: true, query: "Berlin", rows: rows), query: "Berlin"), named: "home", frame: .phone)
    }

    func testSearchFailed() {
        assertLightAndDark(home(search: Fixtures.search(expanded: true, query: "Berlin", failed: true), query: "Berlin"), named: "home", frame: .phone)
    }

    func testSearchNoHits() {
        assertLightAndDark(home(search: Fixtures.search(expanded: true, query: "Xyzzy"), query: "Xyzzy"), named: "home", frame: .phone)
    }
}
