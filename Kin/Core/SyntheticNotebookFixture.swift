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

    @MainActor static func seed(_ selection: String, token: UUID, store: KinStore,
                                today: CivilDate = CivilDate(Date(), timeZone: .current)) throws {
        let records: [(UUID, String)]
        let birthday: Birthday
        switch selection {
        case "named-friend": records = [(token, "Synthetic Named")]; birthday = .unknown
        case "long-friend": records = [(token, "Synthetic Parent With A Long Compound Family Name")]; birthday = .unknown
        case "partner-friends", "young-parent-friends":
            var bytes = token.uuid
            bytes.15 ^= 0xff
            let names = selection == "partner-friends" ? ("Synthetic A", "Synthetic B") : ("Synthetic Young", "Synthetic Existing Parent")
            records = [(token, names.0), (UUID(uuid: bytes), names.1)]
            birthday = .unknown
        case "estimated-age-boundary", "estimated-age-largest", "estimated-photo", "estimated-contact-draft":
            let names = ["estimated-age-boundary": "Synthetic Older", "estimated-age-largest": "Synthetic Large Age",
                         "estimated-photo": "Synthetic Photo", "estimated-contact-draft": "Synthetic Existing Draft"]
            guard let name = names[selection] else { throw FixtureError.unsupported }
            records = [(token, name)]
            birthday = .estimated(age: 80, referenceDate: today)
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
            var friend = Person(id: id, firstName: name, birthday: birthday, connections: [.friend])
            friend.isListed = true
            try store.savePerson(friend)
        }
    }
}
#endif
