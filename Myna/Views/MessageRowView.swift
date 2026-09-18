import SwiftUI

/// Identifiable wrapper so sheets can be presented for a message.
enum MessageSheet: Identifiable {
    case edit(Message)
    case move(Message)

    var id: UUID {
        switch self {
        case .edit(let message), .move(let message): return message.id
        }
    }
}

/// One note in the stream: avatar, author, timestamp, markdown body, thread
/// footer, and the context actions (Reply / Edit / Move / Delete).
struct MessageRowView: View {
    let message: Message
    /// Hides the "N replies" footer inside the thread itself.
    var showsThreadFooter: Bool = true
    /// Opens the thread for this root message — pushes on the stack at compact
    /// width, fills the split-view detail column at regular width.
    var onReply: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var sheet: MessageSheet?
    @State private var confirmingDelete = false

    private var displayName: String {
        if message.authorType == .agent {
            return AgentRegistry.default.agent(byID: message.authorID)?.displayName
                ?? "@\(message.authorID)"
        }
        return "Hong"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(authorType: message.authorType, displayName: displayName)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(message.createdAt, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Group {
                    if message.isPending {
                        MarkdownText(message.content)
                            .italic()
                            .foregroundStyle(.secondary)
                    } else {
                        MarkdownText(message.content)
                    }
                }
                .font(.body)

                if message.isPending {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if showsThreadFooter && !message.isThreadReply && message.replyCount > 0 {
                    Button { onReply?() } label: {
                        Label("\(message.replyCount) \(message.replyCount == 1 ? "reply" : "replies")",
                              systemImage: "bubble.left.and.bubble.right")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .contextMenu { actions }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .edit(let message):
                EditMessageSheet(message: message)
            case .move(let message):
                MoveToChannelSheet(message: message)
            }
        }
        .confirmationDialog("Delete this note and its thread?",
                            isPresented: $confirmingDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                NoteStore(context: modelContext).delete(message)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var actions: some View {
        if let onReply {
            Button { onReply() } label: {
                Label("Reply in thread", systemImage: "bubble.left.and.bubble.right")
            }
        }
        Button { sheet = .edit(message) } label: {
            Label("Edit", systemImage: "pencil")
        }
        if !message.isThreadReply {
            Button { sheet = .move(message) } label: {
                Label("Move to channel…", systemImage: "arrow.right.doc.on.clipboard")
            }
        }
        Button(role: .destructive) { confirmingDelete = true } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
