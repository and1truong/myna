import SwiftData
import SwiftUI

/// Adaptive root: a three-column `NavigationSplitView`. Expanded (iPad,
/// iPhone landscape where space allows) the columns are channels → channel →
/// thread; compact (iPhone portrait, Split View) it collapses into the same
/// Channels → Channel → Thread stack as before — one `NavigationModel` holds
/// the selections either way.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var navigation = NavigationModel()
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
            ChannelListView(selection: channelSelection)
                // Item-driven presentation: lands in the content column when
                // expanded (a swap, not a push) and pushes when collapsed —
                // one binding drives the channel on both form factors.
                .navigationDestination(item: channelSelection) { channelID in
                    ChannelDestination(channelID: channelID)
                        .id(channelID)
                }
        } content: {
            ContentUnavailableView(
                "Select a channel",
                systemImage: "number",
                description: Text("Pick a channel from the sidebar.")
            )
            // Same mechanism one column further right: the thread appears in
            // the detail column when expanded and pushes when collapsed.
            .navigationDestination(item: $navigation.selectedThreadID) { rootID in
                ThreadView(rootID: rootID)
            }
        } detail: {
            ContentUnavailableView(
                "No thread selected",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Open a thread to follow the conversation here.")
            )
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
        }
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
