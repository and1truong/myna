import SwiftData
import SwiftUI

/// iPhone adaptation of the desktop three-pane layout: a channels screen that
/// pushes the channel view, which pushes the thread — one `Route` enum keeps
/// channel and message destinations distinct.
enum Route: Hashable {
    case channel(UUID)
    case thread(UUID)
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var path = NavigationPath()
    @Query private var channels: [Channel]

    var body: some View {
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

/// Resolves a channel id to its model so routes stay value-typed.
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
