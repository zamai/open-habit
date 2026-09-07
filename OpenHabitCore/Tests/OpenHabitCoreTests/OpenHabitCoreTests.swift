import XCTest
@testable import OpenHabitCore

final class OpenHabitCoreTests: XCTestCase {
    func testCustomColorPersistsAndLegacyHabitStillDecodes() throws {
        var habit = Habit(name: "Water")
        let legacy = try JSONEncoder().encode(habit)
        XCTAssertNil(try JSONDecoder().decode(Habit.self, from: legacy).customColorRGB)
        habit.customColorRGB = 0x123ABC
        try habit.validate()
        XCTAssertEqual(try JSONDecoder().decode(Habit.self, from: JSONEncoder().encode(habit)), habit)
        var journal = Journal()
        try journal.save(habit)
        XCTAssertEqual(journal.dataset.habit(habit.id)?.customColorRGB, 0x123ABC)
        habit.customColorRGB = 0x1000000
        XCTAssertThrowsError(try habit.validate())
    }

    let day = "2026-09-05"
    var now: Date { LocalDay.date(day)! }
    func fixture(target: Int = 3) throws -> (Journal, Habit) {
        var journal = Journal()
        let habit = Habit(name: "Water", emoji: "💧", target: target)
        try journal.save(habit)
        return (journal, habit)
    }
    func testCompletionControlsToggleAndCap() throws {
        for target in [1, 3, 99] {
            var (journal, habit) = try fixture(target: target)
            for count in 1...target {
                try journal.toggle(habit.id, day: day, now: now)
                XCTAssertEqual(journal.dataset.day(habit.id, day).count, count)
            }
            try journal.add(habit.id, day: day, amount: Int.max, now: now)
            XCTAssertEqual(journal.dataset.day(habit.id, day).count, target)
            try journal.toggle(habit.id, day: day, now: now)
            XCTAssertEqual(journal.dataset.day(habit.id, day).count, 0)
        }
    }
    func testDistinctConcurrentAdditionsMergeAndRetriesDoNotDuplicate() throws {
        let (base, habit) = try fixture()
        var first = base; var second = base
        try first.add(habit.id, day: day, now: now)
        try second.add(habit.id, day: day, now: now)
        first.merge(second.edits); second.merge(first.edits); first.merge(second.edits)
        XCTAssertEqual(first.dataset.day(habit.id, day).count, 2)
        XCTAssertEqual(first.dataset, second.dataset)
        try first.add(habit.id, day: day, amount: 2, now: now)
        try second.add(habit.id, day: day, amount: 2, now: now)
        first.merge(second.edits); second.merge(first.edits)
        XCTAssertEqual(first.dataset.day(habit.id, day).count, 3)
        XCTAssertEqual(first.dataset, second.dataset)
    }
    func testRemovalAndCorrectionNeverGoNegative() throws {
        var (journal, habit) = try fixture()
        try journal.remove(habit.id, day: day, amount: Int.max, now: now)
        XCTAssertEqual(journal.dataset.day(habit.id, day).count, 0)
        XCTAssertThrowsError(try journal.setCount(habit.id, day: day, count: -1, now: now))
        XCTAssertThrowsError(try journal.add(habit.id, day: day, amount: 0, now: now))
    }
    func testTargetChangeReinterpretsHistoryWithoutDestroyingCounts() throws {
        var (journal, habit) = try fixture()
        try journal.setCount(habit.id, day: day, count: 3, now: now)
        var edited = habit; edited.target = 5
        try journal.save(edited)
        XCTAssertEqual(journal.dataset.day(habit.id, day).progress(target: 5), 0.6, accuracy: 0.001)
        edited.target = 1; try journal.save(edited)
        XCTAssertEqual(journal.dataset.day(habit.id, day).count, 3)
        try journal.toggle(habit.id, day: day, now: now)
        XCTAssertEqual(journal.dataset.day(habit.id, day).count, 0)
    }
    func testArchiveSurvivesStalePropertyEditsAndDeletionCannotResurrect() throws {
        var (first, habit) = try fixture(); var second = first
        first.append(.archive(habit.id, true))
        var edited = habit; edited.name = "More water"; try second.save(edited)
        first.merge(second.edits)
        XCTAssertTrue(first.dataset.habit(habit.id)!.archived)
        XCTAssertThrowsError(try first.add(habit.id, day: day, now: now))
        try first.setNote(habit.id, day: day, note: "A note", now: now)
        first.append(.delete(habit.id))
        try second.save(edited); try second.add(habit.id, day: day, now: now)
        first.merge(second.edits)
        XCTAssertNil(first.dataset.habit(habit.id))
        XCTAssertTrue(first.dataset.days.isEmpty)
    }
    func testRestoreFencesOutOldOfflineEditsAndDoesNotReseed() throws {
        var (first, habit) = try fixture(); var offline = first
        var empty = Dataset(); empty.initialized = true
        try first.restore(Backup(dataset: empty))
        try offline.add(habit.id, day: day, now: now)
        first.merge(offline.edits); offline.merge(first.edits)
        first.seedIfEmpty(); offline.seedIfEmpty()
        XCTAssertTrue(first.dataset.habits.isEmpty)
        XCTAssertEqual(first.dataset, offline.dataset)
        let newHabit = Habit(name: "Read")
        try first.save(newHabit); offline.merge(first.edits)
        XCTAssertEqual(offline.dataset.habits, [newHabit])
    }
    func testSeedExactlyOnceAndSeedMergeKeepsSingleSet() throws {
        var first = Journal(); var second = Journal()
        first.seedIfEmpty(now: now); second.seedIfEmpty(now: now)
        first.merge(second.edits); second.merge(first.edits)
        XCTAssertEqual(first.dataset.habits.count, 3)
        XCTAssertEqual(first.dataset.days.values.map(\.count).reduce(0, +), 1)
        for habit in first.dataset.habits { first.append(.delete(habit.id)) }
        first.seedIfEmpty(now: now)
        XCTAssertTrue(first.dataset.habits.isEmpty)
    }
    func testDateAndNoteRules() throws {
        var (journal, habit) = try fixture()
        XCTAssertThrowsError(try journal.add(habit.id, day: "2026-09-06", now: now))
        XCTAssertThrowsError(try journal.setNote(habit.id, day: "2026-09-06", note: "Future", now: now))
        XCTAssertThrowsError(try journal.setCount(habit.id, day: "2026-02-30", count: 1, now: now))
        XCTAssertThrowsError(try journal.setNote(habit.id, day: day, note: String(repeating: "a", count: 501), now: now))
        try journal.setNote(habit.id, day: "2000-01-01", note: "Before creation\nStill valid.", now: now)
        XCTAssertEqual(journal.dataset.day(habit.id, "2000-01-01").note, "Before creation\nStill valid.")
        let instant = Date(timeIntervalSince1970: 1_783_210_000)
        let date = LocalDay.string(instant, timeZone: TimeZone(secondsFromGMT: -12 * 3600)!)
        try journal.setCount(habit.id, day: date, count: 1, now: now)
        XCTAssertEqual(journal.dataset.day(habit.id, date).count, 1)
        XCTAssertTrue(journal.dataset.days.keys.contains(Dataset.key(habit.id, date)))
    }
    func testBackupFullFidelityAndFutureVersionRejected() throws {
        var (journal, habit) = try fixture()
        try journal.setNote(habit.id, day: day, note: "Line 1\n🌱 Line 2", now: now)
        try journal.setCount(habit.id, day: day, count: 9, now: now)
        journal.append(.archive(habit.id, true))
        var settings = Settings(); settings.appearance = .dark; settings.weekStart = .monday; settings.examplesDismissed = true
        journal.append(.settings(settings))
        let backup = try Backup.decode(Backup(dataset: journal.dataset).encoded())
        XCTAssertEqual(backup.dataset, journal.dataset)
        XCTAssertThrowsError(try Backup.decode(Data("{\"formatVersion\":999}".utf8)))
        var invalid = journal.dataset; invalid.habits.append(habit)
        XCTAssertThrowsError(try Backup.decode(Backup(dataset: invalid).encoded()))
    }
    func testBackupISO8601DatesPreserveFractionalSeconds() throws {
        var data = Dataset()
        let createdAt = Date(timeIntervalSinceReferenceDate: 810123456.1234567)
        data.habits = [Habit(name: "Water", createdAt: createdAt)]
        let original = Backup(dataset: data)
        let encoded = try original.encoded()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(json["formatVersion"] as? Int, 2)
        XCTAssertTrue(try XCTUnwrap(json["exportedAt"] as? String).hasSuffix("Z"))
        let dataset = try XCTUnwrap(json["dataset"] as? [String: Any])
        let habits = try XCTUnwrap(dataset["habits"] as? [[String: Any]])
        XCTAssertEqual(habits[0]["createdAt"] as? String, "2026-09-03T10:17:36.123456717Z")
        let decoded = try Backup.decode(encoded)
        XCTAssertEqual(decoded.dataset, data)
        XCTAssertEqual(decoded.exportedAt, original.exportedAt)
        let malformed = String(decoding: encoded, as: UTF8.self)
            .replacingOccurrences(of: "2026-09-03T10:17:36.123456717Z", with: "not-a-date")
        XCTAssertThrowsError(try Backup.decode(Data(malformed.utf8)))
    }

