import Foundation
import SwiftData
import XCTest
@testable import Myna

private final class StubSlackProtocol: URLProtocol {
    static var response: ((URLRequest) -> Data)?
    static var permalinkRateLimited = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let limited = Self.permalinkRateLimited && request.url?.path == "/api/chat.getPermalink"
        let data = limited ? Data() : (Self.response?(request) ?? Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: limited ? 429 : 200,
                                       httpVersion: nil,
                                       headerFields: limited ? ["Retry-After": "60"] : nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class SlackSyncTests: XCTestCase {
    @MainActor
    func testImportsAndDeduplicatesPerMynaChannel() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SlackSource.self, SlackEntry.self,
                                           configurations: config)
        let context = ModelContext(container)
        let first = SlackSource(mynaChannelID: UUID(), slackChannelID: "C123", slackChannelName: "alerts")
        let second = SlackSource(mynaChannelID: UUID(), slackChannelID: "C123", slackChannelName: "alerts")
        context.insert(first)
        context.insert(second)

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [StubSlackProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        StubSlackProtocol.response = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer xoxb-test")
            if request.url?.path == "/api/conversations.history" {
                return Data(#"{"ok":true,"messages":[{"ts":"100.000001","text":"Build failed","user":"U123"}],"response_metadata":{"next_cursor":""}}"#.utf8)
            }
            return Data(#"{"ok":true,"permalink":"https://example.slack.com/archives/C123/p100000001"}"#.utf8)
        }
        defer { StubSlackProtocol.response = nil }

        let sync = SlackSync(context: context, api: SlackAPI(token: "xoxb-test", session: session))
        let firstCount = try await sync.sync(first)
        let repeatedCount = try await sync.sync(first)
        let secondCount = try await sync.sync(second)
        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(repeatedCount, 0)
        XCTAssertEqual(secondCount, 1)

        let entries = try context.fetch(FetchDescriptor<SlackEntry>())
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map(\.mynaChannelID)).count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.permalink.contains("p100000001") })
    }

    @MainActor
    func testPermalinkRateLimitDefersLinkWithoutLosingPost() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SlackSource.self, SlackEntry.self,
                                           configurations: config)
        let context = ModelContext(container)
        let source = SlackSource(mynaChannelID: UUID(), slackChannelID: "C123", slackChannelName: "alerts")
        context.insert(source)
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [StubSlackProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        StubSlackProtocol.response = { request in
            if request.url?.path == "/api/conversations.history" {
                return Data(#"{"ok":true,"messages":[{"ts":"100.000001","text":"Build failed"}],"response_metadata":{"next_cursor":""}}"#.utf8)
            }
            return Data(#"{"ok":true,"permalink":"https://example.slack.com/archives/C123/p100000001"}"#.utf8)
        }
        StubSlackProtocol.permalinkRateLimited = true
        defer {
            StubSlackProtocol.response = nil
            StubSlackProtocol.permalinkRateLimited = false
        }

        let sync = SlackSync(context: context, api: SlackAPI(token: "xoxb-test", session: session))
        let firstCount = try await sync.sync(source)
        XCTAssertEqual(firstCount, 1)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SlackEntry>()).first)
        XCTAssertEqual(entry.permalink, "")

        StubSlackProtocol.permalinkRateLimited = false
        let secondCount = try await sync.sync(source)
        XCTAssertEqual(secondCount, 0)
        XCTAssertEqual(entry.permalink, "https://example.slack.com/archives/C123/p100000001")
    }

    @MainActor
    func testDeselectRemovesOnlyThatSourceAndItsEntries() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SlackSource.self, SlackEntry.self,
                                           configurations: config)
        let context = ModelContext(container)
        let first = SlackSource(mynaChannelID: UUID(), slackChannelID: "C123", slackChannelName: "alerts")
        let second = SlackSource(mynaChannelID: UUID(), slackChannelID: "C123", slackChannelName: "alerts")
        context.insert(first)
        context.insert(second)
        for source in [first, second] {
            context.insert(SlackEntry(mynaChannelID: source.mynaChannelID,
                                      slackChannelID: source.slackChannelID,
                                      slackChannelName: source.slackChannelName,
                                      messageTS: "100.000001", senderName: "bot",
                                      content: "Build failed", permalink: "https://example.slack.com/post",
                                      postedAt: .now))
        }

        try SlackSourceStore(context: context).remove(first)
        let entries = try context.fetch(FetchDescriptor<SlackEntry>())
        let sources = try context.fetch(FetchDescriptor<SlackSource>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(entries.first?.mynaChannelID, second.mynaChannelID)
        XCTAssertEqual(sources.first?.mynaChannelID, second.mynaChannelID)
    }
}
