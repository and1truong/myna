import Foundation
import SwiftData

enum AuthorType: String, Codable {
    case human
    case agent
    case feed
}

@Model
final class Workspace {
    var id: UUID = UUID()
    var name: String

    @Relationship(deleteRule: .cascade, inverse: \Channel.workspace)
    var channels: [Channel] = []

    init(name: String) {
        self.name = name
    }
}

@Model
final class Channel {
    var id: UUID = UUID()
    var name: String
    var position: Int
    var createdAt: Date = Date()
    var workspace: Workspace?

    /// Root messages only. Replies carry no channel of their own — they derive
    /// it from their root — so moving a root can never split a thread.
    @Relationship(deleteRule: .cascade, inverse: \Message.channel)
    var messages: [Message] = []

    init(name: String, position: Int = 0, workspace: Workspace? = nil) {
        self.name = name
        self.position = position
        self.workspace = workspace
    }
}

@Model
final class Message {
    var id: UUID = UUID()
    var content: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var authorTypeRaw: String = AuthorType.human.rawValue
    var authorID: String = NoteStore.humanAuthorID
    /// External article URL for feed posts; nil for ordinary notes.
    var externalURL: String?
    /// True while an agent response is being generated (the "is thinking…" placeholder).
    var isPending: Bool = false
    /// A local notification attached to this message, if one was scheduled.
    var reminderDueAt: Date?
    var reminderTitle: String?

    /// Set on root messages only; replies leave this nil and derive their channel.
    var channel: Channel?

    var parent: Message?

    @Relationship(deleteRule: .cascade, inverse: \Message.parent)
    var replies: [Message] = []

    init(content: String,
         channel: Channel? = nil,
         parent: Message? = nil,
         authorType: AuthorType = .human,
         authorID: String = NoteStore.humanAuthorID,
         externalURL: String? = nil,
         isPending: Bool = false,
         createdAt: Date = Date()) {
        self.content = content
        self.channel = channel
        self.parent = parent
        self.authorTypeRaw = authorType.rawValue
        self.authorID = authorID
        self.externalURL = externalURL
        self.isPending = isPending
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var authorType: AuthorType {
        get { AuthorType(rawValue: authorTypeRaw) ?? .human }
        set { authorTypeRaw = newValue.rawValue }
    }

    var isThreadReply: Bool { parent != nil }

    var rootMessage: Message {
        var current = self
        while let parent = current.parent { current = parent }
        return current
    }

    /// The channel this message lives in, whether it's a root or a reply.
    var effectiveChannel: Channel? { rootMessage.channel }

    var sortedReplies: [Message] {
        replies.sorted { $0.createdAt < $1.createdAt }
    }

    var replyCount: Int { replies.count }
}
