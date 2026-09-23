import XCTest

final class HabitDetailUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("Habit Detail UI tests run on Simulator.")
        #endif
    }

    func testCalendarDateStartsEditingItsNoteWithoutChangingCompletions() {
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
        let completionsBeforeTap = calendarDate.label

        calendarDate.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 2), app.debugDescription)
        let note = app.descendants(matching: .any)["Day Note"].firstMatch
        XCTAssertTrue(note.exists, app.debugDescription)
        let visibleCenter = (app.frame.minY + keyboard.frame.minY) / 2
        XCTAssertLessThan(abs(note.frame.midY - visibleCenter), 120)
        XCTAssertLessThan(note.frame.maxY, keyboard.frame.minY)
        XCTAssertEqual(calendarDate.label, completionsBeforeTap)
    }

    private func makeHittable(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 3), app.debugDescription, file: file, line: line)
        for _ in 0..<10 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription, file: file, line: line)
    }
}
