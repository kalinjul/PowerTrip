import XCTest
@testable import PowerTrip

/// Which sheet is up when several want to be.
final class OverlayTests: XCTestCase {

    private func shown(
        _ navigation: PhoneOverlay? = nil,
        stop: Bool = false,
        start: Bool = false,
        arrival: Bool = false,
        replan: Bool = false
    ) -> PhoneOverlay? {
        PhoneOverlay.shown(navigation: navigation, stopSelected: stop, startLevelOpen: start, arrivalLevelOpen: arrival, replanLevelOpen: replan)
    }

    func testNavigationShowsWhenNothingElseIsOpen() {
        XCTAssertNil(shown())
        XCTAssertEqual(shown(.settings(nil)), .settings(nil))
    }

    func testASelectedChargerWinsOverNavigation() {
        XCTAssertEqual(shown(.settings(nil), stop: true), .stopDetail)
        XCTAssertEqual(shown(nil, stop: true), .stopDetail)
    }

    func testOverChargeNowTheChargerOpensInsideThatSheet() {
        XCTAssertEqual(shown(.chargeNow, stop: true), .chargeNow)
    }

    func testAnOpenLevelEditorWinsOverEverything() {
        XCTAssertEqual(shown(.chargeNow, stop: true, start: true), .startLevel)
        XCTAssertEqual(shown(nil, stop: true, arrival: true), .arrivalLevel)
        XCTAssertEqual(shown(.settings(.garage), replan: true), .replanLevel)
    }
}
