import Foundation

public enum DataImportSource: Hashable, Sendable {
    case openHabit
    case habitKit
}

public enum DataImportMode: Hashable, Sendable {
    case addNewHabits
    case replaceAllData
}

public struct DataImportPlan: Sendable {
    fileprivate let normalized: NormalizedDataImport
    public let unavailableHabitIDs: Set<UUID>
    public let newHabits: [Habit]
    public let newCategories: [HabitCategory]

    public var dataset: Dataset { normalized.dataset }
    public var warnings: [String] { normalized.warnings }
    public var conflicts: [ImportDayConflict] { normalized.conflicts }
    public var exportedAt: Date? { normalized.exportedAt }

    public var suggestedMode: DataImportMode {
        !dataset.habits.isEmpty && newHabits.isEmpty ? .replaceAllData : .addNewHabits
    }
}

public struct DataImportOutcome: Sendable {
    public let changed: Bool
    public let dataset: Dataset
}

public enum DataImportError: LocalizedError {
    case sharedHabitsPreventReplacement
    case invalidConflictChoices(String)

    public var errorDescription: String? {
        switch self {
        case .sharedHabitsPreventReplacement:
            "Leave or stop sharing every Shared Habit before replacing all data."
        case .invalidConflictChoices(let message):
            message
        }
    }
}

public enum DataImport {
    public static func plan(
        _ data: Data,
        source: DataImportSource,
        store: LocalStore,
        now: Date = Date()
    ) throws -> DataImportPlan {
        let normalized: NormalizedDataImport
        switch source {
        case .openHabit:
            let backup = try Backup.decode(data)
            normalized = NormalizedDataImport(dataset: backup.dataset, exportedAt: backup.exportedAt)
        case .habitKit:
            normalized = try decodeHabitKit(data, now: now)
        }
        return try analyzedPlan(normalized, store: store)
    }

    public static func refresh(_ plan: DataImportPlan, store: LocalStore) throws -> DataImportPlan {
        try analyzedPlan(plan.normalized, store: store)
    }

    private static func analyzedPlan(_ normalized: NormalizedDataImport, store: LocalStore) throws -> DataImportPlan {
        let current = try store.read()
        let unavailable = current.unavailableImportIDs
        let existingCategories = Set((current.dataset.categories ?? []).map(\.id))
        return DataImportPlan(
            normalized: normalized,
            unavailableHabitIDs: unavailable,
            newHabits: normalized.dataset.habits.filter { !unavailable.contains($0.id) },
            newCategories: (normalized.dataset.categories ?? []).filter { !existingCategories.contains($0.id) }
        )
    }

    public static func apply(
        _ plan: DataImportPlan,
        mode: DataImportMode,
        conflictChoices: [String: DuplicateDayResolution],
        to store: LocalStore,
        activeSharedHabitIDs: Set<UUID>
    ) throws -> DataImportOutcome {
        if mode == .replaceAllData, !activeSharedHabitIDs.isEmpty {
            throw DataImportError.sharedHabitsPreventReplacement
        }
        let dataset: Dataset
        do {
            dataset = try plan.normalized.resolved(conflictChoices)
        } catch {
            throw DataImportError.invalidConflictChoices(error.localizedDescription)
        }
        return try store.applyDataImport(dataset, mode: mode)
    }
}

public enum DuplicateDayResolution: String, CaseIterable, Sendable {
    case latest = "Use latest record", sum = "Add amounts", maximum = "Use largest amount"
}
public struct ImportDayConflict: Identifiable, Sendable {
    public var id: String
    public var habitName: String
    public var day: String
    public var amounts: [Int]
    public var latest: Int
    public func count(_ resolution: DuplicateDayResolution) throws -> Int {
        switch resolution {
        case .latest: return latest
        case .maximum: return amounts.max() ?? 0
        case .sum:
            return try amounts.reduce(0) { total, amount in
                let (value, overflow) = total.addingReportingOverflow(amount)
                guard !overflow else { throw HabitError.invalidBackup("Completion count is too large.") }
                return value
            }
        }
    }
}
fileprivate struct NormalizedDataImport: Sendable {
    var dataset: Dataset
    var warnings: [String]
    var conflicts: [ImportDayConflict]
    var exportedAt: Date?
    init(dataset: Dataset, warnings: [String] = [], conflicts: [ImportDayConflict] = [], exportedAt: Date? = nil) {
        self.dataset = dataset; self.warnings = warnings; self.conflicts = conflicts; self.exportedAt = exportedAt
    }
    func resolved(_ choices: [String: DuplicateDayResolution]) throws -> Dataset {
        var result = dataset
        for conflict in conflicts {
            guard let choice = choices[conflict.id] else {
                throw HabitError.invalidBackup("Choose a count for \(conflict.habitName) on \(conflict.day).")
            }
            result.days[conflict.id]?.count = try conflict.count(choice)
        }
        try result.validate()
        return result
    }
}

