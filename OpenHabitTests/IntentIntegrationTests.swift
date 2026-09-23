import XCTest
import AppIntents
import OpenHabitCore
@testable import OpenHabit

final class IntentIntegrationTests: XCTestCase {
    private func sharedState(localHabitID: UUID) -> SharedHabitState {
        let habit = Habit(id: localHabitID, name: "Shared state fixture")
        let member = SharedMember(name: "Taylor", colorIndex: 0, role: .owner)
        let definition = SharedHabitDefinition(habit: habit, weekStart: .monday)
        return SharedHabitState(
            membership: SharedHabitMembership(
                sharedHabitID: definition.id, localHabitID: localHabitID, memberID: member.id, role: .owner,
                visibleFromDay: nil, zoneName: "Fixture", zoneOwnerName: "Fixture", shareRecordName: "Fixture"
            ),
            snapshot: SharedHabitSnapshot(definition: definition, members: [member])
        )
    }

    func testSharingStoreRemovesMetadataWithoutAMatchingHabit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SharingStore(url: directory.appendingPathComponent("shared-habits.json"))
        let orphan = sharedState(localHabitID: UUID())
        let habit = Habit(name: "Visible Shared Habit")
        var data = Dataset(); data.initialized = true; data.habits = [habit]
        let active = sharedState(localHabitID: habit.id)
        try store.write([orphan, active])

        XCTAssertEqual(Set(try store.read(reconciling: data).keys), [habit.id])
        XCTAssertEqual(try store.read(), [active])
    }

    func testPrivateSyncIgnoresSharedRecordsInItsZone() {
        XCTAssertTrue(CloudSync.isHabitEditRecordName(UUID().uuidString))
        XCTAssertFalse(CloudSync.isHabitEditRecordName("Share-2C0CEC81-AE90-4A4A-8DB9-09C7702B6796"))
        XCTAssertFalse(CloudSync.isHabitEditRecordName("SharedHabit-62AD12F6-7B5E-4257-924A-E9BE49DAD223"))
        XCTAssertFalse(CloudSync.isHabitEditRecordName("SharedProgress-E147B1E0-4BC1-4BB7-90E7-5C38FF816ED4"))
    }

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
