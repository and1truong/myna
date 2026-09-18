import SwiftData
import SwiftUI

@main
struct MynaApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Workspace.self, Channel.self, Message.self)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
