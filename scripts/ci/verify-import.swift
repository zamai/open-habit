import Foundation

@main
struct VerifyImport {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.lastPathComponent.hasPrefix("UI-backup-") && $0.pathExtension == "json" }
        let dated = try files.map { ($0, try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) }
        guard let file = dated.max(by: { $0.1 < $1.1 })?.0 else { throw HabitError.invalidBackup("No UI-exported backup was found.") }
        let expected = try Backup.decode(Data(contentsOf: file))
        let journal = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        guard expected.dataset == journal.dataset else { throw HabitError.invalidBackup("The UI-restored dataset differs from the exported snapshot.") }
        let data = journal.dataset
        print("Exact UI round-trip match: \(data.habits.count) habits, \(data.days.count) Habit Days, \((data.categories ?? []).count) categories, \(data.days.values.filter { !$0.note.isEmpty }.count) notes, including all settings, ordering, IDs, dates, goals, colors, and counts.")
    }
}
