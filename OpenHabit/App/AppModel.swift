import SwiftUI
import OpenHabitCore
import WidgetKit
import CloudKit

@MainActor @Observable
final class AppModel {
    var data = Dataset()
    var sharedHabits: [UUID: SharedHabitState] = [:]
    var pendingJoin: SharedHabitJoinOffer?
    var preparingShare = false
    var syncStatus = "Syncing"
    var error: String?
    var loading = true
    var syncing = false

    func reload() {
        do {
            data = try sharedStore().read().dataset
            sharedHabits = try sharingStore().read(reconciling: data)
        }
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
        guard !replacing || sharedHabits.isEmpty else {
            error = "Leave or stop sharing every Shared Habit before replacing all data."
            return
        }
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
        guard sharedHabits.isEmpty else {
            error = "Leave Shared Habits and stop sharing the Shared Habits you own before deleting all data."
            return
        }
        do {
            try sharedStore().deleteAllData()
            reload()
            WidgetCenter.shared.reloadAllTimelines()
            Task { await sync() }
        } catch { self.error = error.localizedDescription }
    }
    func sync(sharedHabits synchronizeSharedHabits: Bool = true) async {
        guard !syncing else { return }
        syncing = true; syncStatus = "Syncing"
        do {
            syncStatus = try await CloudSync.shared.synchronize()
            reload()
            guard synchronizeSharedHabits else {
                loading = false
                syncing = false
                WidgetCenter.shared.reloadAllTimelines()
                return
            }
            var next = try sharingStore().read(reconciling: data)
            for state in try await SharedCloudSync.shared.privateStates()
            where data.habit(state.membership.localHabitID) != nil && next[state.membership.localHabitID] == nil {
                next[state.membership.localHabitID] = state
            }
            for (habitID, state) in next {
                do {
                    let synchronized = try await SharedCloudSync.shared.synchronize(state, dataset: data)
                    next[habitID] = synchronized
                    try? await SharedCloudSync.shared.savePrivateState(synchronized)
                    if synchronized.membership.role == .member,
                       let habit = data.habit(habitID) {
                        let adopted = synchronized.snapshot.definition.apply(to: habit)
                        if adopted != habit { try performLocalEdit { try $0.save(adopted) } }
                    }
                } catch SharedHabitCloudError.unavailable {
                    next.removeValue(forKey: habitID)
                    try? await SharedCloudSync.shared.deletePrivateState(state.membership.sharedHabitID)
                } catch let cloud as CKError where state.membership.role == .member && [.unknownItem, .zoneNotFound, .permissionFailure].contains(cloud.code) {
                    next.removeValue(forKey: habitID)
                    try? await SharedCloudSync.shared.deletePrivateState(state.membership.sharedHabitID)
                }
            }
            try sharingStore().write(Array(next.values))
            sharedHabits = next
        }
        catch { syncStatus = syncProblem(error) }
        reload(); loading = false; syncing = false
        WidgetCenter.shared.reloadAllTimelines()
    }
    func setSettings(_ transform: (inout Settings) -> Void) {
        // Read the current shared value under the lock, rather than overwriting a stale UI snapshot.
        update { journal in var value = journal.dataset.settings; transform(&value); journal.append(.settings(value)) }
    }
    func delete(_ id: UUID) { update { $0.append(.delete(id)) }; UINotificationFeedbackGenerator().notificationOccurred(.warning) }

