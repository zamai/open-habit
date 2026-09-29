import SwiftUI

@main
struct OpenHabitWatchApp: App {
    @State private var model = WatchModel()
    @Environment(\.scenePhase) private var scenePhase

    init() { WatchSync.shared.start() }

    var body: some Scene {
        WindowGroup {
            WatchHabitsView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(.green)
                .task { model.reload(); WatchSync.shared.publish(force: true) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.reload(); WatchSync.shared.publish(force: true) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .watchJournalChanged)) { _ in model.reload() }
                .alert("Couldn’t save this change", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                    Button("OK") { model.error = nil }
                } message: { Text(model.error ?? "") }
        }
    }
}
