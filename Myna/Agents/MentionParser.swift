import Foundation

enum MentionParser {
    private static let mentionRegex = #/@([A-Za-z][A-Za-z0-9_-]*)/#

    /// True when the @ at `atIndex` starts a mention — i.e. it isn't glued to a
    /// word character, so "email me at a@b.com" doesn't parse.
    private static func isMentionStart(_ text: String, atIndex: String.Index) -> Bool {
        guard atIndex > text.startIndex else { return true }
        let before = text[text.index(before: atIndex)]
        return !(before.isLetter || before.isNumber || before == "_")
    }

    /// Mention handles in order of first appearance, deduplicated.
    static func mentionedHandles(in text: String) -> [String] {
        var seen = Set<String>()
        var handles: [String] = []
        for match in text.matches(of: mentionRegex) {
            guard isMentionStart(text, atIndex: match.range.lowerBound) else { continue }
            let handle = String(match.1).lowercased()
            if seen.insert(handle).inserted {
                handles.append(handle)
            }
        }
        return handles
    }

    static func mentionedAgents(in text: String, registry: AgentRegistry) -> [any MynaAgent] {
        mentionedHandles(in: text).compactMap { registry.agent(named: $0) }
    }

    /// The partial handle currently being typed after a trailing `@`, used for
    /// composer autocomplete. Returns nil when the cursor isn't in a mention.
    static func activeMentionPrefix(in text: String) -> String? {
        guard let lastAt = text.lastIndex(of: "@") else { return nil }
        if lastAt > text.startIndex {
            let before = text[text.index(before: lastAt)]
            if before.isLetter || before.isNumber || before == "_" { return nil }
        }
        let tail = text[text.index(after: lastAt)...]
        guard tail.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) else {
            return nil
        }
        return String(tail).lowercased()
    }

    /// Replaces the trailing `@prefix` token with `@name ` — used when the user
    /// taps an autocomplete suggestion.
    static func completingMention(in text: String, with name: String) -> String {
        guard let lastAt = text.lastIndex(of: "@"),
              activeMentionPrefix(in: text) != nil else { return text }
        return String(text[..<lastAt]) + "@\(name) "
    }
}