private struct HabitKitExport: Decodable {
    var formatVersion: Int
    var habits: [HabitKitHabit]
    var completions: [HabitKitCompletion]
    var intervals: [HabitKitInterval]
    var categories: [HabitKitCategory]
    var categoryMappings: [HabitKitCategoryMapping]
    var reminders: [IgnoredRecord]
}
private struct IgnoredRecord: Decodable {}
private struct HabitKitHabit: Decodable {
    var id: UUID; var name: String; var description: String?; var icon: String
    var color: String; var archived: Bool; var orderIndex: Int; var createdAt: String
    var isInverse: Bool; var emoji: String?
}
private struct HabitKitCompletion: Decodable {
    var id: UUID; var date: String; var habitId: UUID; var timezoneOffsetInMinutes: Int
    var amountOfCompletions: Int; var note: String?
}
private struct HabitKitInterval: Decodable {
    var id: UUID; var habitId: UUID; var startDate: String; var endDate: String?
    var type: String; var requiredNumberOfCompletions: Int?
    var requiredNumberOfCompletionsPerDay: Int; var unitType: String; var streakType: String
    var allowExceedingGoal: Bool
}
private struct HabitKitCategory: Decodable {
    var id: UUID; var name: String; var icon: String; var orderIndex: Int; var createdAt: String
}
private struct HabitKitCategoryMapping: Decodable {
    var id: UUID; var habitId: UUID; var categoryId: UUID; var orderIndex: Int
}

