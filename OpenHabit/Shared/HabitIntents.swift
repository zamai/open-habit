import AppIntents
import OpenHabitCore
import WidgetKit

private func performIntentEdit(_ edit: (inout Journal) throws -> Void) throws {
    // Persist before returning, then keep CloudKit and widget refreshes off the interaction path.
    // The journal is the durable upload queue if the extension is suspended before sync finishes.
    try sharedStore().transaction(edit)
    Task(priority: .utility) {
        _ = try? await CloudSync.shared.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct HabitEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static let defaultQuery = HabitQuery()
    var id: UUID
    var name: String
    var emoji: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(emoji) \(name)") }
    init(_ habit: Habit) { id = habit.id; name = habit.name + (habit.archived ? " (Archived)" : ""); emoji = habit.emoji }
}
struct HabitQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [HabitEntity] {
        let data = try sharedStore().read().dataset
        return identifiers.compactMap { data.habit($0).map(HabitEntity.init) }
    }
    func suggestedEntities() async throws -> [HabitEntity] { try sharedStore().read().dataset.habits.map(HabitEntity.init) }
}

struct ActiveHabitEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Active Habit"
    static let defaultQuery = ActiveHabitQuery()
    var id: UUID
    var name: String
    var emoji: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(emoji) \(name)") }
    init(_ habit: Habit) { id = habit.id; name = habit.name; emoji = habit.emoji }
}
struct ActiveHabitQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ActiveHabitEntity] {
        let data = try sharedStore().read().dataset
        return identifiers.compactMap { data.habit($0).map(ActiveHabitEntity.init) }
    }
    func suggestedEntities() async throws -> [ActiveHabitEntity] { try sharedStore().read().dataset.active.map(ActiveHabitEntity.init) }
}

struct AddCompletionsIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Completions"
    static let description = IntentDescription("Add Completions to an active Habit, up to its current Daily Target. Leave the date empty for today.")
    @Parameter(title: "Habit") var habit: ActiveHabitEntity
    @Parameter(title: "Amount", default: 1) var amount: Int
    @Parameter(title: "Date") var date: Date?
    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$amount) Completions to \(\.$habit)") { \.$date } }
    func perform() async throws -> some IntentResult {
        try performIntentEdit { try $0.add(habit.id, day: LocalDay.string(date ?? Date()), amount: amount) }
        return .result()
    }
}
struct RemoveCompletionsIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove Completions"
    static let description = IntentDescription("Remove Completions without going below zero. Leave the date empty for today.")
    @Parameter(title: "Habit") var habit: HabitEntity
    @Parameter(title: "Amount", default: 1) var amount: Int
    @Parameter(title: "Date") var date: Date?
    static var parameterSummary: some ParameterSummary { Summary("Remove \(\.$amount) Completions from \(\.$habit)") { \.$date } }
    func perform() async throws -> some IntentResult {
        try performIntentEdit { try $0.remove(habit.id, day: LocalDay.string(date ?? Date()), amount: amount) }
        return .result()
    }
}
struct ProgressEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Daily Progress"
    static let defaultQuery = ProgressQuery()
    var id: UUID
    @Property(title: "Count") var count: Int
    @Property(title: "Daily Target") var dailyTarget: Int
    @Property(title: "Target Met") var targetMet: Bool
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(count) of \(dailyTarget) Completions", subtitle: "\(targetMet ? "Complete" : count == 0 ? "Empty" : "In progress")") }
    init(habit: Habit, count: Int) { id = habit.id; self.count = count; dailyTarget = habit.target; targetMet = count >= habit.target }
}
struct ProgressQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ProgressEntity] {
        let data = try sharedStore().read().dataset
        return identifiers.compactMap { id in data.habit(id).map { ProgressEntity(habit: $0, count: data.day(id, LocalDay.string()).count) } }
    }
}
struct GetTodayProgressIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Today’s Progress"
    @Parameter(title: "Habit") var habit: HabitEntity
    @Parameter(title: "Date") var date: Date?
    static var parameterSummary: some ParameterSummary { Summary("Get today’s progress for \(\.$habit)") { \.$date } }
    func perform() async throws -> some IntentResult & ReturnsValue<ProgressEntity> {
        let data = try sharedStore().read().dataset
        guard let stored = data.habit(habit.id) else { throw HabitError.missingHabit }
        let day = LocalDay.string(date ?? Date())
        try LocalDay.validatePast(day)
        return .result(value: ProgressEntity(habit: stored, count: data.day(habit.id, day).count))
    }
}
struct SetDayNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Day Note"
    static let description = IntentDescription("Set the optional plain-text note for a Habit Day, up to 500 characters. Future dates are read-only.")
    @Parameter(title: "Habit") var habit: HabitEntity
    @Parameter(title: "Date") var date: Date?
    @Parameter(title: "Text") var text: String
    static var parameterSummary: some ParameterSummary { Summary("Set \(\.$habit) Day Note to \(\.$text)") { \.$date } }
    func perform() async throws -> some IntentResult {
        try performIntentEdit { try $0.setNote(habit.id, day: LocalDay.string(date ?? Date()), note: text) }
        return .result()
    }
}
struct ToggleHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Habit Completion"
    static let isDiscoverable = false
    @Parameter(title: "Habit identifier") var habitID: String
    init() {}
    init(id: UUID) { habitID = id.uuidString }
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: habitID) else { throw HabitError.missingHabit }
        try performIntentEdit { try $0.toggle(id) }
        return .result()
    }
}
struct OpenHabitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddCompletionsIntent(), phrases: ["Add Completions in \(.applicationName)"], shortTitle: "Add Completions", systemImageName: "plus.circle")
        AppShortcut(intent: RemoveCompletionsIntent(), phrases: ["Remove Completions in \(.applicationName)"], shortTitle: "Remove Completions", systemImageName: "minus.circle")
        AppShortcut(intent: GetTodayProgressIntent(), phrases: ["Get my progress in \(.applicationName)"], shortTitle: "Today’s Progress", systemImageName: "checkmark.circle")
        AppShortcut(intent: SetDayNoteIntent(), phrases: ["Set a Day Note in \(.applicationName)"], shortTitle: "Set Day Note", systemImageName: "note.text")
    }
}
