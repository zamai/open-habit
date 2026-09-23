import XCTest

final class ImportUITests: XCTestCase {
    private let app = XCUIApplication()
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("Destructive import tests run only on a disposable Simulator.")
        #endif
    }
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 2)
        for _ in 0..<12 {
            if element.exists && element.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, app.debugDescription, file: file, line: line)
        element.tap()
    }
    private func openSettings() { tap(app.buttons["Settings"]) }
    @discardableResult private func chooseFile(_ name: String, habitKit: Bool, optional: Bool = false) -> Bool {
        tap(app.buttons["Import"])
        tap(app.buttons[habitKit ? "HabitKit data import" : "Open Habit import"])
        let browse = app.tabBars.buttons["Browse"].firstMatch
        XCTAssertTrue(browse.waitForExistence(timeout: 10), app.debugDescription)
        browse.tap()
        let onMyIPhone = app.staticTexts["On My iPhone"].firstMatch
        XCTAssertTrue(onMyIPhone.waitForExistence(timeout: 10), app.debugDescription)
        onMyIPhone.tap()
        if app.cells["Open Habit, Container"].waitForExistence(timeout: 3) { app.cells["Open Habit, Container"].tap() }
        let file = app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", name + ".json")).firstMatch
        if !file.waitForExistence(timeout: 10) {
            if optional { return false }
            XCTFail(app.debugDescription)
        }
        file.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        return true
    }
    // On a disposable Simulator, stage habitkit-synthetic.json in the app's Documents before running.
    func testCreateImportNoteExportDeleteAndRestoreThroughFiles() throws {
        try roundTrip(file: "habitkit-synthetic", personal: false)
    }
    func testPersonalHabitKitRoundTripWhenStaged() throws {
        // Check availability before creating any data, so an optional skip leaves the store unchanged.
        app.launch()
        openSettings()
        guard chooseFile("habitkit-personal", habitKit: true, optional: true) else {
            throw XCTSkip("Stage the original HabitKit file as habitkit-personal.json to run the personal-data UI test.")
        }
        XCTAssertTrue(app.staticTexts["Categories"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        tap(app.buttons["Cancel"])
        tap(app.buttons["Done"])
        try roundTrip(file: "habitkit-personal", personal: true)
    }
    private func roundTrip(file: String, personal: Bool) throws {
        app.launch()
        let name = "UI round-trip " + UUID().uuidString.prefix(6)
        let exportName = "UI-backup-" + UUID().uuidString.prefix(6)
        tap(app.buttons["add-habit"])
        tap(app.textFields["habit-name"]); app.textFields["habit-name"].typeText(name)
        tap(app.buttons["save-habit"])
        openSettings()
        chooseFile(file, habitKit: true)
        XCTAssertTrue(app.staticTexts["Categories"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        if personal {
            // These choices exercise the UI; they do not assert HabitKit's unknown aggregation semantics.
            let archivedDay = app.buttons["duplicate-69FE2FDB-63AE-4192-AC06-115A26FCF800/2025-01-27"]
            if archivedDay.exists {
                tap(archivedDay)
                tap(app.buttons["Add amounts: 3"])
            }
            tap(app.buttons["duplicate-F54D5BE4-B171-4932-B257-4882E7E8B01E/2025-09-30"])
            tap(app.buttons["Add amounts: 2"])
        }
        tap(app.buttons["confirm-import"])
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5), app.debugDescription)
        openSettings()
        chooseFile(file, habitKit: true)
        XCTAssertTrue(app.buttons["Replace all data"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["Replace all data"].isSelected, app.debugDescription)
        tap(app.buttons["Cancel"])
        tap(app.buttons["Done"])
        tap(app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", ", " + name)).firstMatch)
        let note = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND (elementType == %d OR elementType == %d)", "Day Note", XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue)).firstMatch
        tap(note); note.typeText("UI round-trip note")
        tap(app.buttons["Save Note"])
        tap(app.navigationBars.buttons.element(boundBy: 0))
        openSettings()
        tap(app.buttons["Export Backup"])
        // The system save picker writes a real native JSON file.
        if app.staticTexts["On My iPhone"].firstMatch.waitForExistence(timeout: 3) { app.staticTexts["On My iPhone"].firstMatch.tap() }
        if app.cells["Open Habit, Container"].waitForExistence(timeout: 3) { app.cells["Open Habit, Container"].tap() }
        let filename = app.textFields.firstMatch
        if filename.waitForExistence(timeout: 3) {
            filename.tap()
            if let current = filename.value as? String { filename.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)) }
            filename.typeText(exportName)
        }
        tap(app.buttons["Save"].firstMatch)
        tap(app.buttons["Delete All Data"])
        tap(app.alerts.buttons["Yes, erase all"])
        chooseFile(exportName, habitKit: false)
        tap(app.buttons["Replace all data"])
        tap(app.buttons["confirm-import"])
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5), app.debugDescription)
        tap(app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", ", " + name)).firstMatch)
        tap(note)
        XCTAssertEqual(note.value as? String, "UI round-trip note")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Restored note"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
