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
#Preview("Starter Habits") { OverviewView().environment(previewModel()) }
#Preview("Empty dataset") { OverviewView().environment(previewModel(empty: true)) }
#Preview("New Habit") { HabitEditor(habit: Habit(name: "Take a walk", emoji: "🌿"), isNew: true).environment(previewModel()) }
#Preview("Habit Detail") {
    NavigationStack { HabitDetailView(habitID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!) }.environment(previewModel())
}
