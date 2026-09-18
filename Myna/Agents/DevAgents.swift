import Foundation

/// Deterministic offline agents for development. They simulate latency and
/// return canned, context-aware responses so the full agent flow — mention
/// parsing, thinking placeholder, threaded response — works with AI disabled.
/// Swap in an LLM-backed implementation of `MynaAgent` without touching the
/// domain or UI.
struct DevAgent: MynaAgent {
    let id: String
    let name: String
    let displayName: String
    let tagline: String
    var delay: Duration = .milliseconds(600)
    let respond: @Sendable (AgentContext) -> String

    func handle(_ context: AgentContext) async throws -> String {
        try await Task.sleep(for: delay)
        return respond(context)
    }
}

private extension AgentContext {
    /// First line of the note under discussion, trimmed for canned replies.
    var topicLine: String {
        let text = root?.content ?? message.content
        let line = text.components(separatedBy: .newlines).first ?? text
        return line.count > 80 ? String(line.prefix(80)) + "…" : line
    }
}

enum DevAgents {
    static func research(delay: Duration = .milliseconds(600)) -> DevAgent {
        DevAgent(
            id: "research",
            name: "research",
            displayName: "Research",
            tagline: "Digs up context and summarizes findings",
            delay: delay
        ) { context in
            """
            **Research summary** — *\u{201C}\(context.topicLine)\u{201D}*

            • Core idea: this note looks like a seed worth developing in #\(context.channel.name).
            • Suggested next step: pull related notes into this thread, then split conclusions into their own notes.

            _(dev agent — deterministic offline response)_
            """
        }
    }

    static func writer(delay: Duration = .milliseconds(600)) -> DevAgent {
        DevAgent(
            id: "writer",
            name: "writer",
            displayName: "Writer",
            tagline: "Rewrites notes for clarity and concision",
            delay: delay
        ) { context in
            """
            **Concise rewrite** — *\u{201C}\(context.topicLine)\u{201D}*

            > \(context.topicLine)

            _(dev agent — deterministic offline response)_
            """
        }
    }

    static func architect(delay: Duration = .milliseconds(600)) -> DevAgent {
        DevAgent(
            id: "architect",
            name: "architect",
            displayName: "Architect",
            tagline: "Challenges designs and finds failure modes",
            delay: delay
        ) { context in
            """
            **Architect review** — *\u{201C}\(context.topicLine)\u{201D}*

            • What breaks when this grows 10x?
            • Which assumption here is cheapest to validate first?

            _(dev agent — deterministic offline response)_
            """
        }
    }
}
