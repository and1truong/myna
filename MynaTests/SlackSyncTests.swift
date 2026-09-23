import Foundation
import SwiftData
import XCTest
@testable import Myna

private final class StubSlackProtocol: URLProtocol {
    static var response: ((URLRequest) -> Data)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let data = Self.response?(request) ?? Data()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
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
}
