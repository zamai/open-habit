import XCTest
@testable import OpenHabitCore

final class CounterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)
    private var today: String { LocalDay.string(now) }

    private func journal(with habit: Habit) throws -> Journal {
        var journal = Journal()
        try journal.save(habit)
        return journal
    }

    func testTapAddsStepAndAnyAmountExtendsStreak() throws {
        let habit = Habit(name: "Pushups", streakGoal: StreakGoal(period: .daily), counter: Counter(step: 30, unit: "pushups"))
        var journal = try journal(with: habit)
        for _ in 0..<4 { try journal.toggle(habit.id, day: today, now: now) }
        XCTAssertEqual(journal.dataset.day(habit.id, today).count, 120)
        XCTAssertEqual(journal.dataset.currentStreak(for: habit, asOf: now), 1)
    }

    func testDailyStreakNeedsTheGoalAmountEachDay() throws {
        let habit = Habit(name: "Read", streakGoal: StreakGoal(period: .daily, amount: 25), counter: Counter(step: 5, unit: "pages"))
        var journal = try journal(with: habit)
        let days = (0..<4).map { LocalDay.string(now.addingTimeInterval(Double(-$0) * 86_400)) }
        // Today is unfinished at 10 pages; the three days before reach 25, 40 and 20.
        for (day, amount) in zip(days, [10, 25, 40, 20]) { try journal.setCount(habit.id, day: day, count: amount, now: now) }
        XCTAssertEqual(journal.dataset.currentStreak(for: habit, asOf: now), 2, "An unfinished today keeps yesterday's streak")
        try journal.setCount(habit.id, day: days[0], count: 25, now: now)
        XCTAssertEqual(journal.dataset.currentStreak(for: habit, asOf: now), 3)
    }

    func testWeeklyStreakSumsAmountsAcrossTheWeek() throws {
        var habit = Habit(name: "Read", streakGoal: StreakGoal(period: .weekly, target: 3, amount: 100), counter: Counter(step: 5, unit: "pages"))
        var journal = Journal()
        var settings = Settings(); settings.weekStart = .monday
        journal.append(.settings(settings))
        try journal.save(habit)
        let monday = try XCTUnwrap(LocalDay.date("2026-10-19"))
        func day(_ offset: Int) -> String { LocalDay.string(monday.addingTimeInterval(Double(offset) * 86_400)) }
        let sunday = monday.addingTimeInterval(6 * 86_400)
        // Previous week: one big day of 100. This week: 30 + 30 + 40 spread over three days.
        try journal.setCount(habit.id, day: day(-3), count: 100, now: sunday)
        for (offset, amount) in [(0, 30), (2, 30), (5, 30)] { try journal.setCount(habit.id, day: day(offset), count: amount, now: sunday) }
        XCTAssertEqual(journal.dataset.weekTotal(for: habit, inWeekContaining: sunday), 90)
        XCTAssertEqual(journal.dataset.currentStreak(for: habit, asOf: sunday), 1, "The unfinished week keeps last week's streak")
        try journal.setCount(habit.id, day: day(6), count: 10, now: sunday)
        XCTAssertEqual(journal.dataset.currentStreak(for: habit, asOf: sunday), 2)
        habit.streakGoal?.amount = 101
        try journal.save(habit)
        XCTAssertEqual(journal.dataset.currentStreak(for: habit, asOf: sunday), 0)
    }

    func testStreakAmountValidation() {
        XCTAssertNoThrow(try Habit(name: "Read", streakGoal: StreakGoal(period: .weekly, target: 3, amount: 7 * Counter.maximumAmount),
                                   counter: Counter()).validate())
        XCTAssertThrowsError(try Habit(name: "Read", streakGoal: StreakGoal(period: .daily, amount: Counter.maximumAmount + 1),
                                       counter: Counter()).validate())
        XCTAssertThrowsError(try Habit(name: "Read", streakGoal: StreakGoal(period: .daily, amount: 0), counter: Counter()).validate())
        XCTAssertThrowsError(try Habit(name: "Classic", streakGoal: StreakGoal(period: .daily, amount: 5)).validate(),
                             "Only Counter Habits have amount goals")
    }

    func testScaleUsesNinetiethPercentileSoOutliersDoNotWashOutHistory() throws {
        let habit = Habit(name: "Pushups", counter: Counter(step: 10))
        var journal = try journal(with: habit)
        let amounts = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 1_000]
        for (offset, amount) in amounts.enumerated() {
            let day = LocalDay.string(now.addingTimeInterval(Double(-offset) * 86_400))
            try journal.setCount(habit.id, day: day, count: amount, now: now)
        }
        let scale = try XCTUnwrap(journal.dataset.counterScales()[habit.id])
        XCTAssertEqual(scale, CounterScale(reference: 100, best: 1_000))
        XCTAssertEqual(habit.intensity(50, reference: scale.reference), 0.5)
        XCTAssertEqual(habit.intensity(1_000, reference: scale.reference), 1)
        XCTAssertEqual(habit.intensity(0, reference: scale.reference), 0)
        XCTAssertEqual(habit.intensity(5, reference: nil), 1)
        XCTAssertTrue(Dataset().counterScales().isEmpty)
    }

    func testClassicHabitStillCapsAndClears() throws {
        let habit = Habit(name: "Read", target: 2)
        var journal = try journal(with: habit)
        for _ in 0..<2 { try journal.toggle(habit.id, day: today, now: now) }
        XCTAssertEqual(journal.dataset.day(habit.id, today).count, 2)
        try journal.toggle(habit.id, day: today, now: now)
        XCTAssertEqual(journal.dataset.day(habit.id, today).count, 0)
    }

    func testAmountIsBoundedByMaximum() throws {
        let habit = Habit(name: "Steps", counter: Counter(step: 9_999))
        var journal = try journal(with: habit)
        for _ in 0..<12 { try journal.toggle(habit.id, day: today, now: now) }
        XCTAssertEqual(journal.dataset.day(habit.id, today).count, Counter.maximumAmount)
        XCTAssertThrowsError(try journal.setCount(habit.id, day: today, count: Counter.maximumAmount + 1, now: now))
    }

    func testUndoRemovesOneStepWithoutGoingNegative() throws {
        let habit = Habit(name: "Water", counter: Counter(step: 3))
        var journal = try journal(with: habit)
        try journal.toggle(habit.id, day: today, now: now)
        try journal.remove(habit.id, day: today, amount: habit.step, now: now)
        try journal.remove(habit.id, day: today, amount: habit.step, now: now)
        XCTAssertEqual(journal.dataset.day(habit.id, today).count, 0)
    }

    func testValidation() {
        XCTAssertNoThrow(try Habit(name: "Run", counter: Counter(step: 1, unit: "km")).validate())
        XCTAssertThrowsError(try Habit(name: "Classic", target: 500).validate())
        XCTAssertThrowsError(try Habit(name: "Counter with target", target: 5, counter: Counter()).validate())
        XCTAssertThrowsError(try Habit(name: "Zero step", counter: Counter(step: 0)).validate())
        XCTAssertThrowsError(try Habit(name: "Long unit", counter: Counter(unit: "kilometres run")).validate())
    }

    func testSwitchingBackToClassicKeepsRecordedHistory() throws {
        var habit = Habit(name: "Pushups", counter: Counter(step: 25))
        var journal = try journal(with: habit)
        for _ in 0..<3 { try journal.toggle(habit.id, day: today, now: now) }
        habit.counter = nil
        try journal.save(habit)
        // Amounts recorded as a Counter Habit stay; they now read as a complete classic day.
        XCTAssertEqual(journal.dataset.day(habit.id, today).count, 75)
        XCTAssertEqual(journal.dataset.day(habit.id, today).progress(target: 1), 1)
    }

    func testCounterSurvivesBackupAndOldDataDecodesAsClassic() throws {
        var data = Dataset()
        data.habits = [Habit(name: "Minutes", counter: Counter(step: 5, unit: "min"))]
        let restored = try Backup.decode(Backup(dataset: data).encoded())
        XCTAssertEqual(restored.dataset.habits[0].counter, Counter(step: 5, unit: "min"))
        let legacy = try JSONDecoder().decode(Habit.self, from: Data(#"{"id":"\#(UUID().uuidString)","name":"Old","emoji":"🌱","detail":"","color":"green","target":2,"createdAt":0,"archived":false}"#.utf8))
        XCTAssertNil(legacy.counter)
        XCTAssertEqual(legacy.step, 1)
    }

    func testCompactFormatting() {
        XCTAssertEqual(Counter.compact(0), "0")
        XCTAssertEqual(Counter.compact(999), "999")
        XCTAssertEqual(Counter.compact(1_000), "1k")
        XCTAssertEqual(Counter.compact(1_250), "1.2k")
        XCTAssertEqual(Counter.compact(12_800), "12k")
        XCTAssertEqual(Counter.compact(99_999), "99k")
    }
}
