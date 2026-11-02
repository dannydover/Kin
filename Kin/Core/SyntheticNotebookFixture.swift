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
        let name: String
        switch selection {
        case "named-friend": name = "Synthetic Named"
        case "long-friend": name = "Synthetic Parent With A Long Compound Family Name"
        default: throw FixtureError.unsupported
        }
        // A relaunch may follow edits or creation of linked people. Never
        // overwrite an existing fixture or mix it into another notebook.
        if store.people.contains(where: { $0.id == token }) { return }
        guard store.people.isEmpty && store.parentLinks.isEmpty && store.partnerLinks.isEmpty else {
            throw FixtureError.nonemptyNotebook
        }
        var friend = Person(id: token, firstName: name, connections: [.friend])
        friend.isListed = true
        try store.savePerson(friend)
    }
}
#endif
