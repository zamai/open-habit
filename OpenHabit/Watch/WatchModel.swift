import Foundation
import Observation
import OpenHabitCore

func watchStore() -> LocalStore {
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("OpenHabit", isDirectory: true)
    return LocalStore(directory: directory)
}

@MainActor @Observable
final class WatchModel {
    var data = Dataset() {
        didSet { counterScales = data.counterScales() }
    }
    private(set) var counterScales: [UUID: CounterScale] = [:]
    var error: String?
    private let store: LocalStore

    init(store: LocalStore = watchStore()) {
        self.store = store
        reload()
    }

    func reload() {
        do {
            data = try store.read().dataset
        } catch { self.error = error.localizedDescription }
    }

    func complete(_ habitID: UUID, now: Date = Date()) {
        error = nil
        do {
            try store.transaction { try $0.toggle(habitID, day: LocalDay.string(now), now: now) }
            reload()
            WatchSync.shared.publish()
        } catch { self.error = error.localizedDescription }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Counter Habits with varied and maximum amounts, for checking the Watch layout. Replaces local data.
func seedWatchCounterDemo(into store: LocalStore) {
    // The maximum-amount Habit comes first, so the first page shows the worst case.
    let habits: [(Habit, Int)] = [
        (Habit(name: "Steps walked every single day", emoji: "👟", color: .indigo,
               counter: Counter(step: Counter.maximumStep, unit: "steps walked")), 20_000),
        (Habit(name: "Pushups", emoji: "💪", color: .orange, streakGoal: StreakGoal(period: .daily),
               counter: Counter(step: 10, unit: "pushups")), 60),
        (Habit(name: "Drink water", emoji: "💧", color: .blue, counter: Counter(step: 1, unit: "glasses")), 6),
        (Habit(name: "Read", emoji: "📖", color: .teal), 1)
    ]
    var journal = Journal()
    for (habit, _) in habits.reversed() { try! journal.save(habit) }
    var seed: UInt64 = 7
    for (habit, typical) in habits {
        for offset in 1..<90 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let random = Double(seed >> 11) / Double(1 << 53)
            guard random < 0.75 else { continue }
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
            let amount = habit.counter == nil ? 1 : min(Counter.maximumAmount, max(habit.step, Int(random * 2.6 * Double(typical)) / habit.step * habit.step))
            try! journal.setCount(habit.id, day: LocalDay.string(date), count: amount)
        }
    }
    try! journal.setCount(habits[0].0.id, day: LocalDay.string(), count: Counter.maximumAmount)
    try! journal.setCount(habits[1].0.id, day: LocalDay.string(), count: 40)
    try! store.transaction { $0 = journal }
}
#endif
