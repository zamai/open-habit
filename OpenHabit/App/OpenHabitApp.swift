import SwiftUI
import UIKit
import WidgetKit
import CloudKit

@MainActor
final class ShareAcceptanceBroker {
    static let shared = ShareAcceptanceBroker()
    private var metadata: CKShare.Metadata?

    func put(_ metadata: CKShare.Metadata) { self.metadata = metadata }
    func take() -> CKShare.Metadata? {
        defer { metadata = nil }
        return metadata
    }
}

extension Notification.Name {
    static let sharedHabitInvitationAccepted = Notification.Name("SharedHabitInvitationAccepted")
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            do { _ = try await CloudSync.shared.synchronize(); WidgetCenter.shared.reloadAllTimelines(); completionHandler(.newData) }
            catch { completionHandler(.failed) }
        }
    }

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        ShareAcceptanceBroker.shared.put(metadata)
        NotificationCenter.default.post(name: .sharedHabitInvitationAccepted, object: nil)
    }
}

@main
struct OpenHabitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            OverviewView()
                .environment(model)
                .preferredColorScheme(model.colorScheme)
                .tint(.green)
                .task {
                    model.reload()
                    await model.preparePendingShare()
                    await model.sync()
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(45))
                        guard !Task.isCancelled else { break }
                        if scenePhase == .active { await model.sync(sharedHabits: false) }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.reload(); Task { await model.preparePendingShare(); await model.sync() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: .sharedHabitInvitationAccepted)) { _ in
                    Task { await model.preparePendingShare() }
                }
                .alert("Couldn’t save this change", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                    Button("OK") { model.error = nil }
                } message: { Text(model.error ?? "") }
        }
    }
}
