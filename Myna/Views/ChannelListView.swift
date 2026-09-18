import SwiftData
import SwiftUI

/// Channels screen: workspace name, filterable channel list, create channel.
struct ChannelListView: View {
    /// Called after a new channel is created so the caller can navigate to it.
    var onCreate: (UUID) -> Void = { _ in }
    /// Non-nil in a `NavigationSplitView` sidebar: rows become selection-driven
    /// instead of `NavigationLink` pushes.
    var selection: Binding<UUID?>? = nil

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Channel.position) private var channels: [Channel]
    @State private var filter = ""
    @State private var showingNewChannel = false

    private var filtered: [Channel] {
        let f = filter.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return channels }
        return channels.filter { $0.name.localizedCaseInsensitiveContains(f) }
    }

    var body: some View {
        list
        .listStyle(.plain)
        .searchable(text: $filter, prompt: "Filter channels")
        .navigationTitle("My Notes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNewChannel = true } label: {
                    Image(systemName: "plus")
                }
            }
            #if DEBUG
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button("Seed demo data") { DemoSeeder.seed(context: modelContext) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            #endif
        }
        .sheet(isPresented: $showingNewChannel) {
            NewChannelSheet { channel in
                onCreate(channel.id)
            }
        }
    }

    @ViewBuilder private var list: some View {
        if let selection {
            List(selection: selection) {
                channelRows
            }
        } else {
            List {
                channelRows
            }
        }
    }

    @ViewBuilder private var channelRows: some View {
        Section("Channels") {
            ForEach(filtered) { channel in
                if selection != nil {
                    row(channel)
                        .tag(channel.id)
                } else {
                    NavigationLink(value: Route.channel(channel.id)) {
                        row(channel)
                    }
                }
            }
        }
    }

    private func row(_ channel: Channel) -> some View {
        Label {
            HStack {
                Text(channel.name)
                Spacer()
                if !channel.messages.isEmpty {
                    Text("\(channel.messages.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: "number")
                .foregroundStyle(.secondary)
        }
    }
}
