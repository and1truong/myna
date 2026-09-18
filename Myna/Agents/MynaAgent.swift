import Foundation

/// Everything an agent needs to respond: the triggering message, its thread and
/// channel context. A real LLM-backed agent would serialize this into a prompt;
/// the domain never sees any provider details.
struct AgentContext {
    let channel: Channel
    /// The message that contained the @mention.
    let message: Message
    /// The thread root when invoked inside a thread, nil for channel-level mentions.
    let root: Message?
    /// Replies in the thread, oldest first (excludes the placeholder response).
    let thread: [Message]

    var transcript: String {
        var lines: [String] = ["#\(channel.name)"]
        if let root { lines.append("root: \(root.content)") }
        for reply in thread where reply.id != message.id {
            lines.append("reply: \(reply.content)")
        }
        lines.append("you: \(message.content)")
        return lines.joined(separator: "\n")
    }
}

/// An agent is a participant in the workspace. Implementations can wrap an LLM
/// provider, a local tool, or canned development responses — the domain only
/// ever talks to this protocol.
protocol MynaAgent: Identifiable, Sendable {
    var id: String { get }
    /// The @mention handle, e.g. "research" for @research.
    var name: String { get }
    var displayName: String { get }
    var tagline: String { get }
    func handle(_ context: AgentContext) async throws -> String
}
