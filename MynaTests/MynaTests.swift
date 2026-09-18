import SwiftData
import XCTest
@testable import Myna

final class NoteStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var store: NoteStore!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Workspace.self, Channel.self, Message.self,
            configurations: config
        )
        context = ModelContext(container)
        store = NoteStore(context: context)
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    // MARK: - Channels

    func testCreateChannel() throws {
        let channel = store.createChannel(name: "My Ideas")
        XCTAssertEqual(channel.name, "my-ideas")
        XCTAssertEqual(channel.workspace?.name, "My Notes")
        XCTAssertEqual(try fetchAll(Channel.self).count, 1)
    }

    func testCreateChannelDeduplicates() throws {
        let first = store.createChannel(name: "inbox")
        let second = store.createChannel(name: "Inbox ")
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try fetchAll(Channel.self).count, 1)
    }

    func testSeedDefaultChannels() throws {
        store.seedDefaultChannels()
        let names = try fetchAll(Channel.self).map(\.name)
        for expected in ["inbox", "ideas", "engineering", "bible-study", "reading", "random"] {
            XCTAssertTrue(names.contains(expected))
        }
    }

    // MARK: - Messages

    func testCreateMessage() throws {
        let channel = store.createChannel(name: "inbox")
        let message = store.postMessage("hello **world**", in: channel)
        XCTAssertEqual(message.content, "hello **world**")
        XCTAssertEqual(message.authorType, .human)
        XCTAssertFalse(message.isThreadReply)
        XCTAssertEqual(channel.messages.count, 1)
    }

    func testCreateThreadReply() throws {
        let channel = store.createChannel(name: "inbox")
        let root = store.postMessage("root note", in: channel)
        let reply = store.postReply("elaboration", to: root)

        XCTAssertTrue(reply.isThreadReply)
        XCTAssertEqual(reply.rootMessage.id, root.id)
        // Replies derive their channel; they don't pollute the channel stream.
        XCTAssertNil(reply.channel)
        XCTAssertEqual(reply.effectiveChannel?.id, channel.id)
        XCTAssertEqual(channel.messages.count, 1)
        XCTAssertEqual(root.replyCount, 1)
    }

    // MARK: - Move

    func testMoveMessageBetweenChannels() throws {
        let inbox = store.createChannel(name: "inbox")
        let engineering = store.createChannel(name: "engineering")
        let message = store.postMessage("capture first", in: inbox)

        store.move(message, to: engineering)

        XCTAssertEqual(message.channel?.id, engineering.id)
        XCTAssertEqual(inbox.messages.count, 0)
        XCTAssertEqual(engineering.messages.count, 1)
        // Content and timestamps preserved.
        XCTAssertEqual(message.content, "capture first")
    }

    func testThreadPreservedAfterMove() throws {
        let inbox = store.createChannel(name: "inbox")
        let ideas = store.createChannel(name: "ideas")
        let root = store.postMessage("root", in: inbox)
        let reply1 = store.postReply("reply 1", to: root)
        let reply2 = store.postReply("reply 2", to: root)

        store.move(root, to: ideas)

        XCTAssertEqual(root.replies.count, 2)
        XCTAssertEqual(reply1.effectiveChannel?.id, ideas.id)
        XCTAssertEqual(reply2.effectiveChannel?.id, ideas.id)
        XCTAssertEqual(inbox.messages.count, 0)
        XCTAssertEqual(ideas.messages.count, 1)
        // Nothing was deleted — the whole thread came along.
        XCTAssertEqual(try fetchAll(Message.self).count, 3)
    }

    // MARK: - Edit / delete

    func testEditMessage() throws {
        let channel = store.createChannel(name: "inbox")
        let message = store.postMessage("draft", in: channel)
        let before = message.updatedAt

        store.edit(message, content: "final")

        XCTAssertEqual(message.content, "final")
        XCTAssertGreaterThanOrEqual(message.updatedAt, before)
    }

    func testDeleteRootCascadesThread() throws {
        let channel = store.createChannel(name: "inbox")
        let root = store.postMessage("root", in: channel)
        store.postReply("reply", to: root)

        store.delete(root)

        XCTAssertEqual(try fetchAll(Message.self).count, 0)
        XCTAssertEqual(channel.messages.count, 0)
    }

    func testDeleteReplyKeepsThread() throws {
        let channel = store.createChannel(name: "inbox")
        let root = store.postMessage("root", in: channel)
        let reply = store.postReply("reply", to: root)

        store.delete(reply)

        XCTAssertEqual(try fetchAll(Message.self).count, 1)
        XCTAssertEqual(root.replyCount, 0)
    }

    // MARK: - Agents

    @MainActor func testAgentResponsePersistedInChannel() async throws {
        let channel = store.createChannel(name: "inbox")
        let message = store.postMessage("@research what are retry budgets?", in: channel)
        let service = AgentService(store: store, registry: Self.fastRegistry)

        await service.processMentions(in: message)

        let roots = channel.messages.sorted { $0.createdAt < $1.createdAt }
        XCTAssertEqual(roots.count, 2)
        let response = try XCTUnwrap(roots.last)
        XCTAssertEqual(response.authorType, .agent)
        XCTAssertEqual(response.authorID, "research")
        XCTAssertFalse(response.isPending)
        XCTAssertFalse(response.content.contains("is thinking"))
        XCTAssertFalse(response.isThreadReply)
    }

    @MainActor func testAgentResponsePersistedInThread() async throws {
        let channel = store.createChannel(name: "inbox")
        let root = store.postMessage("root note", in: channel)
        let reply = store.postReply("@writer tighten this up", to: root)
        let service = AgentService(store: store, registry: Self.fastRegistry)

        await service.processMentions(in: reply)

        XCTAssertEqual(root.replies.count, 2)
        let agentReply = try XCTUnwrap(root.replies.first { $0.authorType == .agent })
        XCTAssertEqual(agentReply.authorID, "writer")
        XCTAssertFalse(agentReply.isPending)
        XCTAssertEqual(agentReply.effectiveChannel?.id, channel.id)
    }

    /// Zero-latency dev agents so tests stay fast.
    private static let fastRegistry = AgentRegistry(agents: [
        DevAgents.research(delay: .zero),
        DevAgents.writer(delay: .zero),
        DevAgents.architect(delay: .zero),
    ])
}
