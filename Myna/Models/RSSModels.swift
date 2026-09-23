import Foundation
import SwiftData

enum RSSRefreshFrequency: Int, CaseIterable, Identifiable {
    case hourly = 3_600
    case daily = 86_400
    case weekly = 604_800

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .hourly: "1 hour"
        case .daily: "1 day"
        case .weekly: "1 week"
        }
    }
}

@Model
final class RSSFeed {
    var id: UUID = UUID()
    /// A feed may be subscribed in more than one channel.
    var channelID: UUID
    var url: String
    var title: String
    var addedAt: Date = Date()
    var lastFetchedAt: Date?
    var isPaused: Bool = false
    var refreshIntervalSeconds: Int = 3_600

    init(channelID: UUID, url: String, title: String) {
        self.channelID = channelID
        self.url = url
        self.title = title
    }
}

@Model
final class RSSImport {
    var id: UUID = UUID()
    /// This receipt survives deletion or moving of its posted message.
    var channelID: UUID
    var feedURL: String
    var externalID: String
    /// Nil for articles already present when the user subscribed.
    var messageID: UUID?
    var firstSeenAt: Date = Date()

    init(channelID: UUID, feedURL: String, externalID: String, messageID: UUID? = nil) {
        self.channelID = channelID
        self.feedURL = feedURL
        self.externalID = externalID
        self.messageID = messageID
    }
}
