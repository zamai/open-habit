import SwiftUI
import UIKit
import WidgetKit

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
                    await model.sync()
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(45))
                        guard !Task.isCancelled else { break }
                        if scenePhase == .active { await model.sync() }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.reload(); Task { await model.sync() } }
                }
                .alert("Couldn’t save this change", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                    Button("OK") { model.error = nil }
                } message: { Text(model.error ?? "") }
        }
    }
}
