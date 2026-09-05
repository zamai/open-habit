import Foundation
import CloudKit
import OpenHabitCore

// Identified records are fetched with zone change enumeration (no query indexes required).
// Only deletion redaction replaces an existing payload.
// Replaying their union is deterministic; replace events fence off older offline datasets.
actor CloudSync {
    static let shared = CloudSync()
    private var running = false
    private let zoneID = CKRecordZone.ID(zoneName: "OpenHabit", ownerName: CKCurrentUserDefaultName)

    func synchronize() async throws -> String {
        guard !running else { return "Syncing" }
        running = true
        defer { running = false }
        #if targetEnvironment(simulator)
        // Unsigned simulator builds cannot exercise a provisioned private CloudKit container.
        try sharedStore().transaction { $0.seedIfEmpty() }
        return "iCloud unavailable in Simulator. Tracking is saved locally."
        #else
        let container = CKContainer(identifier: cloudContainerID)
        let status = try await container.accountStatus()
        guard status == .available else {
            if status == .noAccount {
                try sharedStore().transaction { $0.seedIfEmpty() }
                return "iCloud unavailable. Sign in to iCloud in Settings to sync."
            }
            return "iCloud is temporarily unavailable or restricted. Check iCloud in Settings and retry."
        }
        let account = try await container.userRecordID().recordName
        let accountFile = try sharedStore().directory.appendingPathComponent("cloud-account.txt")
        if FileManager.default.fileExists(atPath: accountFile.path),
           try String(contentsOf: accountFile, encoding: .utf8) != account {
            return "iCloud account changed. Sign back in to the original iCloud account to sync these local Habits. Export a backup to keep a separate copy."
        }
        try FileManager.default.createDirectory(at: accountFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try account.write(to: accountFile, atomically: true, encoding: .utf8)
        let database = container.privateCloudDatabase
        _ = try await database.save(CKRecordZone(zoneID: zoneID))
        let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: "OpenHabitChanges")
        let info = CKSubscription.NotificationInfo(); info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await database.save(subscription)
        let remote = try await fetchAll(database)
        try sharedStore().transaction { journal in
            journal.merge(remote)
            journal.seedIfEmpty()
        }
        let remoteIDs = Set(remote.map(\.id))
        let remoteByID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let pending = try sharedStore().read().edits.filter { remoteByID[$0.id] != $0 }
        for start in stride(from: 0, to: pending.count, by: 100) {
            let batch = Array(pending[start..<min(start + 100, pending.count)])
            var files: [URL] = []
            defer { for file in files { try? FileManager.default.removeItem(at: file) } }
            let records = try batch.map { edit in
                let record = CKRecord(recordType: "HabitEdit", recordID: CKRecord.ID(recordName: edit.id.uuidString, zoneID: zoneID))
                let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try JSONEncoder().encode(edit).write(to: file, options: .atomic)
                files.append(file); record["payload"] = CKAsset(fileURL: file)
                return record
            }
            let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys, atomically: true)
            for value in result.saveResults.values { _ = try value.get() }
        }
        // An edit from the widget may have arrived while the network request was running.
        let finalIDs = Set(remoteIDs.union(pending.map(\.id)))
        return try sharedStore().read().edits.allSatisfy { finalIDs.contains($0.id) } ? "Synced" : "Syncing"
        #endif
    }

    private func fetchAll(_ database: CKDatabase) async throws -> [Edit] {
        var all: [Edit] = []
        var token: CKServerChangeToken?
        var more = true
        while more {
            let page: (edits: [Edit], token: CKServerChangeToken?, more: Bool) = try await withCheckedThrowingContinuation { continuation in
                let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
                configuration.previousServerChangeToken = token
                let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: configuration])
                operation.fetchAllChanges = false
                var edits: [Edit] = []
                var pageToken: CKServerChangeToken?
                var hasMore = false
                var failure: Error?
                operation.recordWasChangedBlock = { _, result in
                    do {
                        let record = try result.get()
                        guard let asset = record["payload"] as? CKAsset, let file = asset.fileURL else { throw HabitError.invalidBackup("iCloud record has no payload.") }
                        edits.append(try JSONDecoder().decode(Edit.self, from: Data(contentsOf: file)))
                    } catch { failure = error }
                }
                operation.recordZoneFetchResultBlock = { _, result in
                    switch result {
                    case .success(let value): pageToken = value.serverChangeToken; hasMore = value.moreComing
                    case .failure(let error): failure = error
                    }
                }
                operation.fetchRecordZoneChangesResultBlock = { result in
                    if let failure { continuation.resume(throwing: failure) }
                    else {
                        switch result {
                        case .success: continuation.resume(returning: (edits, pageToken, hasMore))
                        case .failure(let error): continuation.resume(throwing: error)
                        }
                    }
                }
                database.add(operation)
            }
            all.append(contentsOf: page.edits); token = page.token; more = page.more
        }
        return all
    }
}

func syncProblem(_ error: Error) -> String {
    guard let cloud = error as? CKError else { return "iCloud: \(error.localizedDescription)" }
    switch cloud.code {
    case .quotaExceeded: return "iCloud storage is full. Free up space or upgrade your iCloud plan."
    case .notAuthenticated: return "Sign in to iCloud in Settings to sync."
    case .networkFailure, .networkUnavailable: return "Offline. Changes are saved locally and will sync when connected."
    case .permissionFailure, .badContainer, .missingEntitlement: return "iCloud configuration needs attention. Check the app’s signing and CloudKit container."
    default: return "iCloud: \(cloud.localizedDescription) Retry when iCloud is available."
    }
}
