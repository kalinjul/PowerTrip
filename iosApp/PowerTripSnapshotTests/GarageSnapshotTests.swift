import Shared
import SwiftUI
import XCTest
@testable import PowerTrip

@MainActor
final class GarageSnapshotTests: XCTestCase {

    func testTwoCarsOneSelected() {
        assertLightAndDark(NavigationStack { GarageContent(state: Fixtures.garage(), actions: .none) }, named: "garage", frame: .phone)
    }

    func testOneCar() {
        assertLightAndDark(NavigationStack { GarageContent(state: Fixtures.garage([Fixtures.id3]), actions: .none) }, named: "garage", frame: .phone)
    }

    func testEmptyGarage() {
        assertLightAndDark(NavigationStack { GarageContent(state: Fixtures.garage([], selected: nil), actions: .none) }, named: "garage", frame: .phone)
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
                AddCarContent(state: AddCarUiState(query: "", matches: [Fixtures.model3, Fixtures.id3, Fixtures.zoe]), query: .constant("")) { _ in }
            },
            named: "add-car",
            frame: .phone
        )
    }

    func testCatalogWithoutMatch() {
        assertLightAndDark(
            NavigationStack {
                AddCarContent(state: AddCarUiState(query: "Trabant", matches: []), query: .constant("Trabant")) { _ in }
            },
            named: "add-car",
            frame: .phone
        )
    }

    func testVehiclePage() {
        let vehicle = Fixtures.id3.toProfile()
        assertLightAndDark(
            NavigationStack {
                VehicleEditContent(
                    state: VehicleEditUiState(vehicle: vehicle, catalog: Fixtures.id3, canRestoreCatalogValues: false, editor: nil, confirmingRemoval: false, removed: false),
                    actions: .none
                )
            },
            named: "vehicle",
            frame: .phone
        )
    }

    func testOwnVehiclePage() {
        let own = VehicleKt.customVehicle(name: "Mein Auto")
        assertLightAndDark(
            NavigationStack {
                VehicleEditContent(
                    state: VehicleEditUiState(vehicle: own, catalog: nil, canRestoreCatalogValues: false, editor: nil, confirmingRemoval: false, removed: false),
                    actions: .none
                )
            },
            named: "vehicle",
            frame: .phone
        )
    }
}
