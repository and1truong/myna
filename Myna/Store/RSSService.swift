import Foundation
import SwiftData

struct ParsedRSSItem {
    let externalID: String
    let title: String
    let summary: String
    let link: String
    let publishedAt: Date
}

struct ParsedRSSFeed {
    let title: String
    let items: [ParsedRSSItem]
}

enum FeedCommand: Equatable {
    case subscribe(String)
    case list
    case remove(String)
    case invalid

    static let usage = "Use /feed subcribe <https://feed-url> (or /feed subscribe), /feed list, or /feed remove <feed-url>."

    /// Only claims the exact /feed command, leaving other slash commands alone.
    static func parse(_ input: String) -> FeedCommand? {
        let parts = input.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.first?.lowercased() == "/feed" else { return nil }
        guard parts.count >= 2 else { return .invalid }
        switch (parts[1].lowercased(), parts.count) {
        case ("subcribe", 3), ("subscribe", 3): return .subscribe(parts[2])
        case ("list", 2): return .list
        case ("remove", 3): return .remove(parts[2])
        default: return .invalid
        }
    }
}

enum RSSError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidFeed
    case duplicateFeed
    case feedNotFound
    case wrongChannel
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter an HTTPS feed URL."
        case .invalidResponse: "The feed could not be downloaded."
        case .invalidFeed: "This URL did not return a valid RSS or Atom feed."
        case .duplicateFeed: "This feed is already subscribed in this channel."
        case .feedNotFound: "No matching feed is subscribed in this channel."
        case .wrongChannel: "This feed belongs to another channel."
        case .tooLarge: "This feed is too large to import."
        }
    }
}

enum RSSParser {
    static func parse(_ data: Data, baseURL: URL) throws -> ParsedRSSFeed {
        let delegate = FeedXMLDelegate(baseURL: baseURL)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), delegate.isFeed else { throw RSSError.invalidFeed }
        return ParsedRSSFeed(
            title: delegate.feedTitle.isEmpty ? baseURL.host ?? "Feed" : delegate.feedTitle,
            items: delegate.items
        )
    }
}

private final class FeedXMLDelegate: NSObject, XMLParserDelegate {
    private struct Element {
        let name: String
        var text = ""
    }

    private struct Draft {
        var title = ""
        var summary = ""
        var link = ""
        var guid = ""
        var date = ""
    }

    private let baseURL: URL
    private var stack: [Element] = []
    private var draft: Draft?
    private(set) var isFeed = false
    private(set) var feedTitle = ""
    private(set) var items: [ParsedRSSItem] = []

