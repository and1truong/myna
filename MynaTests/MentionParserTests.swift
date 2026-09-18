import XCTest
@testable import Myna

final class MentionParserTests: XCTestCase {
    func testParsesSingleMention() {
        XCTAssertEqual(MentionParser.mentionedHandles(in: "@research find the core idea"), ["research"])
    }

    func testParsesMultipleMentionsInOrder() {
        XCTAssertEqual(
            MentionParser.mentionedHandles(in: "@writer rewrite, then @architect challenge it"),
            ["writer", "architect"]
        )
    }

    func testDeduplicatesMentions() {
        XCTAssertEqual(
            MentionParser.mentionedHandles(in: "@research a @research b"),
            ["research"]
        )
    }

    func testMentionMustNotFollowWordCharacter() {
        // Emails and glued mentions don't count.
        XCTAssertEqual(MentionParser.mentionedHandles(in: "ping me at a@b.com"), [])
        XCTAssertEqual(MentionParser.mentionedHandles(in: "hello@research"), [])
        XCTAssertEqual(MentionParser.mentionedHandles(in: "(@research) hi"), ["research"])
    }

    func testMentionMustStartWithLetter() {
        XCTAssertEqual(MentionParser.mentionedHandles(in: "@123"), [])
    }

    func testMentionedAgentsMatchesRegistry() {
        let registry = AgentRegistry.default
        let agents = MentionParser.mentionedAgents(
            in: "@research this and @nobody that",
            registry: registry
        )
        XCTAssertEqual(agents.count, 1)
        XCTAssertEqual(agents.first?.name, "research")
    }

    func testActiveMentionPrefix() {
        XCTAssertEqual(MentionParser.activeMentionPrefix(in: "@re"), "re")
        XCTAssertEqual(MentionParser.activeMentionPrefix(in: "hello @arch"), "arch")
        XCTAssertNil(MentionParser.activeMentionPrefix(in: "done @research "))
        XCTAssertNil(MentionParser.activeMentionPrefix(in: "no mention"))
        XCTAssertNil(MentionParser.activeMentionPrefix(in: "a@b"))
    }

    func testCompletingMention() {
        XCTAssertEqual(
            MentionParser.completingMention(in: "please @wri", with: "writer"),
            "please @writer "
        )
    }
}
