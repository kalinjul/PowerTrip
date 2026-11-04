import Shared
import SwiftUI
import XCTest
@testable import PowerTrip

/// The trip sheet's content at the height the peeked or the expanded sheet gives it.
@MainActor
final class TripSnapshotTests: XCTestCase {

    private func sheet(_ trip: TripUiStateSheet, layout: TripListLayout = .list, height: CGFloat = 520) -> some View {
        TripSheetContent(
            trip: trip,
            layout: layout,
            now: Fixtures.now,
            actions: TripActions(startSocEdit: {}, arrivalSocEdit: {})
        )
        .frame(width: 402, height: height)
        .background(Color(.systemBackground))
    }

    func testList() {
        assertLightAndDark(sheet(Fixtures.planned()), named: "trip")
    }

    func testListWithForecast() {
        assertLightAndDark(sheet(Fixtures.planned(Fixtures.planWithForecast), height: 600), named: "trip")
    }

    func testListSectionPicked() {
        assertLightAndDark(sheet(Fixtures.planned(selection: SectionSelection(selecting: true, a: 1, b: 3))), named: "trip")
    }

    func testTiles() {
        assertLightAndDark(sheet(Fixtures.planned(), layout: .tiles, height: 290), named: "trip")
    }

    func testNoChargerInReach() {
        assertLightAndDark(sheet(Fixtures.unreachable(UnreachableTripNoCharger(afterKm: 0)), height: 290), named: "trip")
    }

    func testNoConnection() {
        assertLightAndDark(sheet(Fixtures.unreachable(UnreachableTripNoConnection.shared), height: 290), named: "trip")
    }

    func testActiveRoute() {
        let state = ActiveRouteUiState(
            trip: CommittedTrip(plan: Fixtures.plan, startSocPercent: 80, committedAtEpochMillis: 0),
            selection: Fixtures.noSelection,
            planning: false,
            startPosition: Fixtures.hamburg,
            socInput: nil,
            shownOnMap: false
        )
        assertLightAndDark(
            NavigationStack {
                ActiveRouteView(state: state, now: Fixtures.now, actions: .none, onEnd: {})
            },
            named: "active-route",
            frame: .phone
        )
    }
}
