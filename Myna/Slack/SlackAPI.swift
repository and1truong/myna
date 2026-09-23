import Foundation

struct SlackConversation: Decodable, Identifiable {
    let id: String
    let name: String
    let is_member: Bool?
}

struct SlackMessage: Decodable {
    let ts: String
    let text: String?
    let user: String?
    let username: String?
    let bot_profile: BotProfile?
    let subtype: String?

    struct BotProfile: Decodable { let name: String? }

    var senderName: String { bot_profile?.name ?? username ?? user ?? "Slack" }
    var postedAt: Date { Date(timeIntervalSince1970: Double(ts) ?? 0) }
    /// Skip channel join, edit, deletion and other system events; preserve bot posts.
    var isImportable: Bool { !ts.isEmpty && !(text ?? "").isEmpty && (subtype == nil || subtype == "bot_message") }
}

struct SlackPage {
    let messages: [SlackMessage]
    let nextCursor: String?
}

enum SlackAPIError: LocalizedError {
    case response(String)
    case rateLimited(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .response(let code): return "Slack: \(code.replacingOccurrences(of: "_", with: " "))"
        case .rateLimited(let seconds): return "Slack rate limit. Try again in \(seconds) seconds."
        case .invalidResponse: return "Slack returned an unreadable response."
        }
    }
}

struct SlackAPI {
    let token: String
    var session: URLSession = .shared

    private struct Envelope: Decodable {
        let ok: Bool
        let error: String?
        let channels: [SlackConversation]?
        let messages: [SlackMessage]?
        let response_metadata: Metadata?
        let permalink: String?
        struct Metadata: Decodable { let next_cursor: String? }
    }

    private func request(_ method: String, parameters: [URLQueryItem]) async throws -> Envelope {
        var components = URLComponents(string: "https://slack.com/api/\(method)")!
        components.queryItems = parameters
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SlackAPIError.invalidResponse }
        if http.statusCode == 429 {
            throw SlackAPIError.rateLimited(Int(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60)
        }
        guard (200..<300).contains(http.statusCode) else { throw SlackAPIError.response("HTTP \(http.statusCode)") }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.ok else { throw SlackAPIError.response(envelope.error ?? "unknown_error") }
        return envelope
    }

    func conversations() async throws -> [SlackConversation] {
        var result: [SlackConversation] = []
        var cursor: String?
        repeat {
            var parameters = [URLQueryItem(name: "types", value: "public_channel,private_channel"),
                              URLQueryItem(name: "limit", value: "200"),
                              URLQueryItem(name: "exclude_archived", value: "true")]
            if let cursor { parameters.append(URLQueryItem(name: "cursor", value: cursor)) }
            let response = try await request("conversations.list", parameters: parameters)
            result += (response.channels ?? []).filter { $0.is_member == true }
            cursor = response.response_metadata?.next_cursor
        } while cursor?.isEmpty == false
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func history(channelID: String, oldest: String?, cursor: String?) async throws -> SlackPage {
        var parameters = [URLQueryItem(name: "channel", value: channelID),
                          URLQueryItem(name: "limit", value: "50")]
        if let oldest { parameters.append(URLQueryItem(name: "oldest", value: oldest)) }
        if let cursor { parameters.append(URLQueryItem(name: "cursor", value: cursor)) }
        let response = try await request("conversations.history", parameters: parameters)
        let next = response.response_metadata?.next_cursor
        return SlackPage(messages: response.messages ?? [], nextCursor: next?.isEmpty == false ? next : nil)
    }

    func permalink(channelID: String, messageTS: String) async throws -> String {
        let response = try await request("chat.getPermalink", parameters: [
            URLQueryItem(name: "channel", value: channelID),
            URLQueryItem(name: "message_ts", value: messageTS),
        ])
        guard let permalink = response.permalink, URL(string: permalink) != nil else {
            throw SlackAPIError.invalidResponse
        }
        return permalink
    }
}
