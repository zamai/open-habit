import Foundation

// Uniquely identified edits make retries idempotent and preserve distinct offline additions.
public struct Edit: Codable, Identifiable, Equatable, Sendable {
    public enum Action: Codable, Equatable, Sendable {
        case redacted
        case initialize(Dataset)
        case replace(Dataset)
        case importData(Dataset)
        case save(Habit)
        case archive(UUID, Bool)
        case delete(UUID)
        case order([UUID])
        case add(UUID, String, Int, Int)
        case remove(UUID, String, Int)
        case count(UUID, String, Int)
        case note(UUID, String, String)
        case settings(Settings)
    }
    public var id: UUID
    public var generation: UUID
    public var timestamp: Date
    public var action: Action
    public init(id: UUID = UUID(), generation: UUID = Journal.originalGeneration, timestamp: Date = Date(), action: Action) {
        self.id = id; self.generation = generation; self.timestamp = timestamp; self.action = action
    }
}
public struct Journal: Codable, Sendable {
    public static let originalGeneration = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    public var edits: [Edit] = []
    public init() {}
    private var sorted: [Edit] {
        edits.sorted { $0.timestamp == $1.timestamp ? $0.id.uuidString < $1.id.uuidString : $0.timestamp < $1.timestamp }
    }
    public var generation: UUID {
        sorted.last(where: { if case .replace = $0.action { return true }; return false })?.id ?? Self.originalGeneration
    }
    public mutating func merge(_ incoming: [Edit]) {
        var ids = Set(edits.map(\.id))
        for edit in incoming where ids.insert(edit.id).inserted { edits.append(edit) }
        redactDeletedContent()
    }
    public mutating func append(_ action: Edit.Action, now: Date = Date()) {
        // A local edit must sort after every edit this device has already observed.
        let timestamp = max(now, (edits.map(\.timestamp).max() ?? .distantPast).addingTimeInterval(0.000001))
        edits.append(Edit(generation: generation, timestamp: timestamp, action: action))
        redactDeletedContent()
    }
    // Preserve only causality markers after deletion/replacement, never the removed user content.
    // Redaction is deterministic and is also uploaded over the corresponding CloudKit payload.
    public mutating func redactDeletedContent() {
        let reset = sorted.last { if case .replace = $0.action { return true }; return false }
        let current = reset?.id ?? Self.originalGeneration
        let deleted = Set(edits.compactMap { edit -> UUID? in
            guard edit.generation == current else { return nil }
            if case .delete(let id) = edit.action { return id }
            return nil
        })
        func cleaned(_ source: Dataset) -> Dataset {
            var data = source
            data.habits.removeAll { deleted.contains($0.id) }
            let removed = Set(deleted.map { $0.uuidString })
            data.days = data.days.filter { !removed.contains(String($0.key.prefix(36))) }
            return data
        }
        for index in edits.indices {
            if edits[index].id == reset?.id {
                if case .replace(let data) = edits[index].action { edits[index].action = .replace(cleaned(data)) }
                continue
            }
            guard edits[index].generation == current else { edits[index].action = .redacted; continue }
            switch edits[index].action {
            case .importData(let data): edits[index].action = .importData(cleaned(data))
            case .initialize(let data): edits[index].action = .initialize(cleaned(data))
            case .save(let habit): if deleted.contains(habit.id) { edits[index].action = .redacted }
            case .archive(let id, _), .add(let id, _, _, _), .remove(let id, _, _), .count(let id, _, _), .note(let id, _, _):
                if deleted.contains(id) { edits[index].action = .redacted }
            case .order(let ids): edits[index].action = .order(ids.filter { !deleted.contains($0) })
            default: break
            }
        }
    }
    public var dataset: Dataset {
        let ordered = sorted
        let reset = ordered.last { if case .replace = $0.action { return true }; return false }
        let generation = reset?.id ?? Self.originalGeneration
        var result = Dataset()
        if let reset, case .replace(let data) = reset.action { result = data; result.initialized = true }
        let relevant = ordered.filter { $0.generation == generation }
        let deleted = Set(relevant.compactMap { edit -> UUID? in if case .delete(let id) = edit.action { return id }; return nil })
        for edit in relevant {
            switch edit.action {
            case .initialize(let data):
                if !result.initialized { result = data; result.initialized = true }
            case .importData(let data):
                // A snapshot is added only once per Habit ID, even across offline imports.
                let existing = Set(result.habits.map(\.id)).union(deleted)
                let added = data.habits.filter { !existing.contains($0.id) }
                let addedIDs = Set(added.map { $0.id.uuidString })
                result.habits.append(contentsOf: added)
                for (key, day) in data.days where addedIDs.contains(String(key.prefix(36))) { result.days[key] = day }
                let categoryIDs = Set((result.categories ?? []).map(\.id))
                let categories = (data.categories ?? []).filter { !categoryIDs.contains($0.id) }
                if !categories.isEmpty { result.categories = (result.categories ?? []) + categories }
                result.initialized = true
            case .replace, .redacted: break
            case .save(var habit):
                guard !deleted.contains(habit.id) else { continue }
                if let index = result.habits.firstIndex(where: { $0.id == habit.id }) {
                    habit.createdAt = result.habits[index].createdAt
                    habit.archived = result.habits[index].archived
                    result.habits[index] = habit
                } else { result.habits.append(habit) }
                result.initialized = true
            case .archive(let id, let archived):
                if let index = result.habits.firstIndex(where: { $0.id == id }) { result.habits[index].archived = archived }
            case .delete: break
            case .order(let ids):
                let positions = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
                result.habits = result.habits.enumerated().sorted {
                    let a = positions[$0.element.id] ?? (ids.count + $0.offset)
                    let b = positions[$1.element.id] ?? (ids.count + $1.offset)
                    return a < b
                }.map(\.element)
            case .add(let id, let date, let amount, let ceiling):
                let key = Dataset.key(id, date); var day = result.days[key] ?? HabitDay()
                let limit = min(ceiling, result.habit(id)?.target ?? ceiling)
                if day.count < limit { day.count += min(amount, limit - day.count) }
                result.days[key] = day
            case .remove(let id, let date, let amount):
                let key = Dataset.key(id, date); var day = result.days[key] ?? HabitDay()
                day.count -= min(day.count, amount); result.days[key] = day
            case .count(let id, let date, let count):
                let key = Dataset.key(id, date); var day = result.days[key] ?? HabitDay()
                day.count = count; result.days[key] = day
            case .note(let id, let date, let note):
                let key = Dataset.key(id, date); var day = result.days[key] ?? HabitDay()
                day.note = note; result.days[key] = day
            case .settings(let settings): result.settings = settings
            }
        }
        result.habits.removeAll { deleted.contains($0.id) }
        let ids = Set(result.habits.map { $0.id.uuidString })
        result.days = result.days.filter { ids.contains(String($0.key.prefix(36))) }
        return result
    }
    public mutating func seedIfEmpty(now: Date = Date()) {
        guard !dataset.initialized else { return }
        var data = Dataset(); data.initialized = true; data.settings = dataset.settings
        data.habits = [
            Habit(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Exercise", emoji: "🏃", detail: "Move your body for at least twenty minutes.", color: .orange, createdAt: now),
            Habit(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Drink the f★cking water", emoji: "💧", detail: "Why do I need habit tracking for drinking water?", color: .blue, target: 3, createdAt: now),
            Habit(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Read five pages", emoji: "📖", detail: "Five pages is enough to keep the story moving.", color: .green, createdAt: now)
        ]
        data.days[Dataset.key(data.habits[1].id, LocalDay.string(now))] = HabitDay(count: 1)
        append(.initialize(data), now: now)
    }
    public mutating func save(_ habit: Habit) throws { try habit.validate(); append(.save(habit)) }
    public mutating func add(_ id: UUID, day: String, amount: Int = 1, now: Date = Date()) throws {
        try LocalDay.validatePast(day, now: now)
        guard amount > 0 else { throw HabitError.invalidAmount }
        guard let habit = dataset.habit(id) else { throw HabitError.missingHabit }
        guard !habit.archived else { throw HabitError.archivedHabit }
        append(.add(id, day, amount, habit.target), now: now)
    }
    public mutating func remove(_ id: UUID, day: String, amount: Int = 1, now: Date = Date()) throws {
        try LocalDay.validatePast(day, now: now)
        guard amount > 0 else { throw HabitError.invalidAmount }
        guard dataset.habit(id) != nil else { throw HabitError.missingHabit }
        append(.remove(id, day, amount), now: now)
    }
    public mutating func setCount(_ id: UUID, day: String, count: Int, now: Date = Date()) throws {
        try LocalDay.validatePast(day, now: now)
        guard count >= 0 else { throw HabitError.invalidAmount }
        guard dataset.habit(id) != nil else { throw HabitError.missingHabit }
        append(.count(id, day, count), now: now)
    }
    public mutating func setNote(_ id: UUID, day: String, note: String, now: Date = Date()) throws {
        try LocalDay.validatePast(day, now: now)
        guard note.count <= 500 else { throw HabitError.longNote }
        guard dataset.habit(id) != nil else { throw HabitError.missingHabit }
        append(.note(id, day, note), now: now)
    }
    public mutating func toggle(_ id: UUID, day: String = LocalDay.string(), now: Date = Date()) throws {
        guard let habit = dataset.habit(id) else { throw HabitError.missingHabit }
        guard !habit.archived else { throw HabitError.archivedHabit }
        if dataset.day(id, day).count >= habit.target { try setCount(id, day: day, count: 0, now: now) }
        else { try add(id, day: day, now: now) }
    }
    public var unavailableImportIDs: Set<UUID> {
        let current = generation
        return Set(dataset.habits.map(\.id)).union(edits.compactMap { edit in
            guard edit.generation == current else { return nil }
            if case .delete(let id) = edit.action { return id }
            return nil
        })
    }
    public mutating func importDataset(_ data: Dataset) throws {
        try data.validate()
        append(.importData(data))
    }
    public mutating func restore(_ backup: Backup) throws {
        try backup.dataset.validate()
        var data = backup.dataset; data.initialized = true
        append(.replace(data))
    }
}