    func share(_ habit: Habit, memberName: String, history: SharedHistoryChoice) async -> Bool {
        error = nil
        do {
            let state = try await SharedCloudSync.shared.create(habit: habit, dataset: data, memberName: memberName, history: history)
            sharedHabits[habit.id] = state
            try sharingStore().write(Array(sharedHabits.values))
            try? await SharedCloudSync.shared.savePrivateState(state)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    @available(iOS 18.0, *)
    func createInvitation(for habitID: UUID) async -> URL? {
        error = nil
        guard let state = sharedHabits[habitID] else { return nil }
        do {
            let (updated, url) = try await SharedCloudSync.shared.createInvitation(for: state)
            sharedHabits[habitID] = updated
            try sharingStore().write(Array(sharedHabits.values))
            try? await SharedCloudSync.shared.savePrivateState(updated)
            return url
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func sharedHabit(for localHabitID: UUID) -> SharedHabitState? { sharedHabits[localHabitID] }

    func preparePendingShare() async {
        guard let metadata = ShareAcceptanceBroker.shared.take() else { return }
        preparingShare = true
        defer { preparingShare = false }
        error = nil
        ShareAcceptanceBroker.logger.info("Accepting invitation and fetching Shared Habit")
        do {
            pendingJoin = try await SharedCloudSync.shared.accept(metadata)
            ShareAcceptanceBroker.logger.info("Shared Habit loaded; presenting join screen")
        } catch {
            let failure = error as NSError
            ShareAcceptanceBroker.logger.error("Invitation failed: \(failure.domain, privacy: .public) code \(failure.code)")
            self.error = error.localizedDescription
        }
    }

    func join(_ offer: SharedHabitJoinOffer, memberName: String, existingHabitID: UUID?) async -> Bool {
        error = nil
        let localHabitID = existingHabitID ?? UUID()
        let existing = existingHabitID.flatMap(data.habit)
        let visibleFromDay = existing == nil ? LocalDay.string() : nil
        let counts = existing.map { data.sharedCounts(for: $0.id, visibleFromDay: nil) } ?? [:]
        do {
            let state = try await SharedCloudSync.shared.join(
                offer,
                localHabitID: localHabitID,
                memberName: memberName,
                counts: counts,
                visibleFromDay: visibleFromDay
            )
            let base = existing ?? Habit(id: localHabitID, name: offer.snapshot.definition.name, createdAt: Date())
            let localHabit = offer.snapshot.definition.apply(to: base)
            try performLocalEdit { try $0.save(localHabit) }
            sharedHabits[localHabitID] = state
            try sharingStore().write(Array(sharedHabits.values))
            try? await SharedCloudSync.shared.savePrivateState(state)
            pendingJoin = nil
            reload()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func decline(_ offer: SharedHabitJoinOffer) async {
        error = nil
        do {
            try await SharedCloudSync.shared.decline(offer)
            pendingJoin = nil
        } catch { self.error = error.localizedDescription }
    }

    func updateMember(habitID: UUID, name: String, colorIndex: Int) {
        error = nil
        guard var state = sharedHabits[habitID],
              let index = state.snapshot.members.firstIndex(where: { $0.id == state.membership.memberID }) else { return }
        state.snapshot.members[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        state.snapshot.members[index].colorIndex = colorIndex
        do {
            try state.snapshot.validate()
            sharedHabits[habitID] = state
            try sharingStore().write(Array(sharedHabits.values))
            Task { await sync() }
        } catch { self.error = error.localizedDescription }
    }

    func leaveSharedHabit(_ habitID: UUID) async -> Bool {
        error = nil
        guard let state = sharedHabits[habitID] else { return false }
        do {
            try await SharedCloudSync.shared.leave(state)
            try? await SharedCloudSync.shared.deletePrivateState(state.membership.sharedHabitID)
            sharedHabits.removeValue(forKey: habitID)
            try sharingStore().write(Array(sharedHabits.values))
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func stopSharing(_ habitID: UUID) async -> Bool {
        error = nil
        guard let state = sharedHabits[habitID] else { return false }
        do {
            try await SharedCloudSync.shared.stopSharing(state)
            try? await SharedCloudSync.shared.deletePrivateState(state.membership.sharedHabitID)
            sharedHabits.removeValue(forKey: habitID)
            try sharingStore().write(Array(sharedHabits.values))
            reload()
            Task { await sync() }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func cancelInvitation(_ invitationID: String, habitID: UUID) async {
        error = nil
        guard let state = sharedHabits[habitID] else { return }
        do {
            let updated = try await SharedCloudSync.shared.cancelInvitation(invitationID, in: state)
            sharedHabits[habitID] = updated
            try sharingStore().write(Array(sharedHabits.values))
            try? await SharedCloudSync.shared.savePrivateState(updated)
        } catch { self.error = error.localizedDescription }
    }

    func removeMember(_ member: SharedMember, habitID: UUID) async {
        error = nil
        guard let state = sharedHabits[habitID] else { return }
        do {
            let updated = try await SharedCloudSync.shared.remove(member, from: state)
            sharedHabits[habitID] = updated
            try sharingStore().write(Array(sharedHabits.values))
            try? await SharedCloudSync.shared.savePrivateState(updated)
        } catch { self.error = error.localizedDescription }
    }
    var colorScheme: ColorScheme? {
        switch data.settings.appearance { case .system: nil; case .light: .light; case .dark: .dark }
    }
}
