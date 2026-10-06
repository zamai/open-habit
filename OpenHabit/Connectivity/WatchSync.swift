import Foundation
import WatchConnectivity
import OpenHabitCore
import OSLog
#if os(iOS)
import UIKit
#endif

extension Notification.Name {
    static let watchJournalChanged = Notification.Name("WatchJournalChanged")
}

// Both devices persist their own journal. Exchanging edits preserves offline additions,
// deletion markers and replacement generations; a received snapshot never replaces a store.
final class WatchSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSync()
    private let queue = DispatchQueue(label: "com.alex.openhabit.watch-sync")
    private let logger = Logger(subsystem: "com.alex.openhabit", category: "WatchSync")
    private var lastSent: Data?

    private var store: LocalStore {
        get throws {
            #if os(watchOS)
            return watchStore()
            #else
            return try sharedStore()
            #endif
        }
    }

    func start() {
        guard WCSession.isSupported() else {
            logger.info("Watch Connectivity is unavailable")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func publish(force: Bool = false) {
        guard WCSession.isSupported() else { return }
        queue.async { self.send(force: force) }
    }

    private func send(force: Bool) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else {
            logger.debug("Watch not ready: paired=\(session.isPaired) installed=\(session.isWatchAppInstalled)")
            return
        }
        #endif
        do {
            let journal = try store.read()
            guard !journal.edits.isEmpty else { return }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let payload = try encoder.encode(journal.edits.sorted { $0.id.uuidString < $1.id.uuidString })
            guard force || payload != lastSent else { return }
            // Small journals use a replaceable background context and immediate delivery.
            // File transfer keeps a long history from exceeding message/context size limits.
            if payload.count < 60_000 {
                try session.updateApplicationContext(["edits": payload])
                if session.isReachable {
                    session.sendMessageData(payload, replyHandler: nil) { [logger] _ in
                        logger.info("Immediate Watch sync unavailable; background delivery is queued")
                    }
                }
            } else {
                let directory = try store.directory.appendingPathComponent("WatchTransfers", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let file = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
                try payload.write(to: file, options: .atomic)
                session.transferFile(file, metadata: ["openHabitJournal": true])
            }
            lastSent = payload
        } catch { logger.error("Could not queue Watch synchronization: \(error.localizedDescription, privacy: .public)") }
    }

    private func receive(_ payload: Data) {
        #if os(iOS)
        // Establish the assertion on the main thread before queuing any file-lock work.
        DispatchQueue.main.async {
            let cancellation = Progress(totalUnitCount: 1)
            var task = UIBackgroundTaskIdentifier.invalid
            task = UIApplication.shared.beginBackgroundTask(withName: "Receive Watch journal") {
                cancellation.cancel()
                // A running transaction observes cancellation before committing and ends
                // the assertion after releasing its lock. Queued work never takes the lock.
            }
            guard task != .invalid else {
                self.logger.info("Background time unavailable for Watch journal receive")
                return
            }
            self.applyReceived(payload, cancellation: cancellation) {
                DispatchQueue.main.async { UIApplication.shared.endBackgroundTask(task) }
            }
        }
        #else
        applyReceived(payload, cancellation: Progress(totalUnitCount: 1), completion: {})
        #endif
    }

    private func applyReceived(_ payload: Data, cancellation: Progress, completion: @escaping () -> Void) {
        queue.async {
            do {
                defer { completion() }
                guard !cancellation.isCancelled else { return }
                let edits = try JSONDecoder().decode([Edit].self, from: payload)
                guard !cancellation.isCancelled else { return }
                try self.store.transaction(cancellation: cancellation) { $0.merge(edits) }
            } catch is CancellationError {
                self.logger.info("Watch journal receive expired before committing")
                return
            } catch {
                self.logger.error("Could not apply Watch synchronization: \(error.localizedDescription, privacy: .public)")
                return
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .watchJournalChanged, object: nil)
            }
            self.send(force: false)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        logger.info("Watch session activated: \(activationState.rawValue)")
        guard activationState == .activated else { return }
        if let payload = session.receivedApplicationContext["edits"] as? Data { receive(payload) }
        publish(force: true)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable { publish(force: true) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let payload = applicationContext["edits"] as? Data { receive(payload) }
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data) { receive(messageData) }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?["openHabitJournal"] as? Bool == true else { return }
        // WCSession removes the incoming URL after this delegate method returns.
        do { receive(try Data(contentsOf: file.fileURL)) }
        catch { logger.error("Could not read Watch journal transfer") }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        queue.async {
            try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
            if error != nil { self.lastSent = nil }
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func sessionWatchStateDidChange(_ session: WCSession) { publish(force: true) }
    #endif
}
