import SwiftData
import SwiftUI

/// Sidebar: workspace name, channel list with filter, create channel.
/// `selection` carries the selected channel id to the detail column.
struct ChannelListView: View {
    @Binding var selection: UUID?

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
        List(selection: $selection) {
            Section("Channels") {
                ForEach(filtered) { channel in
                    Label {
                        Text(channel.name)
                    } icon: {
                        Image(systemName: "number")
                            .foregroundStyle(.secondary)
                    }
                    .tag(channel.id)
                }
            }
        }
        .listStyle(.sidebar)
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
                selection = channel.id
            }
        }
    }
}
