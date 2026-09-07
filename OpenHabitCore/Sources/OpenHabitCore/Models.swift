import Foundation

public enum HabitColor: String, Codable, CaseIterable, Sendable {
    case orange, blue, green, pink, purple, teal, red, yellow
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
public struct Settings: Codable, Equatable, Sendable {
    public var appearance: Appearance = .system
    public var weekStart: WeekStart = .system
    public var examplesDismissed = false
    public init() {}
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
    public var createdAt: Date
    public var archived: Bool
    public init(id: UUID = UUID(), name: String = "", emoji: String = "🌱", detail: String = "", color: HabitColor = .green, target: Int = 1, streakGoal: StreakGoal? = nil, createdAt: Date = Date(), archived: Bool = false) {
        self.id = id; self.name = name; self.emoji = emoji; self.detail = detail
        self.color = color; self.target = target; self.streakGoal = streakGoal; self.createdAt = createdAt; self.archived = archived
    }
    public func validate() throws {
        guard customColorRGB.map({ $0 <= 0xFFFFFF }) ?? true else { throw HabitError.invalidHabit }
        guard streakGoal.map({ $0.period == .daily ? $0.target == 1 : (1...7).contains($0.target) }) ?? true else { throw HabitError.invalidHabit }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 60,
              emoji.count == 1, emoji.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.value == 0xFE0F || ($0.properties.isEmoji && $0.value > 0x238C) }),
              detail.count <= 160, !detail.contains("\n"), (1...99).contains(target), createdAt.timeIntervalSince1970.isFinite else {
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
public struct Dataset: Codable, Equatable, Sendable {
    public var initialized = false
    public var habits: [Habit] = []
    public var days: [String: HabitDay] = [:]
    public var settings = Settings()
    public init() {}
    public var active: [Habit] { habits.filter { !$0.archived } }
    public func habit(_ id: UUID) -> Habit? { habits.first { $0.id == id } }
    public static func key(_ id: UUID, _ day: String) -> String { "\(id.uuidString)/\(day)" }
    public func day(_ id: UUID, _ date: String) -> HabitDay { days[Self.key(id, date)] ?? HabitDay() }
    public func validate() throws {
        guard Set(habits.map(\.id)).count == habits.count else { throw HabitError.invalidBackup("Duplicate Habit identifiers.") }
        for habit in habits { try habit.validate() }
        for (key, day) in days {
            let parts = key.split(separator: "/")
            guard parts.count == 2, let id = UUID(uuidString: String(parts[0])), habit(id) != nil,
                  LocalDay.isValid(String(parts[1])), day.count >= 0, day.note.count <= 500 else {
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
    case invalidHabit, missingHabit, archivedHabit, invalidDate, futureDate, invalidAmount, longNote, storageUnavailable
    case invalidBackup(String)
    public var errorDescription: String? {
        switch self {
        case .invalidHabit: "Enter one emoji, a name of 1–60 characters, a single-line description up to 160 characters, and a Daily Target from 1–99."
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
    public let formatVersion: Int
    public let exportedAt: Date
    public var dataset: Dataset
    public init(dataset: Dataset) { formatVersion = 2; exportedAt = Date(); self.dataset = dataset }
    public static func decode(_ data: Data) throws -> Backup {
        struct Header: Decodable { let formatVersion: Int }
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard (1...2).contains(header.formatVersion) else { throw HabitError.invalidBackup("Format version \(header.formatVersion) is not supported by this app.") }
        let decoder = JSONDecoder()
        if header.formatVersion == 2 {
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
        if formatVersion == 2 {
            encoder.dateEncodingStrategy = .custom { date, encoder in
                let seconds = date.timeIntervalSinceReferenceDate
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