    init(baseURL: URL) {
        self.baseURL = baseURL
        super.init()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased().split(separator: ":").last.map(String.init) ?? elementName
        if stack.isEmpty { isFeed = ["rss", "feed", "rdf"].contains(name) }
        stack.append(Element(name: name))
        if name == "item" || name == "entry" { draft = Draft() }
        if name == "link", draft != nil, let href = attributeDict["href"] {
            let relationship = attributeDict["rel"] ?? "alternate"
            if relationship == "alternate" || draft?.link.isEmpty == true {
                draft?.link = absoluteLink(href)
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else { return }
        self.parser(parser, foundCharacters: string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        guard let element = stack.popLast() else { return }
        let value = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stack.isEmpty { stack[stack.count - 1].text += element.text }

        if element.name == "item" || element.name == "entry" {
            if let draft {
                let title = clean(draft.title)
                let link = absoluteLink(draft.link)
                let externalID = draft.guid.isEmpty ? (link.isEmpty ? "\(title)|\(draft.date)" : link) : draft.guid
                if !title.isEmpty, !externalID.isEmpty {
                    items.append(ParsedRSSItem(
                        externalID: externalID,
                        title: title,
                        summary: clean(draft.summary),
                        link: link,
                        publishedAt: parseDate(draft.date) ?? Date()
                    ))
                }
            }
            draft = nil
            return
        }

        if draft != nil {
            switch element.name {
            case "title": draft?.title = value
            case "description", "summary", "content", "encoded":
                if value.count > (draft?.summary.count ?? 0) { draft?.summary = value }
            case "link":
                if draft?.link.isEmpty == true { draft?.link = absoluteLink(value) }
            case "guid", "id": draft?.guid = value
            case "pubdate", "published", "updated", "date":
                if draft?.date.isEmpty == true { draft?.date = value }
            default: break
            }
        } else if element.name == "title", feedTitle.isEmpty {
            feedTitle = clean(value)
        }
    }

    private func absoluteLink(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL,
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return "" }
        return url.absoluteString
    }

    private func clean(_ value: String) -> String {
        let stripped = value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return stripped.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        let hasTwoDigitYear = value.range(
            of: #"\b[0-9]{2}\s+[0-9]{1,2}:[0-9]{2}"#,
            options: .regularExpression
        ) != nil
        let year = hasTwoDigitYear ? "yy" : "yyyy"
        for format in ["EEE, dd MMM \(year) HH:mm:ss Z", "EEE, dd MMM \(year) HH:mm Z",
                       "dd MMM \(year) HH:mm:ss Z", "dd MMM \(year) HH:mm Z"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.isLenient = false
            if hasTwoDigitYear {
                formatter.twoDigitStartDate = Calendar(identifier: .gregorian).date(
                    from: DateComponents(year: 1950, month: 1, day: 1)
                )
            }
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

@MainActor
final class RSSStore {
    private let context: ModelContext
    private let loadFeed: (URL) async throws -> ParsedRSSFeed

    init(context: ModelContext,
         loader: ((URL) async throws -> ParsedRSSFeed)? = nil) {
        self.context = context
        self.loadFeed = loader ?? Self.download
    }

    /// Existing entries are bookmarked on subscription so adding a busy feed
    /// does not dump its archive into the channel.
    @discardableResult
    func addFeed(_ rawURL: String, to channel: Channel) async throws -> RSSFeed {
        guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil else { throw RSSError.invalidURL }
        let normalized = url.absoluteString
        let feeds = try context.fetch(FetchDescriptor<RSSFeed>())
        guard !feeds.contains(where: { $0.url == normalized && $0.channelID == channel.id })
        else { throw RSSError.duplicateFeed }

        let parsed = try await loadFeed(url)
        let latestFeeds = try context.fetch(FetchDescriptor<RSSFeed>())
        guard !latestFeeds.contains(where: { $0.url == normalized && $0.channelID == channel.id })
        else { throw RSSError.duplicateFeed }
        let feed = RSSFeed(channelID: channel.id, url: normalized, title: parsed.title)
        context.insert(feed)
        var seen = try seenIDs(for: feed)
        for entry in parsed.items where seen.insert(entry.externalID).inserted {
            context.insert(RSSImport(channelID: channel.id, feedURL: normalized,
                                     externalID: entry.externalID))
        }
        feed.lastFetchedAt = Date()
        try context.save()
        return feed
    }

    /// Posts only new articles as root messages in the subscribed channel.
    @discardableResult
    func refresh(_ feed: RSSFeed, in channel: Channel) async throws -> Int {
        guard feed.channelID == channel.id else { throw RSSError.wrongChannel }
        guard let url = URL(string: feed.url) else { throw RSSError.invalidURL }
        let parsed = try await loadFeed(url)
        feed.title = parsed.title
        var seen = try seenIDs(for: feed)
        var posted = 0
        let sorted = parsed.items.sorted { $0.publishedAt < $1.publishedAt }
        let postingTime = Date()
        for entry in sorted where seen.insert(entry.externalID).inserted {
            let title = escapeMarkdown(entry.title)
            let summary = escapeMarkdown(String(entry.summary.prefix(600)))
            let content = summary.isEmpty ? "**\(title)**" : "**\(title)**\n\(summary)"
            let message = Message(content: content,
                                  channel: channel,
                                  authorType: .feed,
                                  authorID: parsed.title,
                                  externalURL: entry.link.isEmpty ? nil : entry.link,
                                  createdAt: postingTime.addingTimeInterval(Double(posted) / 1000))
            context.insert(message)
            context.insert(RSSImport(channelID: channel.id, feedURL: feed.url,
                                     externalID: entry.externalID, messageID: message.id))
            posted += 1
        }
        feed.lastFetchedAt = Date()
        try context.save()
        return posted
    }

    func remove(_ feed: RSSFeed) throws {
        // Leave posted messages and their threads intact. Also retain receipts
        // so re-subscribing later does not repost old articles.
        context.delete(feed)
        try context.save()
    }

    func feeds(in channel: Channel) throws -> [RSSFeed] {
        try context.fetch(FetchDescriptor<RSSFeed>())
            .filter { $0.channelID == channel.id }
            .sorted { $0.addedAt < $1.addedAt }
    }

    static func isDue(_ feed: RSSFeed, now: Date = Date()) -> Bool {
        guard !feed.isPaused else { return false }
        guard let lastFetchedAt = feed.lastFetchedAt else { return true }
        return now.timeIntervalSince(lastFetchedAt) >= Double(feed.refreshIntervalSeconds)
    }

    func setPaused(_ feed: RSSFeed, to paused: Bool) throws {
        feed.isPaused = paused
        try context.save()
    }

    func setFrequency(_ feed: RSSFeed, to frequency: RSSRefreshFrequency) throws {
        feed.refreshIntervalSeconds = frequency.rawValue
        try context.save()
    }

    func remove(_ rawURL: String, from channel: Channel) throws {
        guard let feed = try feeds(in: channel).first(where: { $0.url == rawURL })
        else { throw RSSError.feedNotFound }
        try remove(feed)
    }

    private func seenIDs(for feed: RSSFeed) throws -> Set<String> {
        let receipts = try context.fetch(FetchDescriptor<RSSImport>())
        return Set(receipts.filter { $0.channelID == feed.channelID && $0.feedURL == feed.url }
            .map(\.externalID))
    }

    private func escapeMarkdown(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    private static func download(_ url: URL) async throws -> ParsedRSSFeed {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Myna/1.0 Feed Subscriber", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            bytes.task.cancel()
            throw RSSError.invalidResponse
        }
        let maxFeedBytes = 5_000_000
        guard response.expectedContentLength < 0 || response.expectedContentLength <= Int64(maxFeedBytes)
        else {
            bytes.task.cancel()
            throw RSSError.tooLarge
        }
        let data: Data
        do { data = try await collectLimited(bytes, maxBytes: maxFeedBytes) }
        catch {
            bytes.task.cancel()
            throw error
        }
        return try RSSParser.parse(data, baseURL: response.url ?? url)
    }

    static func collectLimited<S: AsyncSequence>(_ bytes: S, maxBytes: Int) async throws -> Data
    where S.Element == UInt8 {
        var data = Data()
        for try await byte in bytes {
            guard data.count < maxBytes else { throw RSSError.tooLarge }
            data.append(byte)
        }
        return data
    }
}
