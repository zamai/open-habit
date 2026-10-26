import Foundation

public enum HabitColor: String, Codable, CaseIterable, Sendable {
    case orange, blue, green, pink, purple, teal, red, yellow, indigo, mint, brown
}
public enum Appearance: String, Codable, CaseIterable, Sendable { case system, light, dark }
public enum WeekStart: String, Codable, CaseIterable, Sendable { case system, monday, sunday }
public enum StreakPeriod: String, Codable, CaseIterable, Sendable { case daily, weekly }
public struct StreakGoal: Codable, Equatable, Sendable {
    public var period: StreakPeriod
    public var target: Int
    public init(period: StreakPeriod, target: Int = 1) {
        self.period = period
        self.target = period == .daily ? 1 : target
    }
}
/// Turns a Habit into a Counter Habit: each tap adds `step` to the Habit Day and the tile shows the
/// recorded amount. A Counter Habit has no Daily Target: more is better, and any amount completes the day.
public struct Counter: Codable, Equatable, Sendable {
    public static let maximumAmount = 99_999
    public static let maximumStep = 9_999
    public var step: Int
    public var unit: String
    public init(step: Int = 1, unit: String = "") { self.step = step; self.unit = unit }
    public func validate() throws {
        guard (1...Self.maximumStep).contains(step), unit.count <= 12, !unit.contains("\n") else { throw HabitError.invalidHabit }
    }
    /// Fits an amount into a small tile: 999, 1.2k, 12k.
    public static func compact(_ amount: Int) -> String {
        if amount < 1_000 { return "\(amount)" }
        if amount < 10_000 {
            let tenths = amount / 100
            return tenths % 10 == 0 ? "\(tenths / 10)k" : "\(tenths / 10).\(tenths % 10)k"
        }
        return "\(amount / 1_000)k"
    }
}
public struct Settings: Codable, Equatable, Sendable {
    public var appearance: Appearance = .system
    public var weekStart: WeekStart = .system
    public var examplesDismissed = false
    public init() {}
}
public struct HabitCategory: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var icon: String
    public var createdAt: Date
    public init(id: UUID, name: String, icon: String, createdAt: Date) {
        self.id = id; self.name = name; self.icon = icon; self.createdAt = createdAt
    }
}
public struct Habit: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var emoji: String
    public var detail: String
    public var color: HabitColor
    public var customColorRGB: UInt32? = nil
    public var target: Int
    public var streakGoal: StreakGoal? = nil
    public var categoryIDs: [UUID]? = nil
    public var counter: Counter? = nil
    public var createdAt: Date
    public var archived: Bool
    public init(id: UUID = UUID(), name: String = "", emoji: String = "🌱", detail: String = "", color: HabitColor = .green, target: Int = 1, streakGoal: StreakGoal? = nil, counter: Counter? = nil, createdAt: Date = Date(), archived: Bool = false) {
        self.id = id; self.name = name; self.emoji = emoji; self.detail = detail
        self.color = color; self.target = target; self.streakGoal = streakGoal; self.counter = counter; self.createdAt = createdAt; self.archived = archived
    }
    /// The amount one tap adds.
    public var step: Int { counter?.step ?? 1 }
    /// A Counter Habit keeps a Daily Target of 1, so streaks count any recorded amount.
    public var targetRange: ClosedRange<Int> { counter == nil ? 1...99 : 1...1 }
    /// "45 pushups" for Counter Habits, "1 of 3 Completions" otherwise.
    public func progressText(_ count: Int) -> String {
        guard let counter else { return "\(count) of \(target) Completions" }
        return counter.unit.isEmpty ? count.formatted() : "\(count.formatted()) \(counter.unit)"
    }
    /// How strongly a Habit Day's tile is colored, from 0 to 1. Counter Habits have no target, so
    /// they are scaled against `reference`, a typical strong day from `Dataset.counterScales()`.
    public func intensity(_ count: Int, reference: Int?) -> Double {
        guard count > 0 else { return 0 }
        guard counter != nil else { return min(1, Double(count) / Double(target)) }
        guard let reference, reference > 0 else { return 1 }
        return min(1, Double(count) / Double(reference))
    }
    public func validate() throws {
        try counter?.validate()
        guard customColorRGB.map({ $0 <= 0xFFFFFF }) ?? true else { throw HabitError.invalidHabit }
        guard streakGoal.map({ $0.period == .daily ? $0.target == 1 : (1...7).contains($0.target) }) ?? true else { throw HabitError.invalidHabit }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 60,
              emoji.count == 1, emoji.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.value == 0xFE0F || ($0.properties.isEmoji && $0.value > 0x238C) }),
              detail.count <= 160, !detail.contains("\n"), targetRange.contains(target), createdAt.timeIntervalSince1970.isFinite else {
            throw HabitError.invalidHabit
        }
    }
}
public struct HabitDay: Codable, Equatable, Sendable {
    public var count: Int = 0
    public var note: String = ""
    public init(count: Int = 0, note: String = "") { self.count = count; self.note = note }
    public func progress(target: Int) -> Double { min(1, Double(count) / Double(target)) }
}
public struct CounterScale: Equatable, Sendable {
    /// The 90th-percentile amount: days at or above it get full color, so one outlier can't wash out the rest.
    public var reference: Int
    public var best: Int
}
public struct Dataset: Codable, Equatable, Sendable {
    public var initialized = false
    public var habits: [Habit] = []
    public var days: [String: HabitDay] = [:]
    public var settings = Settings()
    public var categories: [HabitCategory]? = nil
    public init() {}
    public var active: [Habit] { habits.filter { !$0.archived } }
    public func habit(_ id: UUID) -> Habit? { habits.first { $0.id == id } }
    public static func key(_ id: UUID, _ day: String) -> String { "\(id.uuidString)/\(day)" }
    public func day(_ id: UUID, _ date: String) -> HabitDay { days[Self.key(id, date)] ?? HabitDay() }
    /// One pass over all Habit Days. Callers compute this once per data change, never per tile.
    public func counterScales() -> [UUID: CounterScale] {
        let counters = Dictionary(uniqueKeysWithValues: habits.filter { $0.counter != nil }.map { ($0.id.uuidString, $0.id) })
        guard !counters.isEmpty else { return [:] }
        var amounts: [UUID: [Int]] = [:]
        for (key, day) in days where day.count > 0 {
            if let id = counters[String(key.prefix(36))] { amounts[id, default: []].append(day.count) }
        }
        return amounts.mapValues { values in
            let sorted = values.sorted()
            return CounterScale(reference: sorted[Int(Double(sorted.count - 1) * 0.9)], best: sorted.last!)
        }
    }
    public func validate() throws {
        guard Set(habits.map(\.id)).count == habits.count else { throw HabitError.invalidBackup("Duplicate Habit identifiers.") }
        let categoryIDs = Set((categories ?? []).map(\.id))
        guard categoryIDs.count == (categories ?? []).count,
              (categories ?? []).allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.createdAt.timeIntervalSince1970.isFinite }) else {
            throw HabitError.invalidBackup("Invalid or duplicate categories.")
        }
        for habit in habits {
            try habit.validate()
            guard Set(habit.categoryIDs ?? []).isSubset(of: categoryIDs),
                  Set(habit.categoryIDs ?? []).count == (habit.categoryIDs ?? []).count else {
                throw HabitError.invalidBackup("Invalid category assignments for \(habit.name).")
            }
        }
        for (key, day) in days {
            let parts = key.split(separator: "/")
            guard parts.count == 2, let id = UUID(uuidString: String(parts[0])), habit(id) != nil,
                  key == Self.key(id, String(parts[1])), LocalDay.isValid(String(parts[1])), day.count >= 0, day.note.count <= 500 else {
                throw HabitError.invalidBackup("Invalid Habit Day or Day Note.")
            }
        }
    }
}
public enum LocalDay {
    public static func string(_ date: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public static func date(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
    public static func isValid(_ day: String) -> Bool { date(day).map { string($0) == day } ?? false }
    public static func validatePast(_ day: String, now: Date = Date()) throws {
        guard isValid(day) else { throw HabitError.invalidDate }
        guard day <= string(now) else { throw HabitError.futureDate }
    }
}
public enum HabitError: LocalizedError {
    case invalidHabit, invalidSharedHabit, missingHabit, archivedHabit, invalidDate, futureDate, invalidAmount, longNote, storageUnavailable
    case invalidBackup(String)
    public var errorDescription: String? {
        switch self {
        case .invalidHabit: "Enter one emoji, a name of 1–60 characters, a single-line description up to 160 characters, and a Daily Target from 1–99."
        case .invalidSharedHabit: "This Shared Habit contains invalid or inconsistent data."
        case .missingHabit: "This Habit was deleted. Choose another Habit."
        case .archivedHabit: "Restore this Archived Habit before adding Completions."
        case .invalidDate: "Choose a valid calendar date."
        case .futureDate: "Future Habit Days are read-only."
        case .invalidAmount: "The amount must be positive and the count cannot be negative."
        case .longNote: "A Day Note can contain up to 500 characters."
        case .storageUnavailable: "Shared storage is unavailable. Check the App Group signing configuration."
        case .invalidBackup(let reason): "Cannot restore this backup. \(reason)"
        }
    }
}
public struct Backup: Codable, Sendable {
    public var format: String? = "open-habit"
    public let formatVersion: Int
    public let exportedAt: Date
    public var dataset: Dataset
    public init(dataset: Dataset) { formatVersion = 3; exportedAt = Date(); self.dataset = dataset }
    public static func decode(_ data: Data) throws -> Backup {
        struct Header: Decodable { let formatVersion: Int; let format: String? }
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard (1...3).contains(header.formatVersion) else { throw HabitError.invalidBackup("Format version \(header.formatVersion) is not supported by this app.") }
        guard header.format == nil || header.format == "open-habit",
              header.formatVersion < 3 || header.format == "open-habit" else {
            throw HabitError.invalidBackup("This is not an Open Habit backup. Choose the matching import option.")
        }
        let decoder = JSONDecoder()
        if header.formatVersion >= 2 {
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let text = try container.decode(String.self)
                // Parse the whole second separately to retain Date's subsecond precision.
                if let dot = text.firstIndex(of: "."), text.hasSuffix("Z") {
                    let digits = text[text.index(after: dot)..<text.index(before: text.endIndex)]
                    guard !digits.isEmpty, digits.count <= 9, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
                          let fraction = Double("0." + digits),
                          let whole = ISO8601DateFormatter().date(from: String(text[..<dot]) + "Z") else {
                        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an ISO 8601 UTC timestamp.")
                    }
                    return whole.addingTimeInterval(fraction)
                }
                guard let date = ISO8601DateFormatter().date(from: text) else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an ISO 8601 timestamp.")
                }
                return date
            }
        }
        let backup = try decoder.decode(Self.self, from: data)
        try backup.dataset.validate()
        return backup
    }
    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if formatVersion >= 2 {
            encoder.dateEncodingStrategy = .custom { date, encoder in
                let seconds = date.timeIntervalSinceReferenceDate
                guard seconds.isFinite else { throw HabitError.invalidBackup("Invalid timestamp.") }
                let whole = floor(seconds)
                let prefix = ISO8601DateFormatter().string(from: Date(timeIntervalSinceReferenceDate: whole)).dropLast()
                // Nine fractional digits preserve the precision of contemporary Date values.
                let fraction = String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), seconds - whole).dropFirst()
                var container = encoder.singleValueContainer()
                try container.encode(String(prefix) + fraction + "Z")
            }
        }
        return try encoder.encode(self)
    }
}
