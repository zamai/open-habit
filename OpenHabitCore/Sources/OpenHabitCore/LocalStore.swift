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

extension LocalStore {
    public var recoveryDirectory: URL { directory.appendingPathComponent("RecoveryBackups", isDirectory: true) }

    public func recoveryBackups() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: recoveryDirectory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: recoveryDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "json" }
        let dated = try files.map { ($0, try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) }
        return dated.sorted { $0.1 == $1.1 ? $0.0.lastPathComponent > $1.0.lastPathComponent : $0.1 > $1.1 }.map { $0.0 }
    }

    // Called under the journal lock: a failed recovery write prevents the destructive edit.
    private func saveRecovery(_ dataset: Dataset) throws {
        let data = try Backup(dataset: dataset).encoded()
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = recoveryDirectory.appendingPathComponent("Before-change-\(timestamp)-\(UUID().uuidString).json")
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func importDataset(_ data: Dataset) throws {
        try data.validate()
        try transaction { journal in
            var next = journal
            try next.importDataset(data)
            guard next.dataset != journal.dataset else { return }
            try saveRecovery(journal.dataset)
            journal = next
        }
    }

    public func restoreBackup(_ backup: Backup) throws {
        try backup.dataset.validate()
        try transaction { journal in
            try saveRecovery(journal.dataset)
            try journal.restore(backup)
        }
    }

    public func deleteAllData() throws {
        var empty = Dataset(); empty.initialized = true; empty.settings.examplesDismissed = true
        try restoreBackup(Backup(dataset: empty))
    }
}
