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
}
#endif
