import XCTest

final class WidgetUITests: XCTestCase {
    // Run on an English-language test Simulator. Adds the small widget only if it is missing.
    func testSmallWidgetCanBeInstalledAndConfigured() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["add-habit"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        let home = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = home.icons["Open Habit"].firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 10))
        if icon.value as? String != "Widget" {
            icon.press(forDuration: 1.5)
            let small = home.buttons["Small widget"]
            XCTAssertTrue(small.waitForExistence(timeout: 5))
            small.tap()
            XCTAssertTrue(home.staticTexts["Choose a Habit"].firstMatch.waitForExistence(timeout: 15))
        }
        icon.press(forDuration: 1.5)
        XCTAssertTrue(home.buttons["Edit Widget"].waitForExistence(timeout: 5))
        home.buttons["Edit Home Screen"].tap()
    }
}