    func testLegacyNumericBackupStillRestoresAndReexportsAsVersion2() throws {
        let legacy = Data("""
        {"formatVersion":1,"exportedAt":810123456.25,"dataset":{
          "initialized":true,"settings":{"appearance":"dark","weekStart":"monday","examplesDismissed":true},
          "habits":[{"id":"00000000-0000-0000-0000-000000000001","name":"Water","emoji":"💧",
            "detail":"Drink water","color":"blue","target":3,"createdAt":810123456.125,"archived":true}],
          "days":{"00000000-0000-0000-0000-000000000001/2026-09-03":{"count":2,"note":"Keep going"}}}}
        """.utf8)
        let backup = try Backup.decode(legacy)
        XCTAssertEqual(backup.exportedAt, Date(timeIntervalSinceReferenceDate: 810123456.25))
        XCTAssertEqual(backup.dataset.habits[0].createdAt, Date(timeIntervalSinceReferenceDate: 810123456.125))
        var journal = Journal()
        try journal.restore(backup)
        XCTAssertEqual(journal.dataset, backup.dataset)
        let reexported = try Backup.decode(Backup(dataset: journal.dataset).encoded())
        XCTAssertEqual(reexported.formatVersion, 2)
        XCTAssertEqual(reexported.dataset, backup.dataset)
    }

