import XCTest
import OpenHabitCore
@testable import OpenHabitWatch

@MainActor
final class WatchModelTests: XCTestCase {
    private var directory: URL!
    private var store: LocalStore!
    private let now = LocalDay.date("2026-09-29")!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = LocalStore(directory: directory)
        try store.transaction { $0.seedIfEmpty(now: now) }
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testCompletionPersistsAndReloadIncludesPhoneEdits() throws {
        let model = WatchModel(store: store)
        let habit = model.data.active.first { $0.target > 1 }!
        model.complete(habit.id, now: now)
        XCTAssertEqual(try store.read().dataset.day(habit.id, LocalDay.string(now)).count, 2)
        try store.transaction { try $0.add(habit.id, day: LocalDay.string(now), now: now) }
        model.reload()
        XCTAssertEqual(model.data.day(habit.id, LocalDay.string(now)).count, 3)
        XCTAssertEqual(WatchModel(store: store).data.day(habit.id, LocalDay.string(now)).count, 3)
        XCTAssertNil(model.error)
    }

    func testCompletedHabitRemovesOneInsteadOfClearingTheDay() throws {
        let model = WatchModel(store: store)
        let habit = model.data.active.first { $0.target > 1 }!
        try store.transaction { try $0.setCount(habit.id, day: LocalDay.string(now), count: habit.target, now: now) }
        model.complete(habit.id, now: now)
        XCTAssertEqual(model.data.day(habit.id, LocalDay.string(now)).count, habit.target - 1)
    }

    func testCompletionAfterMidnightRecordsTheNewDay() throws {
        let model = WatchModel(store: store)
        let habit = model.data.active.first { $0.target == 1 }!
        try store.transaction { try $0.setCount(habit.id, day: LocalDay.string(now), count: 0, now: now) }
        model.complete(habit.id, now: now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        model.complete(habit.id, now: tomorrow)
        XCTAssertEqual(try store.read().dataset.day(habit.id, LocalDay.string(now)).count, 1)
        XCTAssertEqual(try store.read().dataset.day(habit.id, LocalDay.string(tomorrow)).count, 1)
    }

    func testReplacementReloadsAndEmptyStoreDoesNotSeedWatchHabits() throws {
        let empty = LocalStore(directory: directory.appendingPathComponent("Empty"))
        XCTAssertTrue(WatchModel(store: empty).data.habits.isEmpty)
        let model = WatchModel(store: store)
        model.complete(model.data.active[0].id, now: now)
        try store.deleteAllData()
        model.reload()
        XCTAssertTrue(model.data.active.isEmpty)
    }
}
