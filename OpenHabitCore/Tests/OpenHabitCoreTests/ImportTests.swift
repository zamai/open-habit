import XCTest
@testable import OpenHabitCore

final class ImportTests: XCTestCase {
    func fixture() throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: "habitkit-synthetic", withExtension: "json", subdirectory: "Fixtures")))
    }
    func changedFixture(_ change: (inout [String: Any]) -> Void) throws -> Data {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        change(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }
    func temporaryStore() -> LocalStore {
        LocalStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }
    func testImportEditExportDeleteRestorePreservesEntireDatasetAndRecovery() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.transaction { journal in
            for index in 0..<5 { try journal.save(Habit(name: "Existing \(index)", emoji: "📖")) }
            var settings = Settings(); settings.appearance = .dark; settings.weekStart = .sunday; settings.examplesDismissed = false
            journal.append(.settings(settings))
        }
        let beforeImport = try store.read().dataset
        let preview = try HabitKitImport.decode(fixture())
        XCTAssertEqual(preview.dataset.habits.count, 3)
        XCTAssertEqual(preview.dataset.habits[0].streakGoal, StreakGoal(period: .weekly, target: 3))
        XCTAssertEqual(preview.dataset.habits[1].target, 2)
        XCTAssertEqual(preview.dataset.categories?.first?.name, "Practice")
        XCTAssertEqual(preview.dataset.habits[0].categoryIDs, preview.dataset.categories?.map(\.id))
        XCTAssertEqual(preview.dataset.day(preview.dataset.habits[1].id, "2025-01-21").note, "First note\nSecond line")
        try store.importDataset(preview.resolved([:]))
        XCTAssertEqual(try store.read().dataset.habits.count, 8)
        XCTAssertEqual(try store.read().dataset.settings, beforeImport.settings)
        XCTAssertEqual(try Backup.decode(Data(contentsOf: XCTUnwrap(store.recoveryBackups().first))).dataset, beforeImport)
        try store.transaction { journal in
            for habit in journal.dataset.habits {
                try journal.setNote(habit.id, day: "2025-02-01", note: "Added after import\nПривіт 👋")
                try journal.setCount(habit.id, day: "2025-02-01", count: 7)
            }
        }
        let expected = try store.read().dataset
        try store.importDataset(preview.resolved([:]))
        XCTAssertEqual(try store.read().dataset, expected, "Reimport must preserve local edits and avoid duplicate counts")
        let exported = try Backup(dataset: expected).encoded()
        try store.deleteAllData()
        XCTAssertTrue(try store.read().dataset.habits.isEmpty)
        XCTAssertEqual(try Backup.decode(Data(contentsOf: XCTUnwrap(store.recoveryBackups().first))).dataset, expected)
        try store.importDataset(Backup.decode(exported).dataset)
        XCTAssertEqual(try store.read().dataset.habits, expected.habits)
        XCTAssertEqual(try store.read().dataset.days, expected.days)
        XCTAssertEqual(try store.read().dataset.categories, expected.categories)
        try store.restoreBackup(Backup.decode(exported))
        XCTAssertEqual(try store.read().dataset, expected, "Restore also recovers settings and order")
        XCTAssertEqual(try Backup.decode(Backup(dataset: store.read().dataset).encoded()).dataset, expected)
    }
    func testDuplicateDaysRequireExplicitResolutionAndPreserveDistinctNotes() throws {
        let data = try changedFixture { json in
            var records = json["completions"] as! [[String: Any]]
            var duplicate = records[0]; duplicate["id"] = UUID().uuidString
            duplicate["date"] = "2025-01-21T08:00:00Z"; duplicate["amountOfCompletions"] = 2
            duplicate["note"] = "Another note"
            records[0]["note"] = "Earlier note"; records.append(duplicate); json["completions"] = records
        }
        let preview = try HabitKitImport.decode(data)
        let conflict = try XCTUnwrap(preview.conflicts.first)
        XCTAssertThrowsError(try preview.resolved([:]))
        XCTAssertEqual(try preview.resolved([conflict.id: .sum]).days[conflict.id]?.count, 3)
        XCTAssertEqual(try preview.resolved([conflict.id: .latest]).days[conflict.id]?.count, 2)
        XCTAssertEqual(try preview.resolved([conflict.id: .maximum]).days[conflict.id]?.count, 2)
        XCTAssertEqual(preview.dataset.days[conflict.id]?.note, "Earlier note\n\nAnother note")
    }
    func testConcurrentImportsMergeOnceAndNeverResurrectDeletedHabits() throws {
        let imported = try HabitKitImport.decode(fixture()).resolved([:])
        var first = Journal(); var second = Journal()
        try first.importDataset(imported); try second.importDataset(imported)
        first.merge(second.edits); second.merge(first.edits)
        XCTAssertEqual(first.dataset, second.dataset)
        XCTAssertEqual(first.dataset.days, imported.days)
        let habit = imported.habits[0]
        try first.setNote(habit.id, day: "2025-01-21", note: "Local change")
        try second.importDataset(imported)
        first.merge(second.edits)
        XCTAssertEqual(first.dataset.day(habit.id, "2025-01-21").note, "Local change")
        first.append(.delete(habit.id)); try first.importDataset(imported)
        XCTAssertNil(first.dataset.habit(habit.id))
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(first), as: UTF8.self).contains(habit.name))
    }
    func testRecoveryWriteFailureAndInvalidImportLeaveOriginalBytesUnchanged() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.transaction { $0.seedIfEmpty() }
        let file = store.directory.appendingPathComponent("journal.json")
        let original = try Data(contentsOf: file)
        try Data("blocking file".utf8).write(to: store.recoveryDirectory)
        let imported = try HabitKitImport.decode(fixture()).resolved([:])
        XCTAssertThrowsError(try store.importDataset(imported))
        XCTAssertThrowsError(try store.restoreBackup(Backup(dataset: imported)))
        XCTAssertThrowsError(try store.deleteAllData())
        XCTAssertEqual(try Data(contentsOf: file), original)
        var invalid = imported; invalid.habits.append(imported.habits[0])
        XCTAssertThrowsError(try store.importDataset(invalid))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
    func testUnsupportedAndBrokenSourceFailsWithoutSilentLoss() throws {
        for field in ["isInverse", "name"] {
            let data = try changedFixture { json in
                var habits = json["habits"] as! [[String: Any]]
                habits[0][field] = field == "isInverse" ? true : String(repeating: "x", count: 61)
                json["habits"] = habits
            }
            XCTAssertThrowsError(try HabitKitImport.decode(data))
        }
        let duplicate = try changedFixture { json in
            var records = json["completions"] as! [[String: Any]]; records.append(records[0]); json["completions"] = records
        }
        XCTAssertThrowsError(try HabitKitImport.decode(duplicate))
        let orphan = try changedFixture { json in
            var mappings = json["categoryMappings"] as! [[String: Any]]; mappings[0]["categoryId"] = UUID().uuidString; json["categoryMappings"] = mappings
        }
        XCTAssertThrowsError(try HabitKitImport.decode(orphan))
        let current = try Backup(dataset: Dataset()).encoded()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: current) as? [String: Any])
        XCTAssertEqual(json["format"] as? String, "open-habit")
        json["format"] = "another-app"
        XCTAssertThrowsError(try Backup.decode(JSONSerialization.data(withJSONObject: json)))
        XCTAssertThrowsError(try HabitKitImport.decode(current))
    }
    func testVersion2BackupWithoutFormatIdentifierStillDecodes() throws {
        let current = Backup(dataset: try HabitKitImport.decode(fixture()).dataset)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: current.encoded()) as? [String: Any])
        json["formatVersion"] = 2; json.removeValue(forKey: "format")
        XCTAssertEqual(try Backup.decode(JSONSerialization.data(withJSONObject: json)).dataset, current.dataset)
    }
    func testRecordedOffsetsAndZeroCountNotesSurvive() throws {
        let data = try changedFixture { json in
            var records = json["completions"] as! [[String: Any]]
            records[0]["date"] = "2025-01-21T01:00:00Z"; records[0]["timezoneOffsetInMinutes"] = -120
            records[0]["amountOfCompletions"] = 0; records[0]["note"] = "An empty day still has a note"
            records[1]["date"] = "2025-07-20T22:00:00Z"; records[1]["timezoneOffsetInMinutes"] = 120
            records[2]["date"] = "2025-07-20T21:00:00Z"; records[2]["timezoneOffsetInMinutes"] = 180
            json["completions"] = records
        }
        let imported = try HabitKitImport.decode(data).resolved([:])
        XCTAssertEqual(imported.day(imported.habits[0].id, "2025-01-20"), HabitDay(count: 0, note: "An empty day still has a note"))
        XCTAssertEqual(imported.day(imported.habits[1].id, "2025-07-21").count, 2)
        XCTAssertEqual(imported.day(imported.habits[2].id, "2025-07-21").count, 3)
        XCTAssertEqual(try Backup.decode(Backup(dataset: imported).encoded()).dataset, imported)
    }
    func testNamesDoNotDetermineIdentityAndRepeatedImportPreservesPreferences() throws {
        var journal = Journal()
        try journal.save(Habit(name: "Drum practice"))
        let originalSettings = journal.dataset.settings
        let imported = try HabitKitImport.decode(fixture()).resolved([:])
        try journal.importDataset(imported)
        XCTAssertEqual(journal.dataset.habits.filter { $0.name == "Drum practice" }.count, 2)
        XCTAssertEqual(journal.dataset.settings, originalSettings)
        let expected = journal.dataset
        try journal.importDataset(imported)
        XCTAssertEqual(journal.dataset, expected)
    }
    func testUserHabitKitExportWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["HABITKIT_TEST_FILE"] else {
            throw XCTSkip("Provide HABITKIT_TEST_FILE to verify the user's original export; synthetic fixtures are tested separately.")
        }
        let preview = try HabitKitImport.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertEqual(preview.dataset.habits.count, 9)
        XCTAssertEqual(preview.dataset.active.count, 6)
        XCTAssertEqual(preview.dataset.days.count, 591)
        XCTAssertEqual(preview.dataset.categories?.count, 12)
        XCTAssertEqual(preview.conflicts.count, 2)
        XCTAssertEqual(preview.dataset.habits.filter { $0.streakGoal?.period == .weekly }.count, 5)
        // Exercise every offered interpretation; the actual choice remains the user's in the preview.
        for resolution in DuplicateDayResolution.allCases {
            let dataset = try preview.resolved(Dictionary(uniqueKeysWithValues: preview.conflicts.map { ($0.id, resolution) }))
            let store = temporaryStore()
            defer { try? FileManager.default.removeItem(at: store.directory) }
            try store.importDataset(dataset)
            let exported = try Backup(dataset: store.read().dataset).encoded()
            try store.deleteAllData()
            try store.restoreBackup(Backup.decode(exported))
            XCTAssertEqual(try store.read().dataset.habits, dataset.habits)
            XCTAssertEqual(try store.read().dataset.days, dataset.days)
            XCTAssertEqual(try store.read().dataset.categories, dataset.categories)
        }
    }
}
