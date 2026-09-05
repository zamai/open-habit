import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// A separate lock file remains stable across atomic replacement. App and widget processes share it.
public struct LocalStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func read() throws -> Journal { try transaction { $0 } }
    @discardableResult
    public func transaction<T>(_ update: (inout Journal) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lock = open(directory.appendingPathComponent("store.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lock >= 0 else { throw HabitError.storageUnavailable }
        defer { flock(lock, LOCK_UN); close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { throw HabitError.storageUnavailable }
        let url = directory.appendingPathComponent("journal.json")
        let original = try FileManager.default.fileExists(atPath: url.path) ? Data(contentsOf: url) : nil
        var journal = try original.map { try JSONDecoder().decode(Journal.self, from: $0) } ?? Journal()
        let result = try update(&journal)
        let data = try JSONEncoder().encode(journal)
        if data != original { try data.write(to: url, options: .atomic) }
        return result
    }
}
