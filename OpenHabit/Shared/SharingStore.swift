import Foundation
import OpenHabitCore

struct SharingStore {
    let url: URL

    func read() throws -> [SharedHabitState] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let states = try JSONDecoder().decode([SharedHabitState].self, from: Data(contentsOf: url))
        try states.forEach { try $0.validate() }
        return states
    }

    func write(_ states: [SharedHabitState]) throws {
        try states.forEach { try $0.validate() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let ordered = states.sorted {
            $0.membership.localHabitID.uuidString < $1.membership.localHabitID.uuidString
        }
        try JSONEncoder().encode(ordered).write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Sharing metadata is a cache for Habits in the current Dataset. Remove entries whose
    /// Habit was deleted or replaced so invisible cache state cannot block data recovery.
    func read(reconciling data: Dataset) throws -> [UUID: SharedHabitState] {
        let stored = try read()
        let habitIDs = Set(data.habits.map(\.id))
        let active = stored.filter { habitIDs.contains($0.membership.localHabitID) }
        if active.count != stored.count { try write(active) }
        return Dictionary(active.map { ($0.membership.localHabitID, $0) },
                          uniquingKeysWith: { _, latest in latest })
    }
}

func sharingStore() throws -> SharingStore {
    let directory = try sharedStore().directory
    return SharingStore(url: directory.appendingPathComponent("shared-habits.json"))
}
