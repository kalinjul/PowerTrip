import XCTest

/// The trip from the search bar to the active route page and back to the map.
final class PlanUITests: XCTestCase {

    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
        allowLocationIfAsked()
    }

    func testAPlanSentToMapsBecomesTheActiveRouteUntilItIsEnded() {
        ensureACar()

        // Planning starts from the current position; the locate button stops waiting once there is one.
        let located = expectation(for: NSPredicate(format: "value == nil OR value == ''"), evaluatedWith: app.buttons["locate"])
        wait(for: [located], timeout: 30)

        let search = app.textFields["search"]
        search.tap()
        search.typeText("München")
        let hit = app.buttons.matching(identifier: "search-row").firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 20), "the geocoder sent nothing back")
        hit.tap()

        let send = app.buttons["send-to-maps"]
        XCTAssertTrue(send.waitForExistence(timeout: 60), "no plan came back")
        XCTAssertTrue(app.buttons["trip-clear"].exists, "the destination header is missing")
        send.tap()

        // Maps opens in another app; sending is committing, so the active route waits on return.
        app.activate()
        let end = app.buttons["end-trip"]
        XCTAssertTrue(end.waitForExistence(timeout: 20), "the active route page did not open")
        end.tap()

        let activeRoute = app.buttons["active-route"]
        XCTAssertTrue(activeRoute.waitForExistence(timeout: 10), "ending the trip did not lead back to the map")
        XCTAssertFalse(activeRoute.isEnabled, "the ended trip is still active")
    }

    /// The tests share one install, so the garage may or may not have a car yet.
    private func ensureACar() {
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 10))
        app.buttons["settings"].tap()
        app.buttons["garage"].tap()
        XCTAssertTrue(app.buttons["level-soc"].waitForExistence(timeout: 10))
        if !app.buttons["vehicle-edit"].exists {
            app.buttons["garage-add"].tap()
            let preset = app.buttons.matching(identifier: "preset").firstMatch
            XCTAssertTrue(preset.waitForExistence(timeout: 20), "the catalog never arrived")
            preset.tap()
            XCTAssertTrue(app.buttons["vehicle-edit"].waitForExistence(timeout: 10))
        }
        app.buttons["BackButton"].tap()
        app.buttons["settings-done"].tap()
    }
}
