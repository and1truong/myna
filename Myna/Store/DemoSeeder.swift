import Foundation
import SwiftData

#if DEBUG
/// Demo data for development and screenshots — DEBUG builds only, invoked from
/// the channel list toolbar. Never part of a release flow.
enum DemoSeeder {
    static func seed(context: ModelContext) {
        let store = NoteStore(context: context)

        guard let inbox = channel(named: "inbox", context: context),
              let engineering = channel(named: "engineering", context: context) else {
            return
        }

        let a = store.postMessage(
            "Interesting idea about retry budgets — cap retries by elapsed time, not attempt count",
            in: inbox)
        store.postReply("Also consider jitter — synchronized retries amplify load", to: a)
        store.postReply("See the Postgres queue note for the failure mode", to: a)
        store.postReply(
            "**Research summary** — “retry budgets by elapsed time”\n\n• Industry pattern: token-bucket per dependency.\n• Pairs well with circuit breakers at the client.\n\n_(dev agent — deterministic offline response)_",
            to: a, authorType: .agent, authorID: "research")

        let b = store.postMessage(
            "Postgres queue problem: `FOR UPDATE SKIP LOCKED` still hot-spots on the same index page",
            in: engineering)
        store.postReply("Partition by queue name to spread page pressure?", to: b)

        store.postMessage("@research explain retry amplification in one paragraph", in: engineering)
        store.postMessage("half-formed: notes app where every note is a message — organize later", in: inbox)
        store.postMessage("Sermon notes: endurance produces character (Rom 5)", in: channel(named: "bible-study", context: context) ?? inbox)

        store.save()
    }

    private static func channel(named name: String, context: ModelContext) -> Channel? {
        var descriptor = FetchDescriptor<Channel>(predicate: #Predicate { $0.name == name })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
#endif
