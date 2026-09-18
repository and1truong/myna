import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedChannelID: UUID?

    @Query private var channels: [Channel]

    private var selectedChannel: Channel? {
        channels.first { $0.id == selectedChannelID }
    }

    var body: some View {
        NavigationSplitView {
            ChannelListView(selection: $selectedChannelID)
        } detail: {
            NavigationStack {
                if let channel = selectedChannel {
                    ChannelView(channel: channel)
                        .id(channel.id)
                        .navigationDestination(for: UUID.self) { messageID in
                            ThreadView(rootID: messageID)
                        }
                } else {
                    ContentUnavailableView("Select a channel",
                                           systemImage: "number",
                                           description: Text("Pick a channel from the sidebar."))
                }
            }
        }
        .task {
            if channels.isEmpty {
                NoteStore(context: modelContext).seedDefaultChannels()
            }
        }
    }
}
