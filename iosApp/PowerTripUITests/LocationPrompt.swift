import XCTest

extension XCTestCase {
    /// A fresh install asks for the location once; the app is useless without it, so the tests allow it.
    func allowLocationIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Verwenden' OR label CONTAINS[c] 'While Using'")
        ).firstMatch
        if allow.waitForExistence(timeout: 5) { allow.tap() }
    }
}
