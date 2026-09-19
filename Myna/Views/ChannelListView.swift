import SwiftData
import SwiftUI

/// Channels screen: workspace name, filterable channel list, create channel.
/// Drives the split view's content column through `selection` — expanded, the
/// selected row stays highlighted; compact, a tap pushes the channel.
struct ChannelListView: View {
    @Binding var selection: UUID?

    @Environment(NavigationModel.self) private var navigation
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
                    .tag(channel.id)
                }
            }
        }
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
                navigation.selectChannel(channel.id)
            }
        }
    }
}
