import XCTest

final class HabitDetailUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("Habit Detail UI tests run on Simulator.")
        #endif
    }

    func testWholeHabitCardOpensQuickActionsWithoutArchiveOrDelete() {
        app.launch()

        let title = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", ", Exercise,")).firstMatch
        let completion = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Exercise, ")).firstMatch
        let history = app.descendants(matching: .any)["View Exercise history"].firstMatch
        makeHittable(title)
        makeHittable(history)
        makeHittable(completion)
        let originalCompletions = completion.label

        let padding = app.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: title.frame.minX - 9, dy: title.frame.minY + 10)
        )
        let targets = [
            title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
            completion.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
            history.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
            padding
        ]
        for target in targets {
            target.press(forDuration: 1)
            let editNote = app.buttons["Edit today’s note"]
            XCTAssertTrue(editNote.waitForExistence(timeout: 3), app.debugDescription)
            XCTAssertTrue(app.buttons["Edit Habit"].exists)
            XCTAssertFalse(app.buttons["Archive Habit"].exists)
            XCTAssertFalse(app.buttons["Delete Habit"].exists)
            app.navigationBars["Open Habit"].tap()
            XCTAssertTrue(editNote.waitForNonExistence(timeout: 3), app.debugDescription)
            XCTAssertEqual(completion.label, originalCompletions, "Long pressing must not change Completions")
        }

        completion.tap()
        XCTAssertNotEqual(completion.label, originalCompletions, "A normal tap must still change Completions")
        completion.tap()
        XCTAssertEqual(completion.label, originalCompletions)
        title.tap()
        XCTAssertTrue(app.navigationBars["Habit Detail"].waitForExistence(timeout: 3), app.debugDescription)
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
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", " / 500")).firstMatch.exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Edit Habit Day"].waitForNonExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(calendarDate.label.contains(", \(completionsAfterSecondTap) Completions,"))

        let note = app.descendants(matching: .any)["Day Note"].firstMatch
        makeHittable(note)
        note.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3), app.debugDescription)
        let deadline = Date().addingTimeInterval(3)
        while note.frame.maxY >= keyboard.frame.minY - 8 && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertLessThan(note.frame.maxY, keyboard.frame.minY - 8)
        XCTAssertLessThan(keyboard.frame.minY - note.frame.maxY, 80)
        let settledNoteY = note.frame.minY
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertLessThan(abs(note.frame.minY - settledNoteY), 8)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", " / 500")).firstMatch.exists)
    }

    private func makeHittable(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 3), app.debugDescription, file: file, line: line)
        for _ in 0..<10 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription, file: file, line: line)
    }
}
