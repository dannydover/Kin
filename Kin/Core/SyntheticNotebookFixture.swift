#if DEBUG
import Foundation

/// Deterministic records for isolated UI notebooks only; never used by Release.
enum SyntheticNotebookFixture {
    enum FixtureError: Error, Equatable { case invalidArguments, unsupported, nonemptyNotebook }

    static func selection(arguments: [String]) throws -> String? {
        let fixtures = arguments.indices.filter { arguments[$0] == "--kin-ui-fixture" }
        if fixtures.isEmpty { return nil }
        let notebooks = arguments.indices.filter { arguments[$0] == "--kin-test-notebook" }
        guard fixtures.count == 1, notebooks.count == 1, !arguments.contains("--kin-preview"),
              arguments.indices.contains(notebooks[0] + 1), UUID(uuidString: arguments[notebooks[0] + 1]) != nil,
              arguments.indices.contains(fixtures[0] + 1) else {
            throw FixtureError.invalidArguments
        }
        return arguments[fixtures[0] + 1]
    }

    @MainActor static func seed(_ selection: String, token: UUID, store: KinStore) throws {
        let records: [(UUID, String)]
        switch selection {
        case "named-friend": records = [(token, "Synthetic Named")]
        case "long-friend": records = [(token, "Synthetic Parent With A Long Compound Family Name")]
        case "partner-friends", "young-parent-friends":
            var bytes = token.uuid
            bytes.15 ^= 0xff
            let names = selection == "partner-friends" ? ("Synthetic A", "Synthetic B") : ("Synthetic Young", "Synthetic Existing Parent")
            records = [(token, names.0), (UUID(uuid: bytes), names.1)]
        default: throw FixtureError.unsupported
        }
        // A relaunch may follow edits or creation of linked people. Never
        // overwrite an existing fixture or mix it into another notebook.
        let existing = Set(store.people.map(\.id))
        if records.allSatisfy({ existing.contains($0.0) }) { return }
        guard store.people.isEmpty && store.parentLinks.isEmpty && store.partnerLinks.isEmpty else {
            throw FixtureError.nonemptyNotebook
        }
        for (id, name) in records {
            var friend = Person(id: id, firstName: name, connections: [.friend])
            friend.isListed = true
            try store.savePerson(friend)
        }
    }
}
#endif
