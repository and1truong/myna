import SwiftData
import SwiftUI

/// Slack's thread pane, pushed full-screen on iPhone: root note on top, replies
/// below, reply composer at the bottom. Agent @mentions work here too — agent
/// responses land as thread replies.
struct ThreadView: View {
    let rootID: UUID

    @Environment(\.dismiss) private var dismiss
    @Query private var matches: [Message]

    init(rootID: UUID) {
        self.rootID = rootID
        _matches = Query(filter: #Predicate<Message> { $0.id == rootID })
    }

    private var root: Message? { matches.first }

    var body: some View {
        Group {
            if let root {
                threadContent(root)
            } else {
                ContentUnavailableView("Note deleted", systemImage: "trash")
            }
        }
        .navigationTitle("Thread")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: matches.isEmpty) { _, gone in
            if gone { dismiss() }
        }
    }

    private func threadContent(_ root: Message) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        MessageRowView(message: root, showsThreadFooter: false)
                            .background(Color.accentColor.opacity(0.06))
                        Divider().padding(.leading, 14)
                        ForEach(root.sortedReplies) { reply in
                            MessageRowView(message: reply, showsThreadFooter: false)
                                .id(reply.id)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    if let last = root.sortedReplies.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            if let channel = root.effectiveChannel {
                ComposerView(channel: channel, root: root)
            }
        }
    }
}
