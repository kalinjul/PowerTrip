import Shared
import SwiftUI
import XCTest
@testable import ChargeAhead

@MainActor
final class GarageSnapshotTests: XCTestCase {

    func testTwoCarsOneSelected() {
        assertLightAndDark(GarageContent(state: Fixtures.garage()) { EmptyView() }, named: "garage", frame: .phone)
    }

    func testEmptyGarage() {
        assertLightAndDark(GarageContent(state: Fixtures.garage([], selected: nil)) { EmptyView() }, named: "garage", frame: .phone)
    }

    func testBatteryLevelSheet() {
        assertLightAndDark(
            LevelSheet(
                title: localized("garage_soc_title"),
                hint: localized("garage_soc_sheet_hint"),
                percent: 64,
                range: TripPlanKt.SOC_RANGE,
                onChange: { _ in },
                onApply: {},
                onCancel: {}
            ),
            named: "sheet",
            frame: .fitting
        )
    }

    func testCatalog() {
        assertLightAndDark(
            NavigationStack {
                AddCarContent(state: AddCarUiState(query: "", matches: [Fixtures.model3, Fixtures.id3, Fixtures.zoe]), query: .constant(""))
            },
            named: "add-car",
            frame: .phone
        )
    }

    func testCatalogWithoutMatch() {
        assertLightAndDark(
            NavigationStack {
                AddCarContent(state: AddCarUiState(query: "Trabant", matches: []), query: .constant("Trabant"))
            },
            named: "add-car",
            frame: .phone
        )
    }
}
