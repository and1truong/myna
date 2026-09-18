import Foundation
import SwiftData

/// Domain operations over the SwiftData model context. Views and services go
/// through this store rather than mutating models directly.
final class NoteStore {
    static let humanAuthorID = "me"
    static let defaultChannelNames = [
        "inbox", "ideas", "engineering", "bible-study", "reading", "random",
    ]

    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Workspace & channels

    @discardableResult
    func ensureWorkspace(named name: String = "My Notes") -> Workspace {
        if let existing = try? context.fetch(FetchDescriptor<Workspace>()).first {
            return existing
        }
        let workspace = Workspace(name: name)
        context.insert(workspace)
        return workspace
    }

    @discardableResult
    func createChannel(name rawName: String) -> Channel {
        let name = Self.normalizeChannelName(rawName)
        let workspace = ensureWorkspace()
        if let existing = workspace.channels.first(where: { $0.name == name }) {
            return existing
        }
        let channel = Channel(name: name, position: workspace.channels.count, workspace: workspace)
        context.insert(channel)
        return channel
    }

    func seedDefaultChannels() {
        ensureWorkspace()
        for name in Self.defaultChannelNames {
            createChannel(name: name)
        }
        save()
    }

    static func normalizeChannelName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacing(#/\s+/#, with: "-")
    }

    // MARK: - Messages

    @discardableResult
    func postMessage(_ content: String,
                     in channel: Channel,
                     authorType: AuthorType = .human,
                     authorID: String = humanAuthorID,
                     isPending: Bool = false) -> Message {
        let message = Message(content: content,
                              channel: channel,
                              authorType: authorType,
                              authorID: authorID,
                              isPending: isPending)
        context.insert(message)
        save()
        return message
    }

    @discardableResult
    func postReply(_ content: String,
                   to root: Message,
                   authorType: AuthorType = .human,
                   authorID: String = humanAuthorID,
                   isPending: Bool = false) -> Message {
        // Replies intentionally carry no channel — it is derived from the root.
        let reply = Message(content: content,
                            parent: root,
                            authorType: authorType,
                            authorID: authorID,
                            isPending: isPending)
        context.insert(reply)
        save()
        return reply
    }

    func edit(_ message: Message, content newContent: String) {
        message.content = newContent
        message.updatedAt = Date()
        save()
    }

    /// Deleting a root cascades to its entire thread; deleting a reply leaves
    /// the rest of the thread intact.
    func delete(_ message: Message) {
        context.delete(message)
        save()
    }

    /// Moves a root message — and with it, automatically, its whole thread —
    /// into another channel. Replies have no channel of their own to keep in
    /// sync, so the move is a single field update and can't break the invariant.
    func move(_ root: Message, to channel: Channel) {
        precondition(!root.isThreadReply, "V1 moves root messages; a reply's channel derives from its root")
        root.channel = channel
        save()
    }

    func save() {
        try? context.save()
    }
}
