import SwiftData
import SwiftUI

/// Channel Settings keeps subscriptions attached to this channel's message stream.
struct RSSFeedSettingsView: View {
    let channel: Channel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RSSFeed.addedAt) private var allFeeds: [RSSFeed]
    @State private var feedURL = ""
    @State private var isSubscribing = false
    @State private var refreshingIDs: Set<UUID> = []
    @State private var feedback: String?
    @State private var errorMessage: String?

    private var feeds: [RSSFeed] {
        allFeeds.filter { $0.channelID == channel.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Subscribe RSS or Atom") {
                    TextField("https://example.com/feed.xml", text: $feedURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Feed URL")
                    Button("Subscribe to #\(channel.name)") {
                        isSubscribing = true
                        Task {
                            do {
                                let feed = try await RSSStore(context: modelContext)
                                    .addFeed(feedURL, to: channel)
                                feedback = "Subscribed \(feed.title). Future articles will post in this channel."
                                feedURL = ""
                            } catch { errorMessage = error.localizedDescription }
                            isSubscribing = false
                        }
                    }
                    .disabled(feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubscribing)
                    if isSubscribing { ProgressView("Checking feed…") }
                }

                Section("Feeds in #\(channel.name)") {
                    if feeds.isEmpty {
                        Text("No feeds subscribed.").foregroundStyle(.secondary)
                    }
                    ForEach(feeds) { feed in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(feed.title).font(.headline)
                            Text(feed.url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)

                            Toggle("Paused", isOn: Binding(
                                get: { feed.isPaused },
                                set: { paused in
                                    do { try RSSStore(context: modelContext).setPaused(feed, to: paused) }
                                    catch {
                                        feed.isPaused = !paused
                                        errorMessage = error.localizedDescription
                                    }
                                }
                            ))

                            Picker("Check for updates", selection: Binding(
                                get: { feed.refreshIntervalSeconds },
                                set: { seconds in
                                    guard let frequency = RSSRefreshFrequency(rawValue: seconds) else { return }
                                    let previous = feed.refreshIntervalSeconds
                                    do { try RSSStore(context: modelContext).setFrequency(feed, to: frequency) }
                                    catch {
                                        feed.refreshIntervalSeconds = previous
                                        errorMessage = error.localizedDescription
                                    }
                                }
                            )) {
                                ForEach(RSSRefreshFrequency.allCases) { frequency in
                                    Text(frequency.label).tag(frequency.rawValue)
                                }
                            }
                            .pickerStyle(.menu)

                            HStack {
                                Button("Refresh now") {
                                    refreshingIDs.insert(feed.id)
                                    Task {
                                        do {
                                            let count = try await RSSStore(context: modelContext)
                                                .refresh(feed, in: channel)
                                            feedback = "\(feed.title): \(count) new \(count == 1 ? "article" : "articles") posted."
                                        } catch { errorMessage = error.localizedDescription }
                                        refreshingIDs.remove(feed.id)
                                    }
                                }
                                .disabled(refreshingIDs.contains(feed.id))
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    do {
                                        try RSSStore(context: modelContext).remove(feed)
                                        feedback = "Feed removed. Existing posts and threads remain."
                                    } catch { errorMessage = error.localizedDescription }
                                }
                            }
                            .font(.subheadline)
                            if refreshingIDs.contains(feed.id) { ProgressView().controlSize(.small) }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Text("Myna checks active feeds while this channel is open and the app is in the foreground, including when you return to the app. The interval sets when a feed is eligible to check; iOS does not guarantee exact background timing. Refresh now also checks paused feeds.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let feedback { Text(feedback).font(.footnote) }
                }
            }
            .navigationTitle("Channel Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Feed error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }
}
