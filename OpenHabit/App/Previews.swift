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
@MainActor private func sharedPreviewModel() -> AppModel {
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
        sharedHabitID: definition.id, localHabitID: habit.id, memberID: ownerID, role: .owner,
        visibleFromDay: nil, zoneName: "Preview", zoneOwnerName: "Preview", shareRecordName: "Preview"
    )
    model.sharedHabits[habit.id] = SharedHabitState(
        membership: membership,
        snapshot: SharedHabitSnapshot(definition: definition, members: [owner, friend], invitations: [SharedInvitation(id: "preview")])
    )
    return model
}
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
