#if DEBUG
import Foundation
import Testing
@testable import Kin

@Suite("Isolated synthetic notebook fixtures") @MainActor struct SyntheticNotebookFixtureTests {
    @Test("Fixture arguments require one isolated notebook and reject previews")
    func isolationArguments() throws {
        let token = UUID().uuidString
        #expect(try SyntheticNotebookFixture.selection(arguments: ["Kin"]) == nil)
        #expect(try SyntheticNotebookFixture.selection(arguments: ["--kin-test-notebook", token, "--kin-ui-fixture", "named-friend"]) == "named-friend")
        for arguments in [
            ["--kin-ui-fixture", "named-friend"],
            ["--kin-test-notebook", "not-a-token", "--kin-ui-fixture", "named-friend"],
            ["--kin-test-notebook", token, "--kin-ui-fixture"],
            ["--kin-test-notebook", token, "--kin-ui-fixture", "named-friend", "--kin-preview"],
            ["--kin-test-notebook", token, "--kin-ui-fixture", "named-friend", "--kin-ui-fixture", "long-friend"],
            ["--kin-test-notebook", token, "--kin-test-notebook", token, "--kin-ui-fixture", "named-friend"]
        ] {
            #expect(throws: SyntheticNotebookFixture.FixtureError.invalidArguments) {
                try SyntheticNotebookFixture.selection(arguments: arguments)
            }
        }
    }
    @Test("Cancel-rendering fixture matches an uncategorized saved person", arguments: [
        ("cancel-standard", "Synthetic Cancel Standard"), ("cancel-large", "Synthetic Cancel Large")
    ])
    func cancelRenderingFixture(_ selection: String, _ name: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let token = UUID()
        let store = try KinStore(storeURL: directory.appendingPathComponent("fixture.sqlite"))
        defer { try? store.close() }
        try SyntheticNotebookFixture.seed(selection, token: token, store: store)
        let person = try #require(store.people.first)
        #expect(store.people.count == 1 && person.id == token && person.firstName == name)
        #expect(person.connections.isEmpty && person.isListed && person.reference == 1)
        #expect(person.lastName == nil && person.gender == .unknown && person.notes.isEmpty && person.photo == nil)
        #expect(person.birthday == .unknown && store.parentLinks.isEmpty && store.partnerLinks.isEmpty)
        try store.close(); try store.resume()
        #expect(try store.person(token) == person)
        try SyntheticNotebookFixture.seed(selection, token: token, store: store)
        #expect(store.people == [person])
    }
    @Test("Filter fixture persists exact listed records and preserves later edits")
    func persistedFilterRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let token = UUID()
        let store = try KinStore(storeURL: directory.appendingPathComponent("fixture.sqlite"))
        defer { try? store.close() }
        try SyntheticNotebookFixture.seed("filter-records", token: token, store: store)
        #expect(store.people.count == 3)
        let byName = Dictionary(uniqueKeysWithValues: store.people.map { ($0.firstName, $0) })
        #expect(byName["Alex Morgan"]?.connections == [])
        #expect(byName["Jamie Patel"]?.connections == [.friend])
        #expect(byName["Robin Chen"]?.connections == [.family])
        #expect(store.people.allSatisfy { $0.isListed && $0.birthday == .unknown })
        #expect(Set(store.people.map(\.reference)) == Set([1, 2, 3]))
        let before = Dictionary(uniqueKeysWithValues: store.people.map { ($0.id, $0) })
        try store.close(); try store.resume()
        #expect(Dictionary(uniqueKeysWithValues: store.people.map { ($0.id, $0) }) == before)
        var changed = try #require(store.people.first { $0.firstName == "Alex Morgan" })
        changed.notes = "Synthetic changed note"
        try store.savePerson(changed)
        try SyntheticNotebookFixture.seed("filter-records", token: token, store: store)
        #expect(try store.person(changed.id).notes == "Synthetic changed note")
        #expect(store.people.count == 3)
    }

    @Test("Friend fixture retains exact initial data and never overwrites later edits", arguments: [
        ("named-friend", "Synthetic Named"),
        ("long-friend", "Synthetic Parent With A Long Compound Family Name")
    ])
    func persistedAndIdempotent(_ selection: String, _ name: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let token = UUID()
        let store = try KinStore(storeURL: directory.appendingPathComponent("fixture.sqlite"))
        defer { try? store.close() }
        try SyntheticNotebookFixture.seed(selection, token: token, store: store)
        let original = try #require(store.people.first)
        #expect(store.people.count == 1 && original.id == token && original.firstName == name)
        #expect(original.connections == [.friend] && original.isListed && original.reference == 1)
        #expect(original.lastName == nil && original.gender == .unknown && original.notes.isEmpty && original.photo == nil)
        #expect(original.birthday == .unknown && store.parentLinks.isEmpty && store.partnerLinks.isEmpty)
        var changed = original; changed.firstName = "Synthetic Edited"; changed.connections = []
        try store.savePerson(changed)
        let child = Person(firstName: "Synthetic Child")
        try store.savePerson(child, relationship: .child(of: token, parentage: .unspecified))
        try store.close(); try store.resume()
        let saved = try store.person(token), people = store.people, links = store.parentLinks
        try SyntheticNotebookFixture.seed(selection, token: token, store: store)
        #expect(store.people == people && store.parentLinks == links && links.count == 1)
        #expect(store.people.contains(where: { $0.id == child.id }))
        #expect(saved.firstName == "Synthetic Edited" && saved.connections.isEmpty)
        #expect(saved.id == token && saved.isListed && saved.reference == 1)
    }

    @Test("Unknown fixtures and another notebook fail without modifying saved records")
    func invalidAndConflict() throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        #expect(throws: SyntheticNotebookFixture.FixtureError.unsupported) {
            try SyntheticNotebookFixture.seed("unknown", token: UUID(), store: store)
        }
        #expect(store.people.isEmpty)
        let existing = Person(firstName: "Synthetic Existing")
        try store.savePerson(existing)
        let before = store.people
        #expect(throws: SyntheticNotebookFixture.FixtureError.nonemptyNotebook) {
            try SyntheticNotebookFixture.seed("named-friend", token: UUID(), store: store)
        }
        #expect(store.people == before && store.parentLinks.isEmpty && store.partnerLinks.isEmpty)
    }

    @Test("Two Friend fixtures retain identities, references and later links on reopen", arguments: [
        ("partner-friends", "Synthetic A", "Synthetic B"),
        ("young-parent-friends", "Synthetic Young", "Synthetic Existing Parent")
    ])
    func pairedFixtures(_ selection: String, _ firstName: String, _ secondName: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let token = UUID()
        let store = try KinStore(storeURL: directory.appendingPathComponent("fixture.sqlite"))
        defer { try? store.close() }
        try SyntheticNotebookFixture.seed(selection, token: token, store: store)
        let first = try #require(store.people.first(where: { $0.firstName == firstName }))
        let second = try #require(store.people.first(where: { $0.firstName == secondName }))
        #expect(store.people.count == 2 && first.id == token && second.id != token)
        #expect(first.reference == 1 && second.reference == 2)
        #expect(first.isListed && second.isListed && first.connections == [.friend] && second.connections == [.friend])
        #expect(first.birthday == .unknown && second.birthday == .unknown)
        #expect(first.gender == .unknown && second.gender == .unknown && first.lastName == nil && second.lastName == nil)
        #expect(first.notes.isEmpty && second.notes.isEmpty && first.photo == nil && second.photo == nil)
        #expect(store.parentLinks.isEmpty && store.partnerLinks.isEmpty)
        try store.savePartnerLink(PartnerLink(firstID: first.id, secondID: second.id, status: .former))
        try store.close(); try store.resume()
        let people = store.people, links = store.partnerLinks
        try SyntheticNotebookFixture.seed(selection, token: token, store: store)
        #expect(store.people == people && store.partnerLinks == links && links.count == 1)
        #expect(links.first?.status == .former)
    }

    @Test("A paired fixture notebook reopens after deleting one person without reseeding")
    func pairedFixtureDeletionReopensWithoutReseeding() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let token = UUID()
        let store = try KinStore(storeURL: directory.appendingPathComponent("fixture.sqlite"))
        defer { try? store.close() }
        try SyntheticNotebookFixture.seed("partner-friends", token: token, store: store)
        try store.deletePerson(token)
        try store.close(); try store.resume()
        #expect(store.people.map(\.firstName) == ["Synthetic B"])
        #expect(throws: SyntheticNotebookFixture.FixtureError.nonemptyNotebook) {
            try SyntheticNotebookFixture.seed("partner-friends", token: token, store: store)
        }
        #expect(store.people.map(\.firstName) == ["Synthetic B"])
    }

    @Test("Partial two-person setup fails closed rather than silently completing or overwriting", arguments: ["partner-friends", "young-parent-friends"])
    func partialPairedFixture(_ selection: String) throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        let token = UUID()
        var first = Person(id: token, firstName: "Synthetic A", connections: [.friend])
        first.isListed = true
        try store.savePerson(first)
        let before = store.people
        #expect(throws: SyntheticNotebookFixture.FixtureError.nonemptyNotebook) {
            try SyntheticNotebookFixture.seed(selection, token: token, store: store)
        }
        #expect(store.people == before && store.parentLinks.isEmpty && store.partnerLinks.isEmpty)
    }

    @Test("Estimated adult fixtures preserve exact initial data and later edits on reopen", arguments: [
        ("estimated-age-boundary", "Synthetic Older"),
        ("estimated-age-largest", "Synthetic Large Age"),
        ("estimated-photo", "Synthetic Photo"),
        ("estimated-contact-draft", "Synthetic Existing Draft")
    ])
    func estimatedAdultFixture(_ selection: String, _ name: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let token = UUID(), today = CivilDate(year: 2026, month: 10, day: 27)
        let store = try KinStore(storeURL: directory.appendingPathComponent("fixture.sqlite"))
        defer { try? store.close() }
        try SyntheticNotebookFixture.seed(selection, token: token, store: store, today: today)
        var adult = try #require(store.people.first)
        #expect(store.people.count == 1 && adult.id == token && adult.firstName == name && adult.reference == 1)
        #expect(adult.birthday == .estimated(age: 80, referenceDate: today))
        #expect(adult.connections == [.friend] && adult.isListed && adult.gender == .unknown)
        #expect(adult.lastName == nil && adult.notes.isEmpty && adult.photo == nil)
        #expect(AgeRules(calendar: CivilDate.pickerCalendar).allowsPhoto(adult.birthday, on: today.pickerDate))
        #expect(store.parentLinks.isEmpty && store.partnerLinks.isEmpty)
        adult.birthday = .estimated(age: 19, referenceDate: today)
        try store.savePerson(adult); try store.close(); try store.resume()
        let edited = store.people
        try SyntheticNotebookFixture.seed(selection, token: token, store: store,
                                          today: CivilDate(year: 2026, month: 10, day: 28))
        #expect(store.people == edited && store.people.first?.birthday == .estimated(age: 19, referenceDate: today))
    }

    @Test("Estimated adult fixtures never overwrite another notebook", arguments: [
        "estimated-age-boundary", "estimated-age-largest", "estimated-photo", "estimated-contact-draft"
    ])
    func estimatedAdultRejectsNonemptyNotebook(_ selection: String) throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        try store.savePerson(Person(firstName: "Synthetic Existing"))
        let before = store.people
        #expect(throws: SyntheticNotebookFixture.FixtureError.nonemptyNotebook) {
            try SyntheticNotebookFixture.seed(selection, token: UUID(), store: store)
        }
        #expect(store.people == before && store.parentLinks.isEmpty && store.partnerLinks.isEmpty)
    }
    @Test("Paired fixture matches two normally saved Friend drafts")
    func pairedFixtureMatchesDirectDrafts() throws {
        let seeded = try KinStore(inMemory: true)
        let direct = try KinStore(inMemory: true)
        defer { try? seeded.close(); try? direct.close() }
        try SyntheticNotebookFixture.seed("partner-friends", token: UUID(), store: seeded)
        for name in ["Synthetic A", "Synthetic B"] {
            var draft = PersonDraftDefaults.newPerson(relationship: nil, people: direct.people)
            draft.firstName = name
            var gender = DraftGenderDefault(value: draft.gender, isNew: true)
            gender.nameChanged(name, lookup: NameAssociations.bundled.gender)
            draft.gender = gender.value
            draft.connections.insert(.friend)
            try direct.savePerson(draft)
        }
        #expect(seeded.people.count == 2 && direct.people.count == 2)
        for name in ["Synthetic A", "Synthetic B"] {
            let fixture = try #require(seeded.people.first { $0.firstName == name })
            let saved = try #require(direct.people.first { $0.firstName == name })
            #expect(fixture.firstName == saved.firstName && fixture.lastName == saved.lastName)
            #expect(fixture.gender == saved.gender && fixture.birthday == saved.birthday)
            #expect(fixture.connections == saved.connections && fixture.indexInclusion == saved.indexInclusion)
            #expect(fixture.reference == saved.reference && fixture.revision == saved.revision)
            #expect(fixture.notes == saved.notes && fixture.photo == saved.photo && fixture.unnamedRole == saved.unnamedRole)
        }
        #expect(seeded.parentLinks.isEmpty && seeded.partnerLinks.isEmpty)
        #expect(direct.parentLinks.isEmpty && direct.partnerLinks.isEmpty)
    }

}
#endif

