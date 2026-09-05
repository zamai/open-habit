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
    func testHabitValidation() {
        for emoji in ["a", "1", "", "🌱💧"] {
            XCTAssertThrowsError(try Habit(name: "Valid", emoji: emoji).validate())
        }
        for emoji in ["🌱", "👩🏽‍💻", "🇵🇱", "❤️", "1️⃣"] {
            XCTAssertNoThrow(try Habit(name: "Valid", emoji: emoji).validate())
        }
        XCTAssertThrowsError(try Habit(name: "   ").validate())
        XCTAssertThrowsError(try Habit(name: String(repeating: "a", count: 61)).validate())
    }
}
