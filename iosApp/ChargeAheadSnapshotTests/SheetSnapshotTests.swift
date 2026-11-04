import Shared
import SwiftUI
import XCTest
@testable import ChargeAhead

@MainActor
final class SheetSnapshotTests: XCTestCase {

    func testStopDetail() {
        assertLightAndDark(
            StopDetailSheet(
                stop: Fixtures.chargeStop(Fixtures.ionity, km: 168),
                live: nil,
                tripLine: localized("trip_stop_times", "16:08", "16:30"),
                onNavigate: {}
            )
            .frame(width: 402)
            .background(Color(.systemBackground)),
            named: "detail"
        )
    }

    func testChargeNow() {
        let result = ChargeNowResult(
            candidates: [Fixtures.candidate(Fixtures.ionity, km: 3.4), Fixtures.candidate(Fixtures.enbw, km: 7.9)],
            relaxed: [],
            more: [Fixtures.candidate(Fixtures.aral, km: 12.1)]
        )
        assertLightAndDark(
            ChargeNowContent(state: ChargeNowUiStateReady(result: result), selectedSiteId: Fixtures.ionity.id, onNavigate: { _ in }, onOpen: { _ in })
                .frame(width: 402, height: 520)
                .background(Color(.systemBackground)),
            named: "charge-now"
        )
    }

    func testChargeNowLoading() {
        assertLightAndDark(
            ChargeNowContent(state: ChargeNowUiStateLoading.shared, onNavigate: { _ in }, onOpen: { _ in })
                .frame(width: 402, height: 520)
                .background(Color(.systemBackground)),
            named: "charge-now"
        )
    }

    func testLevelSheetBeforeReplanning() {
        assertLightAndDark(
            LevelSheet(
                title: localized("soc_dialog_title"),
                hint: localized("soc_dialog_car_silent"),
                percent: nil,
                range: TripPlanKt.SOC_RANGE,
                applyLabel: localized("trip_soc_confirm"),
                onChange: { _ in },
                onApply: {},
                onCancel: {}
            )
            .frame(width: 402),
            named: "sheet"
        )
    }
}
