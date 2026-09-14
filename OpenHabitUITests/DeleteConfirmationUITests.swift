import XCTest

final class DeleteConfirmationUITests: XCTestCase {
    func testHabitDeletionUsesDestructiveAlertWithCancel() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["add-habit"].waitForExistence(timeout: 10))
        app.buttons["add-habit"].tap()

        let name = "Delete confirmation " + UUID().uuidString.prefix(6)
        let nameField = app.textFields["habit-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        app.buttons["save-habit"].tap()

        let habit = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", ", " + name)).firstMatch
        XCTAssertTrue(habit.waitForExistence(timeout: 5), app.debugDescription)
        habit.tap()
        app.buttons["Edit Habit"].tap()

        let delete = app.buttons["Delete Habit"]
        for _ in 0..<12 where !delete.isHittable { app.swipeUp() }
        XCTAssertTrue(delete.isHittable, app.debugDescription)
        delete.tap()

        let alert = app.alerts["Delete this Habit permanently?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(alert.buttons["Delete"].exists)
        XCTAssertTrue(alert.buttons["Cancel"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Habit delete confirmation alert"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Edit Habit"].exists)

        delete.tap()
        app.alerts.buttons["Delete"].tap()

        XCTAssertTrue(app.navigationBars["Open Habit"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Habit unavailable"].exists)
        XCTAssertTrue(habit.waitForNonExistence(timeout: 5))
        let result = XCTAttachment(screenshot: app.screenshot())
        result.name = "Main habits screen after deletion"
        result.lifetime = .keepAlways
        add(result)
    }
}
