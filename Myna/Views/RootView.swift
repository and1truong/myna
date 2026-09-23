import SwiftData
import SwiftUI

/// Adaptive root: a three-column `NavigationSplitView`. On Mac, each column
/// renders its selected value directly. On iOS, item destinations preserve
/// the compact Channels → Channel → Thread navigation stack.
@MainActor
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var navigation = NavigationModel()
    private let reminderNavigation = ReminderNavigation.shared
    @Query private var channels: [Channel]

    /// Routes sidebar taps through `selectChannel` so switching channels also
    /// closes a thread belonging to the previous channel.
    private var channelSelection: Binding<UUID?> {
        Binding(
            get: { navigation.selectedChannelID },
            set: { if let id = $0 { navigation.selectChannel(id) } }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $navigation.columnVisibility) {
            #if targetEnvironment(macCatalyst)
            ChannelListView(selection: channelSelection)
            #else
            ChannelListView(selection: channelSelection)
                .navigationDestination(item: channelSelection) { channelID in
                    ChannelDestination(channelID: channelID)
                        .id(channelID)
                }
            #endif
        } content: {
            #if targetEnvironment(macCatalyst)
            if let channelID = navigation.selectedChannelID {
                ChannelDestination(channelID: channelID)
                    .id(channelID)
            } else {
                channelPlaceholder
            }
            #else
            channelPlaceholder
                .navigationDestination(item: $navigation.selectedThreadID) { rootID in
                    ThreadView(rootID: rootID)
                }
            #endif
        } detail: {
            #if targetEnvironment(macCatalyst)
            if let rootID = navigation.selectedThreadID {
                ThreadView(rootID: rootID)
                    .id(rootID)
            } else {
                threadPlaceholder
            }
            #else
            threadPlaceholder
            #endif
        }
        .environment(navigation)
        .task {
            if channels.isEmpty {
                NoteStore(context: modelContext).seedDefaultChannels()
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-seedDemo") {
                DemoSeeder.seed(context: modelContext)
            }
            #endif
            openPendingReminder()
        }
        .onChange(of: reminderNavigation.pendingMessageID) { _, _ in
            openPendingReminder()
        }
    }

    private var channelPlaceholder: some View {
        ContentUnavailableView(
            "Select a channel",
            systemImage: "number",
            description: Text("Pick a channel from the sidebar.")
        )
    }

    private var threadPlaceholder: some View {
        ContentUnavailableView(
            "No thread selected",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("Open a thread to follow the conversation here.")
        )
    }

    private func openPendingReminder() {
        guard let id = reminderNavigation.pendingMessageID else { return }
        guard let destination = NoteStore(context: modelContext)
            .reminderDestination(for: id) else {
            reminderNavigation.pendingMessageID = nil
            return
        }
        navigation.selectChannel(destination.channelID)
        navigation.openThread(destination.rootID,
                              focusMessageID: destination.messageID)
        reminderNavigation.pendingMessageID = nil
    }
}

/// Resolves a channel id to its model so selection stays value-typed.
private struct ChannelDestination: View {
    let channelID: UUID
    @Query private var matches: [Channel]

    init(channelID: UUID) {
        self.channelID = channelID
        _matches = Query(filter: #Predicate<Channel> { $0.id == channelID })
    }

    var body: some View {
        if let channel = matches.first {
            ChannelView(channel: channel)
        } else {
            ContentUnavailableView("Channel deleted", systemImage: "trash")
        }
    }
}