    func testFailedTransactionPreservesExactOriginalAndAtomicRestore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalStore(directory: directory)
        try store.transaction { $0.seedIfEmpty(now: now) }
        let original = try Data(contentsOf: directory.appendingPathComponent("journal.json"))
        XCTAssertThrowsError(try store.transaction { journal in
            journal.append(.replace(Dataset()))
            throw HabitError.invalidBackup("Simulated failure")
        })
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("journal.json")), original)
        try store.transaction { try $0.restore(Backup(dataset: Dataset())) }
        XCTAssertTrue(try store.read().dataset.initialized)
        XCTAssertTrue(try store.read().dataset.habits.isEmpty)
    }
    func testSharedStoreConcurrentWritersDoNotLoseUpdates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalStore(directory: directory)
        let habit = Habit(name: "Water", target: 99)
        try store.transaction { try $0.save(habit) }
        let date = day; let clock = now
        DispatchQueue.concurrentPerform(iterations: 40) { _ in
            do { try store.transaction { try $0.add(habit.id, day: date, now: clock) } }
            catch { XCTFail(error.localizedDescription) }
        }
        XCTAssertEqual(try store.read().dataset.day(habit.id, day).count, 40)
    }
    func testDeletionAndReplacementErasePayloadsButKeepCausality() throws {
        var (journal, habit) = try fixture()
        try journal.setNote(habit.id, day: day, note: "Private note", now: now)
        journal.append(.delete(habit.id))
        var encoded = String(data: try JSONEncoder().encode(journal), encoding: .utf8)!
        XCTAssertFalse(encoded.contains("Private note"))
        XCTAssertFalse(encoded.contains("Water"))
        XCTAssertTrue(encoded.contains(habit.id.uuidString))
        var fresh = Dataset(); fresh.initialized = true
        try journal.restore(Backup(dataset: fresh))
        encoded = String(data: try JSONEncoder().encode(journal), encoding: .utf8)!
        XCTAssertFalse(encoded.contains(habit.id.uuidString))
        journal.seedIfEmpty()
        XCTAssertTrue(journal.dataset.habits.isEmpty)
    }
    func testDailyStreakKeepsAnIncompleteCurrentDayOpen() {
        let habit = Habit(name: "Run", target: 1, streakGoal: StreakGoal(period: .daily), createdAt: LocalDay.date("2026-09-01")!)
        var data = Dataset(); data.habits = [habit]
        for day in ["2026-09-04", "2026-09-05", "2026-09-06"] {
            data.days[Dataset.key(habit.id, day)] = HabitDay(count: 1)
        }
        XCTAssertEqual(data.currentStreak(for: habit, asOf: LocalDay.date("2026-09-07")!), 3)
        data.days[Dataset.key(habit.id, "2026-09-07")] = HabitDay(count: 1)
        XCTAssertEqual(data.currentStreak(for: habit, asOf: LocalDay.date("2026-09-07")!), 4)
    }
    func testWeeklyStreakUsesCompletedDaysAndVisibleMonthCountsCompletions() {
        let habit = Habit(name: "Run", target: 1, streakGoal: StreakGoal(period: .weekly, target: 3), createdAt: LocalDay.date("2026-08-24")!)
        var data = Dataset(); data.habits = [habit]; data.settings.weekStart = .monday
        for day in ["2026-08-24", "2026-08-26", "2026-08-28", "2026-08-31", "2026-09-02", "2026-09-04"] {
            data.days[Dataset.key(habit.id, day)] = HabitDay(count: day == "2026-09-02" ? 2 : 1)
        }
        XCTAssertEqual(data.currentStreak(for: habit, asOf: LocalDay.date("2026-09-07")!), 2)
        for day in ["2026-09-07", "2026-09-09", "2026-09-11"] {
            data.days[Dataset.key(habit.id, day)] = HabitDay(count: 1)
        }
        XCTAssertEqual(data.completedDays(for: habit, inWeekContaining: LocalDay.date("2026-09-10")!), 3)
        XCTAssertEqual(data.currentStreak(for: habit, asOf: LocalDay.date("2026-09-11")!), 3)
        XCTAssertEqual(data.completionTotal(for: habit.id, inMonthContaining: LocalDay.date("2026-09-01")!), 6)
    }
    func testHabitValidation() {
        for emoji in ["a", "1", "", "🌱💧"] {
            XCTAssertThrowsError(try Habit(name: "Valid", emoji: emoji).validate())
        }
        for emoji in ["🌱", "👩🏽‍💻", "🇵🇱", "❤️", "1️⃣"] {
            XCTAssertNoThrow(try Habit(name: "Valid", emoji: emoji).validate())
        }
        XCTAssertThrowsError(try Habit(name: "   ").validate())
        XCTAssertThrowsError(try Habit(name: String(repeating: "a", count: 61)).validate())
        XCTAssertThrowsError(try Habit(name: "Run", streakGoal: StreakGoal(period: .weekly, target: 8)).validate())
    }
}
