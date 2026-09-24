import XCTest

final class HabitDetailUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("Habit Detail UI tests run on Simulator.")
        #endif
    }

    func testCalendarTapCyclesCompletionsAndHoldOpensDayNote() {
        app.launch()

        let exercise = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", ", Exercise,")).firstMatch
        makeHittable(exercise)
        exercise.tap()

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: yesterday)
        let calendarDate = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", date + ",")).firstMatch
        makeHittable(calendarDate)
        let completionsBeforeTap = Int(calendarDate.label.split(separator: ",")[1].split(separator: " ")[0])!
        let completionsAfterTap = completionsBeforeTap >= 1 ? 0 : completionsBeforeTap + 1

        calendarDate.tap()
        XCTAssertTrue(calendarDate.label.contains(", \(completionsAfterTap) Completions,"))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.buttons["Go to today"].exists)

        calendarDate.tap()
        let completionsAfterSecondTap = completionsAfterTap >= 1 ? 0 : completionsAfterTap + 1
        XCTAssertTrue(calendarDate.label.contains(", \(completionsAfterSecondTap) Completions,"))

        calendarDate.press(forDuration: 1)
        XCTAssertTrue(app.navigationBars["Edit Habit Day"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), app.debugDescription)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(calendarDate.label.contains(", \(completionsAfterSecondTap) Completions,"))
    }

    private func makeHittable(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 3), app.debugDescription, file: file, line: line)
        for _ in 0..<10 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription, file: file, line: line)
    }
}
