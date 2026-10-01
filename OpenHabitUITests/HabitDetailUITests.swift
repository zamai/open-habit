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
            let addNote = app.buttons["Add today’s note"]
            XCTAssertTrue(addNote.waitForExistence(timeout: 3), app.debugDescription)
            XCTAssertTrue(app.buttons["Mark yesterday complete"].exists)
            XCTAssertFalse(app.buttons["Undo latest Completion today"].exists)
            XCTAssertFalse(app.buttons["Mark today complete"].exists)
            XCTAssertTrue(app.buttons["Edit Habit"].exists)
            XCTAssertFalse(app.buttons["Archive Habit"].exists)
            XCTAssertFalse(app.buttons["Delete Habit"].exists)
            app.navigationBars["Open Habit"].tap()
            XCTAssertTrue(addNote.waitForNonExistence(timeout: 3), app.debugDescription)
            XCTAssertEqual(completion.label, originalCompletions, "Long pressing must not change Completions")
        }

        completion.tap()
        XCTAssertNotEqual(completion.label, originalCompletions, "A normal tap must still change Completions")
        completion.tap()
        XCTAssertEqual(completion.label, originalCompletions)
        title.tap()
        XCTAssertTrue(app.navigationBars["Habit Detail"].waitForExistence(timeout: 3), app.debugDescription)
    }

    func testHabitCardHistoryTapsOpenDetailWithoutChangingCompletions() {
        app.launch()
        let history = app.buttons["history-00000000-0000-0000-0000-000000000001"]
        let completion = app.buttons["complete-00000000-0000-0000-0000-000000000001"]
        makeHittable(history)
        let originalCompletions = completion.label

        // Canvas cells, labels, and gaps should all belong to the same navigation button.
        for point in [CGVector(dx: 0.5, dy: 0.5), CGVector(dx: 0.85, dy: 0.8), CGVector(dx: 0.05, dy: 0.4)] {
            history.coordinate(withNormalizedOffset: point).tap()
            XCTAssertTrue(app.navigationBars["Habit Detail"].waitForExistence(timeout: 3), app.debugDescription)
            app.navigationBars["Habit Detail"].buttons.firstMatch.tap()
            makeHittable(history)
            XCTAssertEqual(completion.label, originalCompletions, "Opening history must not log a Completion")
        }
    }

    func testSharedDetailEndsWithMembersAndKeepsSharingInSettings() {
        app.launchArguments = ["--preview-shared-detail"]
        app.launch()
        let exercise = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", ", Exercise,")).firstMatch
        makeHittable(exercise)
        exercise.tap()

        let day = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " Completions, target ")).firstMatch
        let note = app.descendants(matching: .any)["Day Note"].firstMatch
        let members = app.staticTexts["Members"].firstMatch
        makeHittable(day)
        makeHittable(note)
        if ProcessInfo.processInfo.environment["GENERATE_UI_GLOSSARY"] == "1" {
            capture("glossary-inline-note")
        }
        makeHittable(members)
        XCTAssertLessThan(day.frame.minY, note.frame.minY)
        XCTAssertLessThan(note.frame.minY, members.frame.minY)
        XCTAssertFalse(app.staticTexts["Invitations"].exists)
        XCTAssertFalse(app.buttons["Invite a Member"].exists)
        XCTAssertFalse(app.buttons["Stop Sharing"].exists)
        XCTAssertFalse(app.staticTexts["Empty"].exists, "The Full Completion Grid and its legend are gone")

        app.buttons["Edit Habit"].tap()
        XCTAssertTrue(app.navigationBars["Edit Habit"].waitForExistence(timeout: 3))
        let invitations = app.staticTexts["Invitations"]
        for _ in 0..<8 where !invitations.exists { app.swipeUp() }
        XCTAssertTrue(invitations.exists)
        XCTAssertTrue(app.buttons["Invite a Member"].exists)
        XCTAssertTrue(app.buttons["Stop Sharing"].exists)
    }

    func testSharedMemberCanStillLeaveFromSettings() {
        app.launchArguments = ["--preview-shared-member-detail"]
        app.launch()
        let exercise = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", ", Exercise,")).firstMatch
        makeHittable(exercise)
        exercise.tap()

        XCTAssertTrue(app.staticTexts["Members"].exists)
        XCTAssertFalse(app.buttons["Leave Shared Habit"].exists)
        app.buttons["Sharing Settings"].tap()
        XCTAssertTrue(app.navigationBars["Sharing Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Leave Shared Habit"].exists)
    }

    func testCaptureUIGlossary() throws {
        guard ProcessInfo.processInfo.environment["GENERATE_UI_GLOSSARY"] == "1" else {
            throw XCTSkip("Opt-in screenshots for docs/ui-glossary.md")
        }
        executionTimeAllowance = 600
        app.launch()
        let title = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", ", Exercise,")).firstMatch
        let history = app.buttons["history-00000000-0000-0000-0000-000000000001"]
        makeHittable(history)
        capture("glossary-overview")

        title.tap()
        XCTAssertTrue(app.navigationBars["Habit Detail"].waitForExistence(timeout: 3))
        capture("glossary-habit-detail")
        let date = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " Completions, target ")).firstMatch
        makeHittable(date)
        date.press(forDuration: 1)
        XCTAssertTrue(app.navigationBars["Edit Habit Day"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        capture("glossary-day-note-sheet")
        app.navigationBars["Edit Habit Day"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Edit Habit Day"].waitForNonExistence(timeout: 5))

        makeHittable(app.descendants(matching: .any)["Day Note"].firstMatch)
        app.swipeUp()
        capture("glossary-inline-note")
        app.buttons["Edit Habit"].tap()
        XCTAssertTrue(app.navigationBars["Edit Habit"].waitForExistence(timeout: 3), app.debugDescription)
        capture("glossary-habit-settings")
        app.buttons["habit-emoji"].tap()
        XCTAssertTrue(app.navigationBars["Choose Emoji"].waitForExistence(timeout: 3))
        capture("glossary-emoji-picker")
        app.navigationBars["Choose Emoji"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Choose Emoji"].waitForNonExistence(timeout: 5))
        app.collectionViews.firstMatch.swipeUp()
        makeHittable(app.buttons["Share Habit"])
        capture("glossary-habit-actions")
        app.buttons["Share Habit"].tap()
        XCTAssertTrue(app.navigationBars["Share Habit"].waitForExistence(timeout: 3))
        capture("glossary-share-setup")
        app.navigationBars["Share Habit"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Share Habit"].waitForNonExistence(timeout: 5))
        app.navigationBars["Edit Habit"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Edit Habit"].waitForNonExistence(timeout: 5))

        app.navigationBars["Habit Detail"].buttons.firstMatch.tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        capture("glossary-app-settings")
        app.buttons["Done"].tap()

        makeHittable(history)
        history.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Add today’s note"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(app.buttons["Edit Habit"].exists)
        XCTAssertTrue(app.buttons["Mark yesterday complete"].exists)
        XCTAssertFalse(app.buttons["Undo latest Completion today"].exists)
        XCTAssertFalse(app.buttons["Mark today complete"].exists)
        XCTAssertFalse(app.buttons["Archive Habit"].exists)
        XCTAssertFalse(app.buttons["Delete Habit"].exists)
        capture("glossary-quick-actions")
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

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
