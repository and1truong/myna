import SwiftData
import SwiftUI

/// Adaptive layout: a three-pane `NavigationSplitView` (channels | channel |
/// thread) at regular width, and the iPhone adaptation — a `NavigationStack`
/// pushing channel then thread — at compact width. One `Route` enum keeps
/// channel and message destinations distinct on the compact path.
enum Route: Hashable {
    case channel(UUID)
    case thread(UUID)
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var path = NavigationPath()
    @State private var selectedChannelID: UUID?
    @State private var selectedThreadID: UUID?
    @Query private var channels: [Channel]

    var body: some View {
        Group {
            if sizeClass == .regular {
                splitView
            } else {
                stackView
            }
        }
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

    private var stackView: some View {
        NavigationStack(path: $path) {
            ChannelListView { channelID in
                path.append(Route.channel(channelID))
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .channel(let id):
                    ChannelDestination(channelID: id)
                case .thread(let id):
                    ThreadView(rootID: id)
                }
            }
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            ChannelListView(
                onCreate: { selectedChannelID = $0 },
                selection: $selectedChannelID
            )
        } content: {
            if let channelID = selectedChannelID {
                ChannelDestination(channelID: channelID) {
                    selectedThreadID = $0
                }
            } else {
                ContentUnavailableView("Select a channel", systemImage: "number")
            }
        } detail: {
            if let threadID = selectedThreadID {
                ThreadView(rootID: threadID)
            } else {
                ContentUnavailableView(
                    "Select a note to view its thread",
                    systemImage: "bubble.left.and.bubble.right"
                )
            }
        }
        .onChange(of: selectedChannelID) { _, _ in
            selectedThreadID = nil
        }
    }
}

/// Resolves a channel id to its model so routes stay value-typed.
private struct ChannelDestination: View {
    let channelID: UUID
    let onOpenThread: ((UUID) -> Void)?
    @Query private var matches: [Channel]

    init(channelID: UUID, onOpenThread: ((UUID) -> Void)? = nil) {
        self.channelID = channelID
        self.onOpenThread = onOpenThread
        _matches = Query(filter: #Predicate<Channel> { $0.id == channelID })
    }

    var body: some View {
        if let channel = matches.first {
            ChannelView(channel: channel, onOpenThread: onOpenThread)
        } else {
            ContentUnavailableView("Channel deleted", systemImage: "trash")
        }
    }
}