private extension DataImport {
    private static func date(_ text: String) throws -> Date {
        if let dot = text.firstIndex(of: "."), text.hasSuffix("Z") {
            let digits = text[text.index(after: dot)..<text.index(before: text.endIndex)]
            if !digits.isEmpty, digits.count <= 9, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
               let fraction = Double("0." + digits),
               let whole = ISO8601DateFormatter().date(from: String(text[..<dot]) + "Z") {
                return whole.addingTimeInterval(fraction)
            }
        } else if let date = ISO8601DateFormatter().date(from: text) { return date }
        throw HabitError.invalidBackup("Invalid HabitKit timestamp: \(text)")
    }
    static func decodeHabitKit(_ data: Data, now: Date) throws -> NormalizedDataImport {
        struct Header: Decodable { var formatVersion: Int; var format: String? }
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard header.formatVersion == 2, header.format == nil else {
            throw HabitError.invalidBackup("Choose a HabitKit version 2 export, or use Open Habit import for a native backup.")
        }
        let source = try JSONDecoder().decode(HabitKitExport.self, from: data)
        let ids = Set(source.habits.map(\.id))
        guard ids.count == source.habits.count,
              Set(source.completions.map(\.id)).count == source.completions.count,
              Set(source.intervals.map(\.id)).count == source.intervals.count,
              Set(source.categoryMappings.map(\.id)).count == source.categoryMappings.count else {
            throw HabitError.invalidBackup("Duplicate identifiers in HabitKit export.")
        }
        if let record = source.completions.first(where: { !ids.contains($0.habitId) }) {
            throw HabitError.invalidBackup("HabitKit completion \(record.id) refers to missing Habit \(record.habitId).")
        }
        if let record = source.intervals.first(where: { !ids.contains($0.habitId) }) {
            throw HabitError.invalidBackup("HabitKit interval \(record.id) refers to missing Habit \(record.habitId).")
        }
        var result = Dataset(); result.initialized = true
        var warnings: [String] = []
        let orphanAssignments = source.categoryMappings.filter { !ids.contains($0.habitId) }
        if !orphanAssignments.isEmpty {
            warnings.append("Category assignments for Habits absent from this export will be skipped (count: \(orphanAssignments.count)).")
        }
        if !source.reminders.isEmpty { warnings.append("\(source.reminders.count) reminders will not transfer; Open Habit does not support reminders.") }
        let categories = try source.categories.enumerated().sorted {
            $0.element.orderIndex == $1.element.orderIndex ? $0.offset < $1.offset : $0.element.orderIndex < $1.element.orderIndex
        }.map { _, category in
            HabitCategory(id: category.id, name: category.name, icon: category.icon, createdAt: try date(category.createdAt))
        }
        if !categories.isEmpty { result.categories = categories }
        for (_, item) in source.habits.enumerated().sorted(by: {
            $0.element.orderIndex == $1.element.orderIndex ? $0.offset < $1.offset : $0.element.orderIndex < $1.element.orderIndex
        }) {
            guard !item.isInverse else { throw HabitError.invalidBackup("\(item.name) is an inverse Habit, which Open Habit cannot represent.") }
            let intervals = source.intervals.filter { $0.habitId == item.id }
            let current = try intervals.filter { interval in
                guard try date(interval.startDate) <= now else { return false }
                return try interval.endDate.map { try date($0) > now } ?? true
            }
            guard current.count == 1, let interval = current.first else {
                throw HabitError.invalidBackup("\(item.name) must have exactly one current goal interval.")
            }
            guard interval.unitType == "incremental", interval.streakType == "day", ["none", "day", "week"].contains(interval.type) else {
                throw HabitError.invalidBackup("\(item.name) uses an unsupported goal or tracking mode.")
            }
            let goal: StreakGoal?
            if interval.type == "week" {
                guard let target = interval.requiredNumberOfCompletions, (1...7).contains(target) else {
                    throw HabitError.invalidBackup("Invalid weekly goal for \(item.name).")
                }
                goal = StreakGoal(period: .weekly, target: target)
            } else { goal = interval.type == "day" ? StreakGoal(period: .daily) : nil }
            if intervals.count > 1 { warnings.append("\(item.name): the current goal will apply to all history; historical goal intervals will not transfer.") }
            if interval.allowExceedingGoal { warnings.append("\(item.name): existing counts are preserved, but new quick logging stops at the Daily Target.") }
            let icons = ["drums": "🥁", "running": "🏃", "treadmill": "🏃", "preaching": "🙏", "activity": "🏃", "makeMusic": "🎵", "glass": "💧"]
            let emoji = item.emoji ?? icons[item.icon] ?? "🌱"
            if item.emoji == nil { warnings.append("\(item.name): icon “\(item.icon)” becomes \(emoji).") }
            let color = HabitColor(rawValue: item.color) ?? (item.color == "sky" ? .blue : .green)
            if HabitColor(rawValue: item.color) == nil { warnings.append("\(item.name): color “\(item.color)” becomes \(color.rawValue).") }
            var habit = Habit(id: item.id, name: item.name, emoji: emoji, detail: item.description ?? "", color: color,
                              target: interval.requiredNumberOfCompletionsPerDay, streakGoal: goal,
                              createdAt: try date(item.createdAt), archived: item.archived)
            let assigned = source.categoryMappings.enumerated().filter { $0.element.habitId == item.id }.sorted {
                $0.element.orderIndex == $1.element.orderIndex ? $0.offset < $1.offset : $0.element.orderIndex < $1.element.orderIndex
            }.map { $0.element.categoryId }
            if !assigned.isEmpty { habit.categoryIDs = assigned }
            do { try habit.validate() } catch { throw HabitError.invalidBackup("\(item.name) does not fit Open Habit's name, description, emoji, or target limits. Edit the source and retry.") }
            result.habits.append(habit)
        }
        var grouped: [String: [(HabitKitCompletion, Date)]] = [:]
        for completion in source.completions {
            guard (-840...840).contains(completion.timezoneOffsetInMinutes), completion.amountOfCompletions >= 0 else {
                throw HabitError.invalidBackup("Invalid count or UTC offset in HabitKit completion \(completion.id).")
            }
            let instant = try date(completion.date)
            let day = LocalDay.string(instant, timeZone: TimeZone(secondsFromGMT: completion.timezoneOffsetInMinutes * 60)!)
            try LocalDay.validatePast(day, now: now)
            grouped[Dataset.key(completion.habitId, day), default: []].append((completion, instant))
        }
        var conflicts: [ImportDayConflict] = []
        for key in grouped.keys.sorted() {
            let records = grouped[key]!.sorted { $0.1 == $1.1 ? $0.0.id.uuidString < $1.0.id.uuidString : $0.1 < $1.1 }
            var notes: [String] = []
            for (record, _) in records { if let note = record.note, !note.isEmpty, !notes.contains(note) { notes.append(note) } }
            let note = notes.joined(separator: "\n\n")
            guard note.count <= 500 else { throw HabitError.invalidBackup("Combined notes exceed 500 characters on \(key). No text was truncated.") }
            if notes.count > 1 { warnings.append("\(key): distinct notes are joined with blank lines.") }
            let latest = records.last!.0
            result.days[key] = HabitDay(count: latest.amountOfCompletions, note: note)
            if records.count > 1 {
                conflicts.append(ImportDayConflict(id: key, habitName: result.habit(latest.habitId)!.name,
                                                  day: String(key.suffix(10)), amounts: records.map { $0.0.amountOfCompletions }, latest: latest.amountOfCompletions))
            }
        }
        try result.validate()
        return NormalizedDataImport(dataset: result, warnings: warnings, conflicts: conflicts)
    }
}
