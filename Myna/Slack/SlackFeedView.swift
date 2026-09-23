import SwiftData
import SwiftUI

struct SlackFeedView: View {
    let channel: Channel
    @Environment(\.modelContext) private var context
    @Query private var allSources: [SlackSource]
    @Query private var allEntries: [SlackEntry]
    @State private var showingSetup = false
    @State private var isSyncing = false
    @State private var error: String?

    private var sources: [SlackSource] { allSources.filter { $0.mynaChannelID == channel.id } }
    private var entries: [SlackEntry] {
        allEntries.filter { $0.mynaChannelID == channel.id }
            .sorted { $0.postedAt > $1.postedAt }
    }

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.red)
            }
            if sources.isEmpty {
                ContentUnavailableView("No Slack channels selected",
                                       systemImage: "number.square",
                                       description: Text("Connect Slack and choose a channel to read here."))
                Button("Set up Slack") { showingSetup = true }
            }
            if !entries.isEmpty {
                Section {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("#\(entry.slackChannelName)")
                                    .font(.subheadline.weight(.semibold))
                                Text("· \(entry.senderName)")
                                    .font(.subheadline)
                                Spacer()
                                Text(entry.postedAt, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.content)
                                .font(.body)
                                .lineLimit(8)
                            if let url = URL(string: entry.permalink) {
                                Link(destination: url) {
                                    Label("Open in Slack", systemImage: "arrow.up.right.square")
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Slack posts")
                } footer: {
                    Text("Refreshes while Myna is open. Slack notifications still come from Slack.")
                }
            } else if !sources.isEmpty {
                Text("No Slack posts imported yet. Tap Refresh to check for new posts.")
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !sources.isEmpty {
                    Button { Task { await refresh() } } label: {
                        if isSyncing { ProgressView() }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(isSyncing)
                    .accessibilityLabel("Refresh Slack")
                }
                Button { showingSetup = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Slack settings")
            }
        }
        .sheet(isPresented: $showingSetup) {
            SlackSetupView(channel: channel)
        }
        .task { if !sources.isEmpty { await refresh() } }
    }

    @MainActor
    private func refresh() async {
        guard !isSyncing else { return }
        guard let token = SlackTokenStore.load() else {
            error = "Add a Slack bot token in Slack settings."
            return
        }
        isSyncing = true
        error = nil
        defer { isSyncing = false }
        do {
            let sync = SlackSync(context: context, api: SlackAPI(token: token))
            for source in sources { _ = try await sync.sync(source) }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct SlackSetupView: View {
    let channel: Channel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var allSources: [SlackSource]
    @State private var tokenDraft = ""
    @State private var hasToken = false
    @State private var available: [SlackConversation] = []
    @State private var isLoading = false
    @State private var error: String?

    private var sources: [SlackSource] { allSources.filter { $0.mynaChannelID == channel.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    SecureField(hasToken ? "Replace saved bot token" : "xoxb-… bot token", text: $tokenDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(hasToken ? "Replace token" : "Save token") {
                        if SlackTokenStore.save(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            hasToken = true
                            tokenDraft = ""
                            error = nil
                        } else {
                            error = "Could not save the token in Keychain."
                        }
                    }
                    .disabled(!tokenDraft.hasPrefix("xoxb-"))
                    if hasToken {
                        Button("Remove token", role: .destructive) {
                            SlackTokenStore.delete()
                            hasToken = false
                            available = []
                        }
                    }
                    Text("Create a Slack app with channels:read and channels:history. Add groups:read and groups:history for private channels. Install it, then invite its bot to each channel you want to read.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Slack channels in #\(channel.name)") {
                    Button { Task { await loadChannels() } } label: {
                        if isLoading { ProgressView() }
                        else { Text("Load channels bot has joined") }
                    }
                    .disabled(!hasToken || isLoading)
                    ForEach(available) { conversation in
                        let selected = sources.first { $0.slackChannelID == conversation.id }
                        Button {
                            if let selected {
                                context.delete(selected)
                            } else {
                                context.insert(SlackSource(mynaChannelID: channel.id,
                                                           slackChannelID: conversation.id,
                                                           slackChannelName: conversation.name))
                            }
                            try? context.save()
                        } label: {
                            HStack {
                                Text("#\(conversation.name)")
                                Spacer()
                                if selected != nil { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    if available.isEmpty && !isLoading {
                        ForEach(sources) { source in
                            Text("#\(source.slackChannelName) selected")
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Slack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { hasToken = SlackTokenStore.load() != nil }
        }
    }

    @MainActor
    private func loadChannels() async {
        guard let token = SlackTokenStore.load() else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            available = try await SlackAPI(token: token).conversations()
        } catch {
            self.error = error.localizedDescription
        }
    }

}
