import Foundation
import SwiftData

/// Pulls only explicitly subscribed channels while the app is active.
@MainActor
struct SlackSync {
    let context: ModelContext
    let api: SlackAPI

    func sync(_ source: SlackSource) async throws -> Int {
        let oldest = source.latestTS
        var cursor: String?
        var fetched: [SlackMessage] = []
        repeat {
            let page = try await api.history(channelID: source.slackChannelID,
                                             oldest: oldest, cursor: cursor)
            fetched += page.messages.filter(\.isImportable)
            cursor = page.nextCursor
            // On first connection import only the latest page, rather than an
            // unbounded history. Subsequent runs page through all new posts.
            if oldest == nil { break }
        } while cursor != nil

        let all = try context.fetch(FetchDescriptor<SlackEntry>())
        let known = Set(all.filter {
            $0.slackChannelID == source.slackChannelID && $0.mynaChannelID == source.mynaChannelID
        }
            .map(\.messageTS))
        var newEntries: [SlackEntry] = []
        for message in fetched.reversed() where !known.contains(message.ts) {
            let link = try await api.permalink(channelID: source.slackChannelID,
                                               messageTS: message.ts)
            let entry = SlackEntry(mynaChannelID: source.mynaChannelID,
                                   slackChannelID: source.slackChannelID,
                                   slackChannelName: source.slackChannelName,
                                   messageTS: message.ts,
                                   senderName: message.senderName,
                                   content: message.text ?? "",
                                   permalink: link,
                                   postedAt: message.postedAt)
            newEntries.append(entry)
        }
        for entry in newEntries { context.insert(entry) }
        if let latest = fetched.map(\.ts).max(by: { (Double($0) ?? 0) < (Double($1) ?? 0) }) {
            if source.latestTS == nil || (Double(latest) ?? 0) > (Double(source.latestTS ?? "") ?? 0) {
                source.latestTS = latest
            }
        }
        try context.save()
        return newEntries.count
    }
}
