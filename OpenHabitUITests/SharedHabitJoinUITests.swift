import XCTest

final class SharedHabitJoinUITests: XCTestCase {
    func testJoiningStepsPreserveChoicesAndRequireAnExistingHabitSelection() {
        let app = launchPreview()
        let name = app.textFields["join-member-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["join-continue"].isEnabled)
        XCTAssertFalse(app.buttons["join-confirm"].exists)
        name.tap()
        name.typeText("Alex")
        attach(app, "01 Member Name")

        app.buttons["join-continue"].tap()
        XCTAssertTrue(app.navigationBars["Review Habit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Read together"].exists)
        XCTAssertFalse(name.isHittable)
        attach(app, "02 Review Invitation")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Alex")
        app.buttons["join-continue"].tap()
        app.buttons["join-continue"].tap()
        XCTAssertTrue(app.navigationBars["Choose Your Habit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["join-confirm"].isEnabled)
        attach(app, "03 Start New Habit")

        app.buttons["join-use-existing"].tap()
        XCTAssertFalse(app.buttons["join-confirm"].isEnabled)
        app.buttons["join-existing-habit"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Reading")).firstMatch.tap()
        XCTAssertTrue(app.buttons["join-confirm"].isEnabled)
        attach(app, "04 Connect Existing Habit")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Review Habit"].waitForExistence(timeout: 5))
        app.buttons["join-continue"].tap()
        XCTAssertTrue(app.buttons["join-existing-habit"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["join-confirm"].isEnabled)
    }

    func testNoPrivateHabitsKeepsStartNewAvailableAtAccessibilityTextSize() {
        let app = launchPreview(extraArguments: ["--preview-join-empty", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let name = app.textFields["join-member-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Alex")
        app.buttons["join-continue"].tap()
        XCTAssertTrue(app.navigationBars["Review Habit"].waitForExistence(timeout: 5))
        app.buttons["join-continue"].tap()
        XCTAssertTrue(app.navigationBars["Choose Your Habit"].waitForExistence(timeout: 5))
        let existing = app.buttons["join-use-existing"]
        for _ in 0..<5 where !existing.isHittable { app.swipeUp() }
        XCTAssertFalse(existing.isEnabled)
        XCTAssertTrue(app.buttons["join-confirm"].isEnabled)
        XCTAssertTrue(app.buttons["join-confirm"].isHittable)
        attach(app, "05 Accessibility Text Size")
    }

    private func launchPreview(extraArguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--preview-join"] + extraArguments
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
