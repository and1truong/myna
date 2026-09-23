import Foundation
import XCTest
@testable import Myna

final class RSSParserTests: XCTestCase {
    func testRSSItemsAndRelativeLinks() throws {
        let xml = """
        <rss version="2.0"><channel>
          <title>Example News</title>
          <item><guid>story-1</guid><title>First &amp; best</title>
            <link>/stories/1</link><description><![CDATA[<p>Hello <b>reader</b></p>]]></description>
            <pubDate>Tue, 22 Sep 2026 10:15:00 +0000</pubDate>
          </item>
        </channel></rss>
        """
        let feed = try RSSParser.parse(Data(xml.utf8), baseURL: URL(string: "https://example.com/feed.xml")!)
        XCTAssertEqual(feed.title, "Example News")
        XCTAssertEqual(feed.items.count, 1)
        XCTAssertEqual(feed.items[0].externalID, "story-1")
        XCTAssertEqual(feed.items[0].title, "First & best")
        XCTAssertEqual(feed.items[0].summary, "Hello reader")
        XCTAssertEqual(feed.items[0].link, "https://example.com/stories/1")
    }

    func testAtomAlternateLinkAndPublishedDate() throws {
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Example Atom</title>
          <entry><id>urn:example:2</id><title>Second</title>
            <link rel="self" href="https://example.com/feed/2" />
            <link rel="alternate" href="https://example.com/articles/2" />
            <summary>Short summary</summary><published>2026-09-22T12:00:00Z</published>
          </entry>
        </feed>
        """
        let feed = try RSSParser.parse(Data(xml.utf8), baseURL: URL(string: "https://example.com/atom.xml")!)
        XCTAssertEqual(feed.items.count, 1)
        XCTAssertEqual(feed.items[0].externalID, "urn:example:2")
        XCTAssertEqual(feed.items[0].link, "https://example.com/articles/2")
        XCTAssertEqual(feed.items[0].summary, "Short summary")
        XCTAssertLessThan(feed.items[0].publishedAt, Date())
    }

    func testRejectsNonFeedXML() {
        XCTAssertThrowsError(try RSSParser.parse(Data("<html/>".utf8),
                                               baseURL: URL(string: "https://example.com")!))
    }

    func testRSSDateWithTwoDigitYear() throws {
        let xml = """
        <rss><channel><title>News</title><item><guid>short-year</guid>
          <title>Article</title><pubDate>Tue, 22 Sep 26 10:15:00 +0000</pubDate>
        </item></channel></rss>
        """
        let feed = try RSSParser.parse(Data(xml.utf8), baseURL: URL(string: "https://example.com/rss")!)
        XCTAssertEqual(Calendar(identifier: .gregorian).component(.year, from: feed.items[0].publishedAt), 2026)
    }

    @MainActor
    func testStreamLimitRejectsExtraByte() async throws {
        let exact = AsyncStream<UInt8> { continuation in
            for byte in [UInt8(1), 2, 3] { continuation.yield(byte) }
            continuation.finish()
        }
        let data = try await RSSStore.collectLimited(exact, maxBytes: 3)
        XCTAssertEqual(data, Data([1, 2, 3]))

        let oversized = AsyncStream<UInt8> { continuation in
            for byte in [UInt8(1), 2, 3, 4] { continuation.yield(byte) }
            continuation.finish()
        }
        do {
            _ = try await RSSStore.collectLimited(oversized, maxBytes: 3)
            XCTFail("The stream should stop at the byte limit")
        } catch RSSError.tooLarge {
            // The fourth byte is rejected before it is appended.
        }
    }
}

final class FeedCommandTests: XCTestCase {
    func testSubscribeTypoAndAlias() {
        XCTAssertEqual(FeedCommand.parse("/feed subcribe https://example.com/rss"),
                       .subscribe("https://example.com/rss"))
        XCTAssertEqual(FeedCommand.parse("/feed subscribe https://example.com/rss"),
                       .subscribe("https://example.com/rss"))
    }

    func testListRemoveAndInvalidCommands() {
        XCTAssertEqual(FeedCommand.parse("/feed list"), .list)
        XCTAssertEqual(FeedCommand.parse("/feed remove https://example.com/rss"),
                       .remove("https://example.com/rss"))
        XCTAssertEqual(FeedCommand.parse("/feed"), .invalid)
        XCTAssertEqual(FeedCommand.parse("/feed subscribe"), .invalid)
        XCTAssertNil(FeedCommand.parse("/remind me later"))
        XCTAssertNil(FeedCommand.parse("/feedback hello"))
    }
}

final class RSSSubscriptionTests: XCTestCase {
    private final class Source {
        var feed: ParsedRSSFeed
        init(_ items: [ParsedRSSItem]) {
            feed = ParsedRSSFeed(title: "Example News", items: items)
        }
    }

    private func item(_ id: String, day: Int) -> ParsedRSSItem {
        ParsedRSSItem(externalID: id, title: "Story \(id)", summary: "Summary \(id)",
                      link: "https://example.com/\(id)",
                      publishedAt: Date(timeIntervalSince1970: TimeInterval(day * 86_400)))
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Workspace.self, Channel.self, Message.self,
                                           RSSFeed.self, RSSImport.self,
                                           configurations: config)
        return ModelContext(container)
    }

    @MainActor
    func testSameFeedIsolatedByChannelAndNoArchiveFlood() async throws {
        let context = try makeContext()
        let notes = NoteStore(context: context)
        let first = notes.createChannel(name: "reading")
        let second = notes.createChannel(name: "engineering")
        let source = Source([item("old", day: 1)])
        let store = RSSStore(context: context, loader: { _ in source.feed })
        let url = "https://example.com/rss"
        let firstFeed = try await store.addFeed(url, to: first)
        let secondFeed = try await store.addFeed(url, to: second)
        do {
            _ = try await store.addFeed(url, to: first)
            XCTFail("The same channel must not subscribe twice")
        } catch RSSError.duplicateFeed {
            // The same URL in a different channel remains valid.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(first.messages.isEmpty)
        XCTAssertTrue(second.messages.isEmpty)

        source.feed = ParsedRSSFeed(title: "Example News", items: [item("old", day: 1), item("new", day: 2)])
        let firstPostCount = try await store.refresh(firstFeed, in: first)
        let duplicatePostCount = try await store.refresh(firstFeed, in: first)
        XCTAssertEqual(firstPostCount, 1)
        XCTAssertEqual(duplicatePostCount, 0)
        XCTAssertEqual(first.messages.count, 1)
        let root = try XCTUnwrap(first.messages.first)
        XCTAssertEqual(root.authorType, .feed)
        XCTAssertEqual(root.authorID, "Example News")
        XCTAssertEqual(root.externalURL, "https://example.com/new")
        XCTAssertNil(root.parent)
        XCTAssertEqual(notes.postReply("my note", to: root).effectiveChannel?.id, first.id)

        let secondPostCount = try await store.refresh(secondFeed, in: second)
        XCTAssertEqual(secondPostCount, 1)
        XCTAssertEqual(second.messages.count, 1)
    }

    @MainActor
    func testDeletedPostAndResubscriptionDoNotRepostOldEntries() async throws {
        let context = try makeContext()
        let notes = NoteStore(context: context)
        let channel = notes.createChannel(name: "reading")
        let source = Source([item("old", day: 1)])
        let store = RSSStore(context: context, loader: { _ in source.feed })
        let feed = try await store.addFeed("https://example.com/rss", to: channel)
        source.feed = ParsedRSSFeed(title: "Example News", items: [item("old", day: 1), item("new", day: 2)])
        let posted = try await store.refresh(feed, in: channel)
        XCTAssertEqual(posted, 1)
        notes.delete(try XCTUnwrap(channel.messages.first))
        let afterDelete = try await store.refresh(feed, in: channel)
        XCTAssertEqual(afterDelete, 0)

        try store.remove(feed)
        let resubscribed = try await store.addFeed("https://example.com/rss", to: channel)
        let afterResubscribe = try await store.refresh(resubscribed, in: channel)
        XCTAssertEqual(afterResubscribe, 0)
        XCTAssertTrue(channel.messages.isEmpty)
    }

    @MainActor
    func testMovingPostAndRemovingFeedKeepsDiscussion() async throws {
        let context = try makeContext()
        let notes = NoteStore(context: context)
        let sourceChannel = notes.createChannel(name: "reading")
        let destination = notes.createChannel(name: "ideas")
        let source = Source([item("old", day: 1)])
        let store = RSSStore(context: context, loader: { _ in source.feed })
        let feed = try await store.addFeed("https://example.com/rss", to: sourceChannel)
        source.feed = ParsedRSSFeed(title: "Example News", items: [item("old", day: 1), item("new", day: 2)])
        _ = try await store.refresh(feed, in: sourceChannel)
        let root = try XCTUnwrap(sourceChannel.messages.first)
        let reply = notes.postReply("Discuss this", to: root)

        notes.move(root, to: destination)
        let afterMove = try await store.refresh(feed, in: sourceChannel)
        XCTAssertEqual(afterMove, 0)
        try store.remove(feed)

        XCTAssertTrue(try store.feeds(in: sourceChannel).isEmpty)
        XCTAssertEqual(root.effectiveChannel?.id, destination.id)
        XCTAssertEqual(reply.effectiveChannel?.id, destination.id)
        XCTAssertEqual(root.replies.count, 1)
        XCTAssertEqual(destination.messages.count, 1)
    }

    @MainActor
    func testPauseAndRefreshIntervals() async throws {
        let context = try makeContext()
        let channel = NoteStore(context: context).createChannel(name: "reading")
        let source = Source([])
        let store = RSSStore(context: context, loader: { _ in source.feed })
        let feed = try await store.addFeed("https://example.com/rss", to: channel)
        let now = Date()
        feed.lastFetchedAt = now.addingTimeInterval(-3_600)
        XCTAssertTrue(RSSStore.isDue(feed, now: now))
        try store.setFrequency(feed, to: .daily)
        XCTAssertFalse(RSSStore.isDue(feed, now: now))
        feed.lastFetchedAt = now.addingTimeInterval(-86_400)
        XCTAssertTrue(RSSStore.isDue(feed, now: now))
        try store.setFrequency(feed, to: .weekly)
        XCTAssertFalse(RSSStore.isDue(feed, now: now))
        feed.lastFetchedAt = now.addingTimeInterval(-604_800)
        XCTAssertTrue(RSSStore.isDue(feed, now: now))
        try store.setPaused(feed, to: true)
        XCTAssertFalse(RSSStore.isDue(feed, now: now))
        try store.setPaused(feed, to: false)
        XCTAssertTrue(RSSStore.isDue(feed, now: now))

        try store.setPaused(feed, to: true)
        source.feed = ParsedRSSFeed(title: "Example News", items: [item("manual", day: 2)])
        let manuallyPosted = try await store.refresh(feed, in: channel)
        XCTAssertEqual(manuallyPosted, 1)
        XCTAssertFalse(RSSStore.isDue(feed))
    }
}
