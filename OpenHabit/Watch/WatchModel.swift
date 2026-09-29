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
    var data = Dataset()
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
            try store.transaction { journal in
                guard let habit = journal.dataset.habit(habitID) else { throw HabitError.missingHabit }
                guard !habit.archived else { throw HabitError.archivedHabit }
                let day = LocalDay.string(now)
                let added = journal.dataset.day(habitID, day).count < habit.target
                if added { try journal.add(habitID, day: day, now: now) }
                else { try journal.remove(habitID, day: day, now: now) }
            }
            reload()
            WatchSync.shared.publish()
        } catch { self.error = error.localizedDescription }
    }

}
