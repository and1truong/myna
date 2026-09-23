import Foundation
import SwiftData

/// A Slack conversation explicitly selected for one Myna channel.
@Model
final class SlackSource {
    var id: UUID = UUID()
    var mynaChannelID: UUID
    var slackChannelID: String
    var slackChannelName: String
    /// Highest imported Slack message timestamp. Nil means the first sync.
    var latestTS: String?

    init(mynaChannelID: UUID, slackChannelID: String, slackChannelName: String) {
        self.mynaChannelID = mynaChannelID
        self.slackChannelID = slackChannelID
        self.slackChannelName = slackChannelName
    }
}

@Model
final class SlackEntry {
    var id: UUID = UUID()
    var mynaChannelID: UUID
    var slackChannelID: String
    var slackChannelName: String
    var messageTS: String
    var senderName: String
    var content: String
    var permalink: String
    var postedAt: Date

    init(mynaChannelID: UUID, slackChannelID: String, slackChannelName: String,
         messageTS: String, senderName: String, content: String,
         permalink: String, postedAt: Date) {
        self.mynaChannelID = mynaChannelID
        self.slackChannelID = slackChannelID
        self.slackChannelName = slackChannelName
        self.messageTS = messageTS
        self.senderName = senderName
        self.content = content
        self.permalink = permalink
        self.postedAt = postedAt
    }
}
