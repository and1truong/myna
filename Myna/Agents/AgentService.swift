import Foundation

/// Watches posted messages for @mentions and drives agent invocation: inserts a
/// pending placeholder, calls the agent off the main thread's critical path,
/// then resolves the placeholder with the response. The UI never blocks — the
/// placeholder renders as "…is thinking…" until the reply lands.
@MainActor
final class AgentService {
    let store: NoteStore
    let registry: AgentRegistry

    init(store: NoteStore, registry: AgentRegistry = .default) {
        self.store = store
        self.registry = registry
    }

    /// Fire-and-forget from the UI; awaitable in tests.
    func processMentions(in message: Message) async {
        guard message.authorType == .human else { return }
        let agents = MentionParser.mentionedAgents(in: message.content, registry: registry)
        for agent in agents {
            await invoke(agent, triggeredBy: message)
        }
    }

    private func invoke(_ agent: any MynaAgent, triggeredBy message: Message) async {
        let root = message.isThreadReply ? message.rootMessage : nil
        guard let channel = message.effectiveChannel else { return }

        let placeholder: Message
        if let root {
            placeholder = store.postReply("\(agent.displayName) is thinking…",
                                          to: root,
                                          authorType: .agent,
                                          authorID: agent.id,
                                          isPending: true)
        } else {
            placeholder = store.postMessage("\(agent.displayName) is thinking…",
                                            in: channel,
                                            authorType: .agent,
                                            authorID: agent.id,
                                            isPending: true)
        }

        let context = AgentContext(
            channel: channel,
            message: message,
            root: root,
            thread: root?.sortedReplies.filter { !$0.isPending } ?? []
        )

        do {
            placeholder.content = try await agent.handle(context)
        } catch {
            placeholder.content = "\(agent.displayName) couldn't respond right now."
        }
        placeholder.isPending = false
        placeholder.updatedAt = Date()
        store.save()
    }
}
