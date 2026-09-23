import SwiftData
import SwiftUI

/// Thread pane — the split view's detail column on Mac and iPad, a push on
/// iPhone: root note on top, replies below, reply composer at the bottom.
/// Agent @mentions work here too — agent responses land as thread replies.
struct ThreadView: View {
    let rootID: UUID

    @Environment(NavigationModel.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
        .toolbar {
            // Compact offers Back; expanded needs an explicit close to return
            // the detail column to its placeholder.
            if showsCloseButton {
                ToolbarItem(placement: .primaryAction) {
                    Button { navigation.closeThread() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close thread")
                }
            }
        }
        .onChange(of: matches.isEmpty) { _, gone in
            if gone {
                navigation.closeThread()
                dismiss()
            }
        }
    }

    private var showsCloseButton: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    private func threadContent(_ root: Message) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        MessageRowView(message: root, showsThreadFooter: false)
                            .background(Color.accentColor.opacity(0.06))
                            .id(root.id)
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
                    if let focused = navigation.focusedMessageID {
                        proxy.scrollTo(focused, anchor: .center)
                    } else if let last = root.sortedReplies.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: navigation.focusedMessageID) { _, focused in
                    if let focused {
                        proxy.scrollTo(focused, anchor: .center)
                    }
                }
            }
            if let channel = root.effectiveChannel {
                ComposerView(channel: channel, root: root)
            }
        }
    }
}
