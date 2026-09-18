import SwiftUI

/// A channel hosts tabs — `[ Messages ]` today; Notes, Bookmarks, etc. plug in
/// later without redesigning the channel screen (the V2 extensible boundary).
enum ChannelTab: String, CaseIterable, Identifiable {
    case messages = "Messages"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .messages: return "bubble.left.and.bubble.right"
        }
    }
}

struct ChannelView: View {
    let channel: Channel
    /// Non-nil in a `NavigationSplitView`: a thread tap is reported to the
    /// caller (shown in the detail column) instead of pushed on the stack.
    var onOpenThread: ((UUID) -> Void)? = nil
    @State private var tab: ChannelTab = .messages

    private var roots: [Message] {
        channel.messages
            .filter { !$0.isThreadReply }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            ChannelTabsBar(selection: $tab)
            switch tab {
            case .messages:
                MessageStreamView(channel: channel, roots: roots, onOpenThread: onOpenThread)
            }
        }
        .navigationTitle("#\(channel.name)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ChannelTabsBar: View {
    @Binding var selection: ChannelTab

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(ChannelTab.allCases) { tab in
                        Button {
                            selection = tab
                        } label: {
                            Label(tab.rawValue, systemImage: tab.systemImage)
                                .font(.subheadline.weight(selection == tab ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(selection == tab ? Color.accentColor.opacity(0.12) : .clear)
                                .foregroundStyle(selection == tab ? Color.accentColor : .secondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            Divider()
        }
    }
}

private struct MessageStreamView: View {
    let channel: Channel
    let roots: [Message]
    var onOpenThread: ((UUID) -> Void)? = nil

    @State private var threadID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(roots) { message in
                            MessageRowView(
                                message: message,
                                onReply: {
                                    if let onOpenThread {
                                        onOpenThread(message.id)
                                    } else {
                                        threadID = message.id
                                    }
                                }
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { scrollToEnd(proxy, animated: false) }
                .onChange(of: roots.count) { _, _ in scrollToEnd(proxy, animated: true) }
                .overlay {
                    if roots.isEmpty {
                        ContentUnavailableView(
                            "No notes yet",
                            systemImage: "note.text",
                            description: Text("Capture your first thought below.")
                        )
                    }
                }
            }
            ComposerView(channel: channel)
        }
        .navigationDestination(item: $threadID) { id in
            ThreadView(rootID: id)
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = roots.last else { return }
        if animated {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}
