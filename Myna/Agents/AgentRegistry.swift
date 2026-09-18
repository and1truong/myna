import Foundation

/// The roster of agents available for @mention. Backed by simple deterministic
/// dev agents today; a real LLM provider would register its agents here without
/// touching the domain or UI.
struct AgentRegistry: Sendable {
    let agents: [any MynaAgent]

    func agent(named name: String) -> (any MynaAgent)? {
        let lowered = name.lowercased()
        return agents.first { $0.name.lowercased() == lowered || $0.id.lowercased() == lowered }
    }

    func agent(byID id: String) -> (any MynaAgent)? {
        agents.first { $0.id == id }
    }

    /// Suggestions for composer autocomplete, e.g. prefix "re" -> @research.
    func suggestions(forPrefix prefix: String) -> [any MynaAgent] {
        let p = prefix.lowercased()
        return agents
            .filter { p.isEmpty || $0.name.lowercased().hasPrefix(p) }
            .sorted { $0.name < $1.name }
    }

    static let `default` = AgentRegistry(agents: [
        DevAgents.research(),
        DevAgents.writer(),
        DevAgents.architect(),
    ])
}
