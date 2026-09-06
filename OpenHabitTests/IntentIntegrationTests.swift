import XCTest
import AppIntents
import OpenHabitCore
@testable import OpenHabit

final class IntentIntegrationTests: XCTestCase {
    func testAllShortcutActionsAndWidgetToggleSharePersistentOperations() async throws {
        let habit = Habit(name: "Intent integration fixture", emoji: "💧", target: 3)
        try performLocalEdit { try $0.save(habit) }
        defer { try? performLocalEdit { $0.append(.delete(habit.id)) } }
        let entity = HabitEntity(habit)
        let add = AddCompletionsIntent(); add.habit = ActiveHabitEntity(habit); add.amount = 2
        let addStarted = ContinuousClock.now
        _ = try await add.perform()
        XCTAssertLessThan(ContinuousClock.now - addStarted, .milliseconds(500), "Add Completions must return after local persistence")
        XCTAssertEqual(try sharedStore().read().dataset.day(habit.id, LocalDay.string()).count, 2)
        let toggle = ToggleHabitIntent(id: habit.id)
        _ = try await toggle.perform()
        XCTAssertEqual(try sharedStore().read().dataset.day(habit.id, LocalDay.string()).count, 3)
        let progress = GetTodayProgressIntent(); progress.habit = entity
        let result = try await progress.perform()
        XCTAssertEqual(result.value?.count, 3)
        XCTAssertEqual(result.value?.dailyTarget, 3)
        XCTAssertEqual(result.value?.targetMet, true)
        _ = try await toggle.perform()
        XCTAssertEqual(try sharedStore().read().dataset.day(habit.id, LocalDay.string()).count, 0)
        add.amount = 99; _ = try await add.perform()
        XCTAssertEqual(try sharedStore().read().dataset.day(habit.id, LocalDay.string()).count, 3)
        let remove = RemoveCompletionsIntent(); remove.habit = entity; remove.amount = 99
        _ = try await remove.perform()
        XCTAssertEqual(try sharedStore().read().dataset.day(habit.id, LocalDay.string()).count, 0)
        let note = SetDayNoteIntent(); note.habit = entity; note.text = "From Shortcuts\nSecond line."
        _ = try await note.perform()
        XCTAssertEqual(try sharedStore().read().dataset.day(habit.id, LocalDay.string()).note, note.text)
        note.date = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        do { _ = try await note.perform(); XCTFail("Future date was accepted") } catch {}
        try performLocalEdit { $0.append(.archive(habit.id, true)) }
        do { _ = try await add.perform(); XCTFail("Archived Habit accepted additions") } catch {}
        let suggestions = try await ActiveHabitQuery().suggestedEntities()
        let resolved = try await HabitQuery().entities(for: [habit.id])
        XCTAssertFalse(suggestions.contains { $0.id == habit.id })
        XCTAssertEqual(resolved.first?.id, habit.id)
    }
}
