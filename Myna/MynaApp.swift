import SwiftData
import SwiftUI
import UserNotifications

@main
struct MynaApp: App {
    let container: ModelContainer
    private let reminderDelegate = ReminderNotificationDelegate()

    init() {
        do {
            container = try ModelContainer(for: Workspace.self, Channel.self, Message.self,
                                           RSSFeed.self, RSSImport.self)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
        UNUserNotificationCenter.current().delegate = reminderDelegate
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
