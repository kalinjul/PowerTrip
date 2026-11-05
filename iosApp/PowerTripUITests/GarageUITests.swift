import XCTest

/// Drives the app like a driver would; screenshots land in SCREENSHOT_DIR when it is set.
final class GarageUITests: XCTestCase {

    private let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
        allowLocationIfAsked()
    }

    func testACarFromTheCatalogBecomesTheOneToPlanWith() {
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 10))
        app.buttons["settings"].tap()
        app.buttons["garage"].tap()
        XCTAssertTrue(app.buttons["garage-add"].waitForExistence(timeout: 10))
        snapshot("garage-before")

        app.buttons["garage-add"].tap()
        XCTAssertTrue(app.buttons.matching(identifier: "preset").firstMatch.waitForExistence(timeout: 20), "the catalog never arrived")
        let search = app.searchFields.firstMatch
        search.tap()
        // Typed at full speed: the field reads its text back from the shared ViewModel.
        search.typeText("Tesla")
        XCTAssertEqual(search.value as? String, "Tesla")
        let firstPreset = app.buttons.matching(NSPredicate(format: "identifier == 'preset' AND label BEGINSWITH 'Tesla'")).firstMatch
        XCTAssertTrue(firstPreset.waitForExistence(timeout: 10), "no Tesla in the catalog")
        snapshot("add-car")
        let name = firstPreset.label.components(separatedBy: ",").first ?? ""
        firstPreset.tap()

        let selected = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'vehicle' AND isSelected == true")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 10), "the added car is not the selected one")
        XCTAssertTrue(selected.label.hasPrefix(name), "selected \(selected.label), added \(name)")
        snapshot("garage-after")

        app.buttons["level-soc"].tap()
        XCTAssertTrue(app.sliders.firstMatch.waitForExistence(timeout: 5))
        snapshot("soc-sheet")
    }

    func testTheDotsSwitchTheCar() {
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 10))
        app.buttons["settings"].tap()
        app.buttons["garage"].tap()
        let earlier = addPreset(matching: "Tesla")
        _ = addPreset(matching: "ID.3")

        let dots = app.pageIndicators["car-dots"]
        XCTAssertTrue(dots.waitForExistence(timeout: 10), "two cars, but no dots")
        snapshot("dots")
        // Left of the current dot means one car back.
        dots.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()

        let selected = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'vehicle' AND isSelected == true AND label BEGINSWITH %@", earlier))
            .firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 10), "the dots did not switch back to \(earlier)")
    }

    /// Adds the first catalog car whose name contains `model` and returns its name.
    private func addPreset(matching model: String) -> String {
        let add = app.buttons.matching(identifier: "garage-add").firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "preset").firstMatch.waitForExistence(timeout: 20), "the catalog never arrived")
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText(model)
        let preset = app.buttons.matching(NSPredicate(format: "identifier == 'preset' AND label CONTAINS %@", model)).firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 10), "no \(model) in the catalog")
        let name = preset.label.components(separatedBy: ",").first ?? ""
        preset.tap()
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the add page did not close")
        return name
    }

    private func snapshot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
