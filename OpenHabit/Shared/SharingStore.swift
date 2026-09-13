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
        try JSONEncoder().encode(states).write(to: url, options: [.atomic, .completeFileProtection])
    }
}

func sharingStore() throws -> SharingStore {
    let directory = try sharedStore().directory
    return SharingStore(url: directory.appendingPathComponent("shared-habits.json"))
}
