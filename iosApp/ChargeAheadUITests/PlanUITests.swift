import XCTest

/// Search, pick, plan: a trip sheet with the destination on top, or, without a car, the way to the garage.
final class PlanUITests: XCTestCase {

    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
        allowLocationIfAsked()
    }

    func testPickingADestinationPlansOrAsksForACar() {
        let search = app.textFields["search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        // Planning starts from the current position; the locate button stops waiting once there is one.
        let located = expectation(for: NSPredicate(format: "value == nil OR value == ''"), evaluatedWith: app.buttons["locate"])
        wait(for: [located], timeout: 30)
        search.tap()
        search.typeText("München")
        let hit = app.buttons.matching(identifier: "search-row").firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 20), "the geocoder sent nothing back")
        hit.tap()

        let sent = app.buttons["send-to-maps"]
        let replan = app.buttons["replan"]
        let askedForCar = app.alerts.firstMatch
        let deadline = Date().addingTimeInterval(60)
        while !(sent.exists || replan.exists || askedForCar.exists) && Date() < deadline {
            _ = sent.waitForExistence(timeout: 1)
        }
        if askedForCar.exists {
            // The tests share one install: whether a car is there depends on which test ran first.
            askedForCar.buttons["Auto anlegen"].tap()
            XCTAssertTrue(app.buttons["garage-add"].waitForExistence(timeout: 10), "the garage did not open")
        } else {
            XCTAssertTrue(sent.exists || replan.exists, "planning never came back")
            app.buttons["trip-clear"].tap()
            XCTAssertTrue(search.waitForExistence(timeout: 10), "clearing the trip did not bring the search back")
        }
    }
}
