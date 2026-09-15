import SwiftUI
import UIKit
import WidgetKit
import CloudKit
import OSLog

@MainActor
final class ShareAcceptanceBroker {
    static let shared = ShareAcceptanceBroker()
    static let logger = Logger(subsystem: "com.alex.openhabit", category: "ShareAcceptance")
    private var metadata: CKShare.Metadata?

    func put(_ metadata: CKShare.Metadata) {
        self.metadata = metadata
        NotificationCenter.default.post(name: .sharedHabitInvitationAccepted, object: nil)
    }
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

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ShareSceneDelegate.self
        return configuration
    }
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Task {
            do { _ = try await CloudSync.shared.synchronize(); WidgetCenter.shared.reloadAllTimelines(); completionHandler(.newData) }
            catch { completionHandler(.failed) }
        }
    }

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        ShareAcceptanceBroker.logger.info("Invitation received by app delegate")
        ShareAcceptanceBroker.shared.put(metadata)
    }
}

final class ShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // When an invitation launches the app, iOS supplies it with the new scene.
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        ShareAcceptanceBroker.logger.info("Invitation received while connecting scene")
        ShareAcceptanceBroker.shared.put(metadata)
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        ShareAcceptanceBroker.logger.info("Invitation received by connected window scene")
        ShareAcceptanceBroker.shared.put(metadata)
    }
}

@main
struct OpenHabitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG && targetEnvironment(simulator)
        if SharedHabitJoinPreview.isEnabled {
            _model = State(initialValue: SharedHabitJoinPreview.makeModel(
                withPrivateHabit: !ProcessInfo.processInfo.arguments.contains("--preview-join-empty")
            ))
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            OverviewView()
                .environment(model)
                .preferredColorScheme(model.colorScheme)
                .tint(.green)
                .task {
                    #if DEBUG && targetEnvironment(simulator)
                    if SharedHabitJoinPreview.isEnabled { return }
                    #endif
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
                    #if DEBUG && targetEnvironment(simulator)
                    if SharedHabitJoinPreview.isEnabled { return }
                    #endif
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
