import CloudKit
import Foundation
import OpenHabitCore

enum SharedHabitCloudError: LocalizedError {
    case requiresDevice
    case requiresIOS18
    case unavailable
    case full
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .requiresDevice: "Shared Habits require a signed iPhone or iPad with iCloud."
        case .requiresIOS18: "Single-use Shared Habit invitations require iOS 18 or later."
        case .unavailable: "This Shared Habit is no longer available. Your personal Habit and history are unchanged."
        case .full: "This Shared Habit already has ten Members or pending Invitations."
        case .invalidResponse: "iCloud returned incomplete Shared Habit data. Try again."
        }
    }
}

struct SharedHabitJoinOffer: Identifiable {
    var id: UUID { snapshot.id }
    let snapshot: SharedHabitSnapshot
    let zoneName: String
    let zoneOwnerName: String
    let shareRecordName: String
}

actor SharedCloudSync {
    static let shared = SharedCloudSync()

    private enum RecordName {
        static let habit = "SharedHabit-"
        static let member = "SharedMember-"
        static let progress = "SharedProgress-"
        static let membership = "SharedMembership-"
    }

    func privateStates() async throws -> [SharedHabitState] {
        let container = try await availableContainer()
        let zoneID = CKRecordZone.ID(zoneName: "OpenHabit", ownerName: CKCurrentUserDefaultName)
        let records = try await fetchAll(in: zoneID, database: container.privateCloudDatabase)
        return try records.filter { $0.recordID.recordName.hasPrefix(RecordName.membership) }.map { record in
            let state: SharedHabitState = try decodedPayload(record)
            try state.validate()
            return state
        }
    }

    func savePrivateState(_ state: SharedHabitState) async throws {
        try state.validate()
        let container = try await availableContainer()
        let zoneID = CKRecordZone.ID(zoneName: "OpenHabit", ownerName: CKCurrentUserDefaultName)
        let (record, file) = try payloadRecord(state, recordID: privateStateRecordID(state.membership.sharedHabitID, zoneID: zoneID))
        defer { try? FileManager.default.removeItem(at: file) }
        let result = try await container.privateCloudDatabase.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys, atomically: true)
        for value in result.saveResults.values { _ = try value.get() }
    }

    func deletePrivateState(_ sharedHabitID: UUID) async throws {
        let container = try await availableContainer()
        let zoneID = CKRecordZone.ID(zoneName: "OpenHabit", ownerName: CKCurrentUserDefaultName)
        do { _ = try await container.privateCloudDatabase.deleteRecord(withID: privateStateRecordID(sharedHabitID, zoneID: zoneID)) }
        catch let error as CKError where error.code == .unknownItem {}
    }

    func create(
        habit: Habit,
        dataset: Dataset,
        memberName: String,
        history: SharedHistoryChoice
    ) async throws -> SharedHabitState {
        let container = try await availableContainer()
        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: "OpenHabit", ownerName: CKCurrentUserDefaultName)
        _ = try await database.save(CKRecordZone(zoneID: zoneID))

        var definition = SharedHabitDefinition(habit: habit, weekStart: effectiveWeekStart(dataset.settings.weekStart))
        let rootID = CKRecord.ID(recordName: "\(RecordName.habit)\(definition.id.uuidString)", zoneID: zoneID)
        let (root, rootFile) = try payloadRecord(definition, recordID: rootID)

        let userRecordName = try await container.userRecordID().recordName
        let member = SharedMember(name: memberName.trimmingCharacters(in: .whitespacesAndNewlines), colorIndex: 0, role: .owner, cloudUserRecordName: userRecordName)
        try member.validate()
        let (memberRecord, memberFile) = try payloadRecord(member, recordID: memberRecordID(member.id, zoneID: zoneID), parent: rootID)

        let visibleFromDay = history == .startFresh ? LocalDay.string() : nil
        let counts = dataset.sharedCounts(for: habit.id, visibleFromDay: visibleFromDay)
        let (progress, progressFile) = try payloadRecord(counts, recordID: progressRecordID(member.id, zoneID: zoneID), parent: rootID)
        let files = [rootFile, memberFile, progressFile]
        defer { for file in files { try? FileManager.default.removeItem(at: file) } }

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = habit.name
        share.publicPermission = .none

        let result = try await database.modifyRecords(saving: [root, memberRecord, progress, share], deleting: [], savePolicy: .allKeys, atomically: true)
        for value in result.saveResults.values { _ = try value.get() }
        guard let savedShare = try result.saveResults[share.recordID]?.get() as? CKShare else {
            throw SharedHabitCloudError.invalidResponse
        }

        definition.id = UUID(uuidString: String(rootID.recordName.dropFirst(RecordName.habit.count))) ?? definition.id
        let membership = SharedHabitMembership(
            sharedHabitID: definition.id,
            localHabitID: habit.id,
            memberID: member.id,
            role: .owner,
            visibleFromDay: visibleFromDay,
            zoneName: rootID.zoneID.zoneName,
            zoneOwnerName: rootID.zoneID.ownerName,
            shareRecordName: savedShare.recordID.recordName
        )
        var memberWithCounts = member
        memberWithCounts.counts = counts
        return SharedHabitState(membership: membership, snapshot: SharedHabitSnapshot(definition: definition, members: [memberWithCounts]))
    }

    func synchronize(_ state: SharedHabitState, dataset: Dataset) async throws -> SharedHabitState {
        let container = try await availableContainer()
        let membership = state.membership
        let zoneID = CKRecordZone.ID(zoneName: membership.zoneName, ownerName: membership.zoneOwnerName)
        let database = membership.role == .owner ? container.privateCloudDatabase : container.sharedCloudDatabase
        let rootID = CKRecord.ID(recordName: "\(RecordName.habit)\(membership.sharedHabitID.uuidString)", zoneID: zoneID)

        guard let localHabit = dataset.habit(membership.localHabitID) else { return state }
        var ownMember = state.snapshot.members.first(where: { $0.id == membership.memberID })
        ownMember?.counts = dataset.sharedCounts(for: membership.localHabitID, visibleFromDay: membership.visibleFromDay)

        var saving: [CKRecord] = []
        var files: [URL] = []
        defer { for file in files { try? FileManager.default.removeItem(at: file) } }
        if membership.role == .owner {
            var definition = SharedHabitDefinition(habit: localHabit, weekStart: state.snapshot.definition.weekStart)
            definition.id = membership.sharedHabitID
            let (root, file) = try payloadRecord(definition, recordID: rootID)
            saving.append(root)
            files.append(file)
        }
        if let ownMember {
            var identity = ownMember
            identity.counts = [:]
            let (memberRecord, memberFile) = try payloadRecord(identity, recordID: memberRecordID(ownMember.id, zoneID: zoneID), parent: rootID)
            saving.append(memberRecord)
            files.append(memberFile)

            let (progress, progressFile) = try payloadRecord(ownMember.counts, recordID: progressRecordID(ownMember.id, zoneID: zoneID), parent: rootID)
            saving.append(progress)
            files.append(progressFile)
        }
        if !saving.isEmpty {
            let result = try await database.modifyRecords(saving: saving, deleting: [], savePolicy: .changedKeys, atomically: true)
            for value in result.saveResults.values { _ = try value.get() }
        }

        let records = try await fetchAll(in: zoneID, database: database)
        guard let root = records.first(where: { $0.recordID == rootID }) else {
            throw SharedHabitCloudError.unavailable
        }
        let definition: SharedHabitDefinition = try decodedPayload(root)
        var members = try records.filter {
            $0.recordID.recordName.hasPrefix(RecordName.member) && $0.parent?.recordID == rootID
        }.map { record -> SharedMember in
            try decodedPayload(record)
        }
        let progressByMember: [UUID: [String: Int]] = try Dictionary(uniqueKeysWithValues: records.filter {
            $0.recordID.recordName.hasPrefix(RecordName.progress) && $0.parent?.recordID == rootID
        }.map { record in
            guard let id = recordUUID(record, prefix: RecordName.progress) else {
                throw SharedHabitCloudError.invalidResponse
            }
            let counts: [String: Int] = try decodedPayload(record)
            return (id, counts)
        })
        for index in members.indices { members[index].counts = progressByMember[members[index].id] ?? [:] }

        var invitations = state.snapshot.invitations
        if membership.role == .owner {
            let shareID = CKRecord.ID(recordName: membership.shareRecordName, zoneID: zoneID)
            if let share = try await database.record(for: shareID) as? CKShare {
                let memberCloudUsers = Set(members.compactMap(\.cloudUserRecordName))
                let pendingIDs = Set(share.participants.filter { participant in
                    guard participant.role != .owner else { return false }
                    return participant.userIdentity.userRecordID.map { !memberCloudUsers.contains($0.recordName) } ?? true
                }.map(\.participantID))
                invitations = invitations.filter { pendingIDs.contains($0.id) }
                for id in pendingIDs where !invitations.contains(where: { $0.id == id }) { invitations.append(SharedInvitation(id: id)) }
            }
        }
        let snapshot = SharedHabitSnapshot(definition: definition, members: members, invitations: invitations)
        try snapshot.validate()
        return SharedHabitState(membership: membership, snapshot: snapshot)
    }

    @available(iOS 18.0, *)
    func createInvitation(for state: SharedHabitState) async throws -> (SharedHabitState, URL) {
        guard state.membership.role == .owner else { throw SharedHabitCloudError.unavailable }
        guard state.snapshot.members.count + state.snapshot.invitations.count < 10 else { throw SharedHabitCloudError.full }
        let container = try await availableContainer()
        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: state.membership.zoneName, ownerName: state.membership.zoneOwnerName)
        let shareID = CKRecord.ID(recordName: state.membership.shareRecordName, zoneID: zoneID)
        guard let share = try await database.record(for: shareID) as? CKShare else { throw SharedHabitCloudError.unavailable }
        guard share.participants.count < 10 else { throw SharedHabitCloudError.full }
        let participant = CKShare.Participant.oneTimeURLParticipant()
        participant.role = .privateUser
        participant.permission = .readWrite
        share.addParticipant(participant)
        guard let saved = try await database.save(share) as? CKShare,
              let url = oneTimeURL(from: saved, participantID: participant.participantID) else {
            throw SharedHabitCloudError.invalidResponse
        }
        var result = state
        result.snapshot.invitations.append(SharedInvitation(id: participant.participantID))
        return (result, url)
    }

    func accept(_ metadata: CKShare.Metadata) async throws -> SharedHabitJoinOffer {
        let container = try await availableContainer()
        let accepted = try await container.accept([metadata])
        guard let share = try accepted[metadata]?.get() else { throw SharedHabitCloudError.invalidResponse }
        guard let rootID = metadata.hierarchicalRootRecordID else { throw SharedHabitCloudError.invalidResponse }
        let zoneID = rootID.zoneID
        let records = try await fetchAll(in: zoneID, database: container.sharedCloudDatabase)
        guard let root = records.first(where: { $0.recordID == rootID }) else {
            throw SharedHabitCloudError.invalidResponse
        }
        let definition: SharedHabitDefinition = try decodedPayload(root)
        var members = try records.filter {
            $0.recordID.recordName.hasPrefix(RecordName.member) && $0.parent?.recordID == rootID
        }.map { record -> SharedMember in
            try decodedPayload(record)
        }
        let progressByMember: [UUID: [String: Int]] = try Dictionary(uniqueKeysWithValues: records.filter {
            $0.recordID.recordName.hasPrefix(RecordName.progress) && $0.parent?.recordID == rootID
        }.map { record in
            guard let id = recordUUID(record, prefix: RecordName.progress) else {
                throw SharedHabitCloudError.invalidResponse
            }
            let counts: [String: Int] = try decodedPayload(record)
            return (id, counts)
        })
        for index in members.indices { members[index].counts = progressByMember[members[index].id] ?? [:] }
        let snapshot = SharedHabitSnapshot(definition: definition, members: members)
        try snapshot.validate()
        guard snapshot.members.count < 10 else { throw SharedHabitCloudError.full }
        return SharedHabitJoinOffer(
            snapshot: snapshot,
            zoneName: zoneID.zoneName,
            zoneOwnerName: zoneID.ownerName,
            shareRecordName: share.recordID.recordName
        )
    }

    func join(
        _ offer: SharedHabitJoinOffer,
        localHabitID: UUID,
        memberName: String,
        counts: [String: Int],
        visibleFromDay: String?
    ) async throws -> SharedHabitState {
        let container = try await availableContainer()
        guard let colorIndex = SharedMember.nextColorIndex(usedBy: offer.snapshot.members) else { throw SharedHabitCloudError.full }
        let zoneID = CKRecordZone.ID(zoneName: offer.zoneName, ownerName: offer.zoneOwnerName)
        let rootID = CKRecord.ID(recordName: "\(RecordName.habit)\(offer.id.uuidString)", zoneID: zoneID)
        let member = SharedMember(
            name: memberName.trimmingCharacters(in: .whitespacesAndNewlines),
            colorIndex: colorIndex,
            role: .member,
            cloudUserRecordName: try await container.userRecordID().recordName
        )
        try member.validate()
        let (memberRecord, memberFile) = try payloadRecord(member, recordID: memberRecordID(member.id, zoneID: zoneID), parent: rootID)
        let (progress, progressFile) = try payloadRecord(counts, recordID: progressRecordID(member.id, zoneID: zoneID), parent: rootID)
        let files = [memberFile, progressFile]
        defer { for file in files { try? FileManager.default.removeItem(at: file) } }
        let result = try await container.sharedCloudDatabase.modifyRecords(saving: [memberRecord, progress], deleting: [], savePolicy: .allKeys, atomically: true)
        for value in result.saveResults.values { _ = try value.get() }

        let membership = SharedHabitMembership(
            sharedHabitID: offer.id,
            localHabitID: localHabitID,
            memberID: member.id,
            role: .member,
            visibleFromDay: visibleFromDay,
            zoneName: offer.zoneName,
            zoneOwnerName: offer.zoneOwnerName,
            shareRecordName: offer.shareRecordName
        )
        var snapshot = offer.snapshot
        var memberWithCounts = member
        memberWithCounts.counts = counts
        snapshot.members.append(memberWithCounts)
        snapshot.updatedAt = Date()
        try snapshot.validate()
        return SharedHabitState(membership: membership, snapshot: snapshot)
    }

    func decline(_ offer: SharedHabitJoinOffer) async throws {
        let container = try await availableContainer()
        let zoneID = CKRecordZone.ID(zoneName: offer.zoneName, ownerName: offer.zoneOwnerName)
        let shareID = CKRecord.ID(recordName: offer.shareRecordName, zoneID: zoneID)
        _ = try await container.sharedCloudDatabase.deleteRecord(withID: shareID)
    }

    func leave(_ state: SharedHabitState) async throws {
        guard state.membership.role == .member else { throw SharedHabitCloudError.unavailable }
        let container = try await availableContainer()
        let zoneID = CKRecordZone.ID(zoneName: state.membership.zoneName, ownerName: state.membership.zoneOwnerName)
        let database = container.sharedCloudDatabase
        let memberID = state.membership.memberID
        let result = try await database.modifyRecords(
            saving: [],
            deleting: [memberRecordID(memberID, zoneID: zoneID), progressRecordID(memberID, zoneID: zoneID)],
            savePolicy: .allKeys,
            atomically: true
        )
        for value in result.deleteResults.values { _ = try value.get() }
        let shareID = CKRecord.ID(recordName: state.membership.shareRecordName, zoneID: zoneID)
        _ = try await database.deleteRecord(withID: shareID)
    }

    func stopSharing(_ state: SharedHabitState) async throws {
        guard state.membership.role == .owner else { throw SharedHabitCloudError.unavailable }
        let container = try await availableContainer()
        let zoneID = CKRecordZone.ID(zoneName: state.membership.zoneName, ownerName: state.membership.zoneOwnerName)
        let database = container.privateCloudDatabase
        let rootID = CKRecord.ID(recordName: "\(RecordName.habit)\(state.membership.sharedHabitID.uuidString)", zoneID: zoneID)
        let shareID = CKRecord.ID(recordName: state.membership.shareRecordName, zoneID: zoneID)
        let childIDs = try await fetchAll(in: zoneID, database: database)
            .filter { $0.parent?.recordID == rootID }
            .map(\.recordID)
        let result = try await database.modifyRecords(
            saving: [], deleting: childIDs + [shareID, rootID], savePolicy: .allKeys, atomically: true
        )
        for value in result.deleteResults.values { _ = try value.get() }
    }

    func cancelInvitation(_ invitationID: String, in state: SharedHabitState) async throws -> SharedHabitState {
        guard state.membership.role == .owner else { throw SharedHabitCloudError.unavailable }
        let container = try await availableContainer()
        let zoneID = CKRecordZone.ID(zoneName: state.membership.zoneName, ownerName: state.membership.zoneOwnerName)
        let shareID = CKRecord.ID(recordName: state.membership.shareRecordName, zoneID: zoneID)
        guard let share = try await container.privateCloudDatabase.record(for: shareID) as? CKShare,
              let participant = share.participants.first(where: { $0.participantID == invitationID && $0.acceptanceStatus == .pending }) else {
            throw SharedHabitCloudError.unavailable
        }
        share.removeParticipant(participant)
        _ = try await container.privateCloudDatabase.save(share)
        var result = state
        result.snapshot.invitations.removeAll { $0.id == invitationID }
        return result
    }

    func remove(_ member: SharedMember, from state: SharedHabitState) async throws -> SharedHabitState {
        guard state.membership.role == .owner, member.role != .owner,
              let cloudUserRecordName = member.cloudUserRecordName else { throw SharedHabitCloudError.unavailable }
        let container = try await availableContainer()
        let zoneID = CKRecordZone.ID(zoneName: state.membership.zoneName, ownerName: state.membership.zoneOwnerName)
        let database = container.privateCloudDatabase
        let shareID = CKRecord.ID(recordName: state.membership.shareRecordName, zoneID: zoneID)
        guard let share = try await database.record(for: shareID) as? CKShare,
              let participant = share.participants.first(where: { $0.userIdentity.userRecordID?.recordName == cloudUserRecordName }) else {
            throw SharedHabitCloudError.unavailable
        }
        share.removeParticipant(participant)
        let result = try await database.modifyRecords(
            saving: [share],
            deleting: [memberRecordID(member.id, zoneID: zoneID), progressRecordID(member.id, zoneID: zoneID)],
            savePolicy: .allKeys,
            atomically: true
        )
        for value in result.saveResults.values { _ = try value.get() }
        for value in result.deleteResults.values { _ = try value.get() }
        var updated = state
        updated.snapshot.members.removeAll { $0.id == member.id }
        return updated
    }

    private func availableContainer() async throws -> CKContainer {
        let container = CKContainer(identifier: cloudContainerID)
        guard try await container.accountStatus() == .available else { throw CKError(.notAuthenticated) }
        return container
    }

    private func effectiveWeekStart(_ setting: WeekStart) -> WeekStart {
        guard setting == .system else { return setting }
        return Calendar.current.firstWeekday == 2 ? .monday : .sunday
    }

    private func payloadRecord<T: Encodable>(
        _ value: T,
        recordID: CKRecord.ID,
        parent: CKRecord.ID? = nil
    ) throws -> (CKRecord, URL) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try JSONEncoder().encode(value).write(to: file, options: .atomic)
        let record = CKRecord(recordType: "HabitEdit", recordID: recordID)
        record["payload"] = CKAsset(fileURL: file)
        // CloudKit requires its special parent reference to use `.none`; `.deleteSelf` raises an exception.
        if let parent { record.parent = CKRecord.Reference(recordID: parent, action: .none) }
        return (record, file)
    }

    private func decodedPayload<T: Decodable>(_ record: CKRecord) throws -> T {
        guard let asset = record["payload"] as? CKAsset, let file = asset.fileURL else {
            throw SharedHabitCloudError.invalidResponse
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: file))
    }

    private func recordUUID(_ record: CKRecord, prefix: String) -> UUID? {
        guard record.recordID.recordName.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(record.recordID.recordName.dropFirst(prefix.count)))
    }

    private func memberRecordID(_ memberID: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(RecordName.member)\(memberID.uuidString)", zoneID: zoneID)
    }

    private func progressRecordID(_ memberID: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(RecordName.progress)\(memberID.uuidString)", zoneID: zoneID)
    }

    private func privateStateRecordID(_ sharedHabitID: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(RecordName.membership)\(sharedHabitID.uuidString)", zoneID: zoneID)
    }

    private func fetchAll(in zoneID: CKRecordZone.ID, database: CKDatabase) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var token: CKServerChangeToken?
        var more = true
        while more {
            let page: ([CKRecord], CKServerChangeToken?, Bool) = try await withCheckedThrowingContinuation { continuation in
                let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
                configuration.previousServerChangeToken = token
                let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: configuration])
                operation.fetchAllChanges = false
                var changed: [CKRecord] = []
                var pageToken: CKServerChangeToken?
                var hasMore = false
                var failure: Error?
                operation.recordWasChangedBlock = { _, result in
                    do { changed.append(try result.get()) } catch { failure = error }
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
                        case .success: continuation.resume(returning: (changed, pageToken, hasMore))
                        case .failure(let error): continuation.resume(throwing: error)
                        }
                    }
                }
                database.add(operation)
            }
            records.append(contentsOf: page.0)
            token = page.1
            more = page.2
        }
        return records
    }

    @available(iOS 18.0, *)
    private func oneTimeURL(from share: CKShare, participantID: CKShare.Participant.ID) -> URL? {
        if #available(iOS 26.0, *) { return share.oneTimeURL(for: participantID) }

        // Xcode 26 imports this iOS 18 Objective-C API as iOS 26 in Swift. Calling the
        // public selector preserves the API's real iOS 18 availability until that is corrected.
        let selector = NSSelectorFromString("oneTimeURLForParticipantID:")
        guard share.responds(to: selector) else { return nil }
        typealias Implementation = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<NSURL>?
        let implementation = unsafeBitCast(share.method(for: selector), to: Implementation.self)
        return implementation(share, selector, participantID as NSString)?.takeUnretainedValue() as URL?
    }
}
