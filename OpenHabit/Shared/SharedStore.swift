import Foundation
import OpenHabitCore
import WidgetKit

let appGroupID = "group.com.alex.openhabit"
let cloudContainerID = "iCloud.com.alex.openhabit"

func sharedStore() throws -> LocalStore {
    guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
        throw HabitError.storageUnavailable
    }
    return LocalStore(directory: url.appendingPathComponent("OpenHabit", isDirectory: true))
}

func performLocalEdit(_ edit: (inout Journal) throws -> Void) throws {
    try sharedStore().transaction(edit)
    WidgetCenter.shared.reloadAllTimelines()
}
