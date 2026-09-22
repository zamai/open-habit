import Foundation

@main
struct VerifyImport {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("UI-backup-") && $0.pathExtension == "json" }
        let backups = try files.map { try Backup.decode(Data(contentsOf: $0)) }
        guard let expected = backups.max(by: { $0.exportedAt < $1.exportedAt }) else {
            throw HabitError.invalidBackup("No UI-exported backup was found.")
        }
        let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        guard expected.dataset == journal.dataset else { throw HabitError.invalidBackup("The UI-restored dataset differs from the exported snapshot.") }
        let data = journal.dataset
        print("Exact UI round-trip match: \(data.habits.count) habits, \(data.days.count) Habit Days, \((data.categories ?? []).count) categories, \(data.days.values.filter { !$0.note.isEmpty }.count) notes, including all settings, ordering, IDs, dates, goals, colors, and counts.")
    }
}
