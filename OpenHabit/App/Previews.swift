import SwiftUI
import OpenHabitCore

@MainActor private func previewModel(empty: Bool = false) -> AppModel {
    let model = AppModel()
    var journal = Journal()
    if !empty { journal.seedIfEmpty() }
    model.data = journal.dataset
    model.loading = false
    model.syncStatus = "Synced"
    return model
}
@MainActor func sharedPreviewModel(asMember: Bool = false) -> AppModel {
    let model = previewModel()
    guard let habit = model.data.habits.first else { return model }
    var definition = SharedHabitDefinition(habit: habit, weekStart: .monday)
    let ownerID = UUID()
    let friendID = UUID()
    var owner = SharedMember(id: ownerID, name: "Taylor", colorIndex: 0, role: .owner)
    var friend = SharedMember(id: friendID, name: "Marta", colorIndex: 1, role: .member, joinedAt: Date().addingTimeInterval(1))
    for offset in 0..<7 {
        let day = LocalDay.string(Calendar.current.date(byAdding: .day, value: -offset, to: Date())!)
        owner.counts[day] = offset.isMultiple(of: 2) ? habit.target : 0
        friend.counts[day] = offset.isMultiple(of: 3) ? habit.target : 0
    }
    definition.id = UUID()
    let membership = SharedHabitMembership(
        sharedHabitID: definition.id, localHabitID: habit.id,
        memberID: asMember ? friendID : ownerID, role: asMember ? .member : .owner,
        visibleFromDay: nil, zoneName: "Preview", zoneOwnerName: "Preview", shareRecordName: "Preview"
    )
    model.sharedHabits[habit.id] = SharedHabitState(
        membership: membership,
        snapshot: SharedHabitSnapshot(definition: definition, members: [owner, friend], invitations: [SharedInvitation(id: "preview")])
    )
    return model
}

#if DEBUG && targetEnvironment(simulator)
/// Synthetic, repeatable content for the opt-in screen-width audit.
@MainActor func layoutAuditModel() -> AppModel {
    let model = sharedPreviewModel()
    let sharedID = model.data.habits[0].id
    var shared = model.sharedHabits.removeValue(forKey: sharedID)!
    var habits = [
        Habit(id: sharedID, name: "Tatat", emoji: "🌱", color: .green),
        Habit(name: "Drink some water", emoji: "🍶", color: .indigo, target: 3,
              streakGoal: StreakGoal(period: .daily)),
        Habit(name: "Drum kit practice", emoji: "🥁", detail: "Enjoy getting better at drumming, a little every day.",
              color: .green, streakGoal: StreakGoal(period: .weekly, target: 3)),
        Habit(name: "A longer habit title to check wrapping on smaller screens", emoji: "📖",
              detail: "Read five pages together, at your own pace.", color: .orange,
              streakGoal: StreakGoal(period: .daily))
    ]
    var archived = Habit(name: "An archived habit", emoji: "🌿", color: .teal)
    archived.archived = true
    habits.append(archived)
    var journal = Journal()
    for habit in habits { journal.append(.save(habit)) }
    for (index, habit) in habits.enumerated() {
        for offset in 0..<180 where (offset + index) % 5 < 2 {
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
            try! journal.setCount(habit.id, day: LocalDay.string(date), count: habit.target)
        }
    }
    try! journal.setCount(habits[1].id, day: LocalDay.string(), count: 1)
    try! journal.setCount(habits[2].id, day: LocalDay.string(), count: 1)
    model.data = journal.dataset
    model.data.settings.examplesDismissed = true
    model.data.settings.weekStart = .monday
    shared.membership.localHabitID = habits[3].id
    shared.snapshot.definition = SharedHabitDefinition(habit: habits[3], weekStart: .monday)
    model.sharedHabits[habits[3].id] = shared
    return model
}
#endif
#Preview("Starter Habits") { OverviewView().environment(previewModel()) }
#Preview("Empty dataset") { OverviewView().environment(previewModel(empty: true)) }
#Preview("New Habit") { HabitEditor(habit: Habit(name: "Take a walk", emoji: "🌿"), isNew: true).environment(previewModel()) }
#Preview("Habit Detail") {
    NavigationStack { HabitDetailView(habitID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!) }.environment(previewModel())
}
#Preview("Shared Habit") {
    NavigationStack { HabitDetailView(habitID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!) }.environment(sharedPreviewModel())
}
#Preview("Shared Habit Settings") {
    let model = sharedPreviewModel()
    HabitEditor(habit: model.data.habits[0], isNew: false).environment(model)
}
