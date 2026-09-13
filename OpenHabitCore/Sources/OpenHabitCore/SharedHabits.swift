import Foundation

public enum SharedHabitRole: String, Codable, Sendable {
    case owner, member
}

public enum SharedHistoryChoice: String, Codable, CaseIterable, Sendable {
    case startFresh
    case fullHistory
}

public struct SharedHabitDefinition: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var emoji: String
    public var detail: String
    public var color: HabitColor
    public var customColorRGB: UInt32?
    public var target: Int
    public var streakGoal: StreakGoal?
    public var weekStart: WeekStart

    public init(habit: Habit, weekStart: WeekStart) {
        id = UUID()
        name = habit.name
        emoji = habit.emoji
        detail = habit.detail
        color = habit.color
        customColorRGB = habit.customColorRGB
        target = habit.target
        streakGoal = habit.streakGoal
        self.weekStart = weekStart
    }

    public func apply(to habit: Habit) -> Habit {
        var result = habit
        result.name = name
        result.emoji = emoji
        result.detail = detail
        result.color = color
        result.customColorRGB = customColorRGB
        result.target = target
        result.streakGoal = streakGoal
        result.archived = false
        return result
    }

    public func validate() throws {
        var habit = Habit(name: name, emoji: emoji, detail: detail, color: color, target: target, streakGoal: streakGoal)
        habit.customColorRGB = customColorRGB
        try habit.validate()
        guard weekStart != .system else { throw HabitError.invalidSharedHabit }
    }
}

public struct SharedHabitMembership: Codable, Equatable, Sendable {
    public var sharedHabitID: UUID
    public var localHabitID: UUID
    public var memberID: UUID
    public var role: SharedHabitRole
    public var visibleFromDay: String?
    public var zoneName: String
    public var zoneOwnerName: String
    public var shareRecordName: String

    public init(
        sharedHabitID: UUID,
        localHabitID: UUID,
        memberID: UUID,
        role: SharedHabitRole,
        visibleFromDay: String?,
        zoneName: String,
        zoneOwnerName: String,
        shareRecordName: String
    ) {
        self.sharedHabitID = sharedHabitID
        self.localHabitID = localHabitID
        self.memberID = memberID
        self.role = role
        self.visibleFromDay = visibleFromDay
        self.zoneName = zoneName
        self.zoneOwnerName = zoneOwnerName
        self.shareRecordName = shareRecordName
    }
}

public struct SharedMember: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var colorIndex: Int
    public var role: SharedHabitRole
    public var joinedAt: Date
    public var counts: [String: Int]
    public var cloudUserRecordName: String?

    public init(
        id: UUID = UUID(),
        name: String,
        colorIndex: Int,
        role: SharedHabitRole,
        joinedAt: Date = Date(),
        counts: [String: Int] = [:],
        cloudUserRecordName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.role = role
        self.joinedAt = joinedAt
        self.counts = counts
        self.cloudUserRecordName = cloudUserRecordName
    }

    public func validate() throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40, (0..<Self.palette.count).contains(colorIndex),
              joinedAt.timeIntervalSince1970.isFinite,
              counts.allSatisfy({ LocalDay.isValid($0.key) && $0.value >= 0 }) else {
            throw HabitError.invalidSharedHabit
        }
    }

    public static let palette: [UInt32] = [
        0x023E8A, 0xE29578, 0x0077B6, 0xEE6C4D, 0x00B4D8,
        0xF95738, 0x34A0A4, 0xFF9F1C, 0x52B69A, 0xF4D35E,
    ]

    public var colorRGB: UInt32 { Self.palette[colorIndex] }

    public static func nextColorIndex(usedBy members: [SharedMember]) -> Int? {
        let used = Set(members.map(\.colorIndex))
        return palette.indices.first { !used.contains($0) }
    }
}

public struct SharedInvitation: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var createdAt: Date
    public init(id: String, createdAt: Date = Date()) { self.id = id; self.createdAt = createdAt }
}

public struct SharedHabitSnapshot: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID { definition.id }
    public var definition: SharedHabitDefinition
    public var members: [SharedMember]
    public var invitations: [SharedInvitation]
    public var updatedAt: Date

    public init(
        definition: SharedHabitDefinition,
        members: [SharedMember],
        invitations: [SharedInvitation] = [],
        updatedAt: Date = Date()
    ) {
        self.definition = definition
        self.members = members
        self.invitations = invitations
        self.updatedAt = updatedAt
    }

    public func validate() throws {
        try definition.validate()
        guard !members.isEmpty, members.count + invitations.count <= 10,
              members.filter({ $0.role == .owner }).count == 1,
              Set(members.map(\.id)).count == members.count,
              Set(invitations.map(\.id)).count == invitations.count,
              updatedAt.timeIntervalSince1970.isFinite else {
            throw HabitError.invalidSharedHabit
        }
        try members.forEach { try $0.validate() }
    }

    public func orderedMembers(currentMemberID: UUID) -> [SharedMember] {
        members.sorted { left, right in
            func rank(_ member: SharedMember) -> Int {
                if member.id == currentMemberID { return 0 }
                if member.role == .owner { return 1 }
                return 2
            }
            let leftRank = rank(left), rightRank = rank(right)
            if leftRank != rightRank { return leftRank < rightRank }
            if left.joinedAt != right.joinedAt { return left.joinedAt < right.joinedAt }
            return left.id.uuidString < right.id.uuidString
        }
    }
}

public struct SharedHabitState: Codable, Equatable, Sendable {
    public var membership: SharedHabitMembership
    public var snapshot: SharedHabitSnapshot
    public init(membership: SharedHabitMembership, snapshot: SharedHabitSnapshot) {
        self.membership = membership
        self.snapshot = snapshot
    }

    public func validate() throws {
        try snapshot.validate()
        guard membership.sharedHabitID == snapshot.id,
              let current = snapshot.members.first(where: { $0.id == membership.memberID }),
              current.role == membership.role,
              LocalDay.isValid(membership.visibleFromDay ?? LocalDay.string()) else {
            throw HabitError.invalidSharedHabit
        }
    }
}

public extension Dataset {
    func sharedCounts(for habitID: UUID, visibleFromDay: String?) -> [String: Int] {
        let prefix = habitID.uuidString + "/"
        return days.reduce(into: [:]) { result, item in
            guard item.key.hasPrefix(prefix) else { return }
            let day = String(item.key.dropFirst(prefix.count))
            guard item.value.count > 0, visibleFromDay.map({ day >= $0 }) ?? true else { return }
            result[day] = item.value.count
        }
    }

    func dataset(for member: SharedMember, definition: SharedHabitDefinition) -> Dataset {
        var result = Dataset()
        result.initialized = true
        result.settings.weekStart = definition.weekStart
        let habit = definition.apply(to: Habit(id: definition.id, name: definition.name, createdAt: member.joinedAt))
        result.habits = [habit]
        result.days = Dictionary(uniqueKeysWithValues: member.counts.map { day, count in
            (Dataset.key(habit.id, day), HabitDay(count: count))
        })
        return result
    }
}
