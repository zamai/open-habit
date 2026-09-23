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
    func dataImportPlan(_ data: Data, source: DataImportSource = .habitKit) throws -> DataImportPlan {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        return try DataImport.plan(data, source: source, store: store)
    }
    func importedDataset(
        _ data: Data,
        source: DataImportSource = .habitKit,
        choices: [String: DuplicateDayResolution] = [:]
    ) throws -> Dataset {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let plan = try DataImport.plan(data, source: source, store: store)
        return try DataImport.apply(plan, mode: .addNewHabits, conflictChoices: choices, to: store, activeSharedHabitIDs: []).dataset
    }
    func assertEveryConflictResolutionRoundTrips(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws {
        for resolution in DuplicateDayResolution.allCases {
            let store = temporaryStore()
            defer { try? FileManager.default.removeItem(at: store.directory) }
            let plan = try DataImport.plan(data, source: .habitKit, store: store)
            let choices = Dictionary(uniqueKeysWithValues: plan.conflicts.map { ($0.id, resolution) })
            let dataset = try DataImport.apply(
                plan,
                mode: .addNewHabits,
                conflictChoices: choices,
                to: store,
                activeSharedHabitIDs: []
            ).dataset
            let exported = try Backup(dataset: dataset).encoded()
            try store.deleteAllData()
            let restore = try DataImport.plan(exported, source: .openHabit, store: store)
            _ = try DataImport.apply(restore, mode: .replaceAllData, conflictChoices: [:], to: store, activeSharedHabitIDs: [])
            XCTAssertEqual(try store.read().dataset.habits, dataset.habits, file: file, line: line)
            XCTAssertEqual(try store.read().dataset.days, dataset.days, file: file, line: line)
            XCTAssertEqual(try store.read().dataset.categories, dataset.categories, file: file, line: line)
        }
    }
    func testDataImportPlanAnalyzesHabitKitFile() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let plan = try DataImport.plan(fixture(), source: .habitKit, store: store)

        XCTAssertEqual(plan.dataset.habits.count, 3)
        XCTAssertEqual(plan.newHabits.count, 3)
        XCTAssertEqual(plan.newCategories.map(\.name), ["Practice"])
        XCTAssertEqual(plan.suggestedMode, .addNewHabits)
    }
    func testDataImportAddsNewHabitsAndReturnsCommittedDataset() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let plan = try DataImport.plan(fixture(), source: .habitKit, store: store)

        let outcome = try DataImport.apply(
            plan,
            mode: .addNewHabits,
            conflictChoices: [:],
            to: store,
            activeSharedHabitIDs: []
        )

        XCTAssertTrue(outcome.changed)
        XCTAssertEqual(outcome.dataset.habits.count, 3)
        XCTAssertEqual(outcome.dataset.categories?.map(\.name), ["Practice"])
    }
    func testDataImportRebasesAddModeAndSkipsRecoveryForAStaleNoOp() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let stalePlan = try DataImport.plan(fixture(), source: .habitKit, store: store)
        let competingPlan = try DataImport.plan(fixture(), source: .habitKit, store: store)
        _ = try DataImport.apply(competingPlan, mode: .addNewHabits, conflictChoices: [:], to: store, activeSharedHabitIDs: [])
        let recoveryCount = try store.recoveryBackups().count

        let outcome = try DataImport.apply(stalePlan, mode: .addNewHabits, conflictChoices: [:], to: store, activeSharedHabitIDs: [])

        XCTAssertFalse(outcome.changed)
        XCTAssertEqual(outcome.dataset.habits.count, 3)
        XCTAssertEqual(try store.recoveryBackups().count, recoveryCount)
    }
    func testDataImportRebasesAddModeWhenSourceHabitsBecomeAvailable() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let firstPlan = try DataImport.plan(fixture(), source: .habitKit, store: store)
        _ = try DataImport.apply(firstPlan, mode: .addNewHabits, conflictChoices: [:], to: store, activeSharedHabitIDs: [])
        let stalePlan = try DataImport.plan(fixture(), source: .habitKit, store: store)
        XCTAssertTrue(stalePlan.newHabits.isEmpty)
        try store.deleteAllData()

        let refreshedPlan = try DataImport.refresh(stalePlan, store: store)
        XCTAssertEqual(refreshedPlan.newHabits.count, 3)
        XCTAssertEqual(refreshedPlan.suggestedMode, .addNewHabits)

        let outcome = try DataImport.apply(stalePlan, mode: .addNewHabits, conflictChoices: [:], to: store, activeSharedHabitIDs: [])

        XCTAssertTrue(outcome.changed)
        XCTAssertEqual(outcome.dataset.habits.count, 3)
    }
    func testDataImportRejectsReplaceWhenASharedHabitBecameActiveAfterPlanning() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.transaction { $0.seedIfEmpty() }
        let original = try store.read().dataset
        let plan = try DataImport.plan(fixture(), source: .habitKit, store: store)

        XCTAssertThrowsError(try DataImport.apply(
            plan,
            mode: .replaceAllData,
            conflictChoices: [:],
            to: store,
            activeSharedHabitIDs: [UUID()]
        )) { error in
            XCTAssertEqual(error.localizedDescription, "Leave or stop sharing every Shared Habit before replacing all data.")
        }
        XCTAssertEqual(try store.read().dataset, original)
        XCTAssertTrue(try store.recoveryBackups().isEmpty)
    }
    func testReplaceAllDataCreatesANewGenerationWhenTheDatasetMatches() throws {
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        try store.transaction { $0.seedIfEmpty() }
        let before = try store.read()
        let backup = try Backup(dataset: before.dataset).encoded()
        let plan = try DataImport.plan(backup, source: .openHabit, store: store)

        let outcome = try DataImport.apply(
            plan,
            mode: .replaceAllData,
            conflictChoices: [:],
            to: store,
            activeSharedHabitIDs: []
        )

        XCTAssertTrue(outcome.changed)
        XCTAssertEqual(outcome.dataset, before.dataset)
        XCTAssertNotEqual(try store.read().generation, before.generation)
        XCTAssertEqual(try store.recoveryBackups().count, 1)
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
        let plan = try DataImport.plan(fixture(), source: .habitKit, store: store)
        XCTAssertEqual(plan.dataset.habits.count, 3)
        XCTAssertEqual(plan.dataset.habits[0].streakGoal, StreakGoal(period: .weekly, target: 3))
        XCTAssertEqual(plan.dataset.habits[1].target, 2)
        XCTAssertEqual(plan.dataset.categories?.first?.name, "Practice")
        XCTAssertEqual(plan.dataset.habits[0].categoryIDs, plan.dataset.categories?.map(\.id))
        XCTAssertEqual(plan.dataset.day(plan.dataset.habits[1].id, "2025-01-21").note, "First note\nSecond line")
        _ = try DataImport.apply(plan, mode: .addNewHabits, conflictChoices: [:], to: store, activeSharedHabitIDs: [])
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
        _ = try DataImport.apply(plan, mode: .addNewHabits, conflictChoices: [:], to: store, activeSharedHabitIDs: [])
        XCTAssertEqual(try store.read().dataset, expected, "Reimport must preserve local edits and avoid duplicate counts")
        let exported = try Backup(dataset: expected).encoded()
        try store.deleteAllData()
        XCTAssertTrue(try store.read().dataset.habits.isEmpty)
        XCTAssertEqual(try Backup.decode(Data(contentsOf: XCTUnwrap(store.recoveryBackups().first))).dataset, expected)
        let backupPlan = try DataImport.plan(exported, source: .openHabit, store: store)
        _ = try DataImport.apply(backupPlan, mode: .addNewHabits, conflictChoices: [:], to: store, activeSharedHabitIDs: [])
        XCTAssertEqual(try store.read().dataset.habits, expected.habits)
        XCTAssertEqual(try store.read().dataset.days, expected.days)
        XCTAssertEqual(try store.read().dataset.categories, expected.categories)
        _ = try DataImport.apply(backupPlan, mode: .replaceAllData, conflictChoices: [:], to: store, activeSharedHabitIDs: [])
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
        let plan = try dataImportPlan(data)
        let conflict = try XCTUnwrap(plan.conflicts.first)
        XCTAssertThrowsError(try importedDataset(data))
        XCTAssertEqual(try importedDataset(data, choices: [conflict.id: .sum]).days[conflict.id]?.count, 3)
        XCTAssertEqual(try importedDataset(data, choices: [conflict.id: .latest]).days[conflict.id]?.count, 2)
        XCTAssertEqual(try importedDataset(data, choices: [conflict.id: .maximum]).days[conflict.id]?.count, 2)
        XCTAssertEqual(plan.dataset.days[conflict.id]?.note, "Earlier note\n\nAnother note")
    }
    func testConcurrentImportsMergeOnceAndNeverResurrectDeletedHabits() throws {
        let imported = try importedDataset(fixture())
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
        let plan = try DataImport.plan(fixture(), source: .habitKit, store: store)
        let original = try Data(contentsOf: file)
        try Data("blocking file".utf8).write(to: store.recoveryDirectory)
        XCTAssertThrowsError(try DataImport.apply(plan, mode: .addNewHabits, conflictChoices: [:], to: store, activeSharedHabitIDs: []))
        XCTAssertThrowsError(try DataImport.apply(plan, mode: .replaceAllData, conflictChoices: [:], to: store, activeSharedHabitIDs: []))
        XCTAssertThrowsError(try store.deleteAllData())
        XCTAssertEqual(try Data(contentsOf: file), original)
        var invalid = plan.dataset; invalid.habits.append(plan.dataset.habits[0])
        XCTAssertThrowsError(try DataImport.plan(Backup(dataset: invalid).encoded(), source: .openHabit, store: store))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
    func testUnsupportedAndBrokenSourceFailsWithoutSilentLoss() throws {
        for field in ["isInverse", "name"] {
            let data = try changedFixture { json in
                var habits = json["habits"] as! [[String: Any]]
                habits[0][field] = field == "isInverse" ? true : String(repeating: "x", count: 61)
                json["habits"] = habits
            }
            XCTAssertThrowsError(try dataImportPlan(data))
        }
        let duplicate = try changedFixture { json in
            var records = json["completions"] as! [[String: Any]]; records.append(records[0]); json["completions"] = records
        }
        XCTAssertThrowsError(try dataImportPlan(duplicate))
        let orphan = try changedFixture { json in
            var mappings = json["categoryMappings"] as! [[String: Any]]; mappings[0]["categoryId"] = UUID().uuidString; json["categoryMappings"] = mappings
        }
        XCTAssertThrowsError(try dataImportPlan(orphan))
        let current = try Backup(dataset: Dataset()).encoded()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: current) as? [String: Any])
        XCTAssertEqual(json["format"] as? String, "open-habit")
        json["format"] = "another-app"
        XCTAssertThrowsError(try dataImportPlan(JSONSerialization.data(withJSONObject: json), source: .openHabit))
        XCTAssertThrowsError(try dataImportPlan(current))
    }
    func testMissingHabitErrorIdentifiesTheSourceRecord() throws {
        for (section, recordType) in [("completions", "completion"), ("intervals", "interval")] {
            let missingID = UUID()
            let data = try changedFixture { json in
                var records = json[section] as! [[String: Any]]
                records[0]["habitId"] = missingID.uuidString
                json[section] = records
            }
            XCTAssertThrowsError(try dataImportPlan(data)) { error in
                XCTAssertTrue(error.localizedDescription.contains("HabitKit \(recordType)"))
                XCTAssertTrue(error.localizedDescription.contains(missingID.uuidString))
            }
        }
    }
    func testCategoryAssignmentsForAbsentHabitsAreDisclosedAndSkipped() throws {
        let data = try changedFixture { json in
            for section in ["habits", "completions", "intervals"] {
                var records = json[section] as! [[String: Any]]
                records.removeLast()
                json[section] = records
            }
        }
        let plan = try dataImportPlan(data)
        XCTAssertEqual(plan.dataset.habits.count, 2)
        XCTAssertEqual(plan.dataset.days.count, 2)
        XCTAssertEqual(plan.dataset.categories?.count, 1)
        XCTAssertEqual(plan.warnings.filter { $0.contains("Category assignments for Habits absent") },
                       ["Category assignments for Habits absent from this export will be skipped (count: 1)."])
        XCTAssertEqual(plan.dataset.habits.map(\.categoryIDs), [plan.dataset.categories?.map(\.id), plan.dataset.categories?.map(\.id)])
        try importedDataset(data).validate()
    }
    func testVersion2BackupWithoutFormatIdentifierStillDecodes() throws {
        let current = Backup(dataset: try dataImportPlan(fixture()).dataset)
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
        let imported = try importedDataset(data)
        XCTAssertEqual(imported.day(imported.habits[0].id, "2025-01-20"), HabitDay(count: 0, note: "An empty day still has a note"))
        XCTAssertEqual(imported.day(imported.habits[1].id, "2025-07-21").count, 2)
        XCTAssertEqual(imported.day(imported.habits[2].id, "2025-07-21").count, 3)
        XCTAssertEqual(try Backup.decode(Backup(dataset: imported).encoded()).dataset, imported)
    }
    func testNamesDoNotDetermineIdentityAndRepeatedImportPreservesPreferences() throws {
        var journal = Journal()
        try journal.save(Habit(name: "Drum practice"))
        let originalSettings = journal.dataset.settings
        let imported = try importedDataset(fixture())
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
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let plan = try dataImportPlan(data)
        XCTAssertEqual(plan.dataset.habits.count, 9)
        XCTAssertEqual(plan.dataset.active.count, 6)
        XCTAssertEqual(plan.dataset.days.count, 591)
        XCTAssertEqual(plan.dataset.categories?.count, 12)
        XCTAssertEqual(plan.conflicts.count, 2)
        XCTAssertEqual(plan.dataset.habits.filter { $0.streakGoal?.period == .weekly }.count, 5)
        // Exercise every offered interpretation; the actual choice remains the user's in the preview.
        try assertEveryConflictResolutionRoundTrips(data)
    }
    func testUserHabitKitExportWithStaleAssignmentsWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["HABITKIT_ORPHAN_TEST_FILE"] else {
            throw XCTSkip("Provide HABITKIT_ORPHAN_TEST_FILE to verify the user's export with stale category assignments.")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let plan = try dataImportPlan(data)
        XCTAssertEqual(plan.dataset.habits.count, 5)
        XCTAssertEqual(plan.dataset.active.count, 5)
        XCTAssertEqual(plan.dataset.days.count, 540)
        XCTAssertEqual(plan.dataset.categories?.count, 12)
        XCTAssertEqual(plan.dataset.habits.reduce(0) { $0 + ($1.categoryIDs?.count ?? 0) }, 2)
        XCTAssertEqual(plan.conflicts.count, 1)
        XCTAssertTrue(plan.warnings.contains("Category assignments for Habits absent from this export will be skipped (count: 3)."))
        try assertEveryConflictResolutionRoundTrips(data)
    }
    func testSeptember22ExportImportsFreshButDoesNotRefreshKnownHabitsWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["HABITKIT_SEPT22_TEST_FILE"] else {
            throw XCTSkip("Provide HABITKIT_SEPT22_TEST_FILE to verify the September 22 export.")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let store = temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let plan = try DataImport.plan(data, source: .habitKit, store: store)
        XCTAssertEqual(plan.dataset.habits.count, 5)
        XCTAssertEqual(plan.dataset.days.count, 544)
        XCTAssertEqual(plan.conflicts.count, 1)
        let sport = try XCTUnwrap(plan.dataset.habits.first { $0.name == "Sport" })
        let choices: [String: DuplicateDayResolution] = [plan.conflicts[0].id: .sum]
        let dataset = try DataImport.apply(plan, mode: .addNewHabits, conflictChoices: choices, to: store, activeSharedHabitIDs: []).dataset
        XCTAssertEqual(dataset.day(sport.id, "2025-09-30").count, 2)
        XCTAssertEqual(try store.read().dataset.habits.count, 5)
        XCTAssertEqual(try store.read().dataset.days.count, 544)
        let before = try store.read().dataset
        _ = try DataImport.apply(plan, mode: .addNewHabits, conflictChoices: choices, to: store, activeSharedHabitIDs: [])
        XCTAssertEqual(try store.read().dataset, before)
        try store.transaction { journal in
            for habit in dataset.habits { journal.append(.delete(habit.id)) }
        }
        XCTAssertTrue(try store.read().dataset.habits.isEmpty)
        _ = try DataImport.apply(plan, mode: .addNewHabits, conflictChoices: choices, to: store, activeSharedHabitIDs: [])
        XCTAssertTrue(try store.read().dataset.habits.isEmpty, "Add mode must not resurrect explicitly deleted Habit IDs")
        let backup = try Backup(dataset: dataset).encoded()
        let restore = try DataImport.plan(backup, source: .openHabit, store: store)
        _ = try DataImport.apply(restore, mode: .replaceAllData, conflictChoices: [:], to: store, activeSharedHabitIDs: [])
        XCTAssertEqual(try store.read().dataset.habits, dataset.habits)
        XCTAssertEqual(try store.read().dataset.days, dataset.days)
    }
}
