import SwiftUI
import OpenHabitCore
import WidgetKit

@MainActor @Observable
final class AppModel {
    var data = Dataset()
    var syncStatus = "Syncing"
    var error: String?
    var loading = true
    var syncing = false

    func reload() {
        do { data = try sharedStore().read().dataset }
        catch { self.error = error.localizedDescription }
    }
    func update(_ operation: (inout Journal) throws -> Void) {
        error = nil
        do {
            try performLocalEdit(operation)
            reload()
            Task { await sync() }
        } catch { self.error = error.localizedDescription }
    }
    func importData(_ data: Dataset, replacing: Bool) {
        error = nil
        do {
            if replacing { try sharedStore().restoreBackup(Backup(dataset: data)) }
            else { try sharedStore().importDataset(data) }
            reload()
            WidgetCenter.shared.reloadAllTimelines()
            Task { await sync() }
        } catch { self.error = error.localizedDescription }
    }
    func eraseData() {
        error = nil
        do {
            try sharedStore().deleteAllData()
            reload()
            WidgetCenter.shared.reloadAllTimelines()
            Task { await sync() }
        } catch { self.error = error.localizedDescription }
    }
    func sync() async {
        guard !syncing else { return }
        syncing = true; syncStatus = "Syncing"
        do { syncStatus = try await CloudSync.shared.synchronize() }
        catch { syncStatus = syncProblem(error) }
        reload(); loading = false; syncing = false
        WidgetCenter.shared.reloadAllTimelines()
    }
    func setSettings(_ transform: (inout Settings) -> Void) {
        // Read the current shared value under the lock, rather than overwriting a stale UI snapshot.
        update { journal in var value = journal.dataset.settings; transform(&value); journal.append(.settings(value)) }
    }
    func delete(_ id: UUID) { update { $0.append(.delete(id)) }; UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    var colorScheme: ColorScheme? {
        switch data.settings.appearance { case .system: nil; case .light: .light; case .dark: .dark }
    }
}
