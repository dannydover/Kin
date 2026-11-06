#if DEBUG
import Foundation
import Testing
@testable import Kin

@Suite("Role-label synthetic notebook") @MainActor
struct RoleLabelFixtureTests {
    @Test("Three listed friends keep identities and later links after reopening")
    func roleLabelFixture() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let token = UUID()
        let store = try KinStore(storeURL: directory.appendingPathComponent("role-label.sqlite"))
        defer { try? store.close() }
        try SyntheticNotebookFixture.seed("role-label-friends", token: token, store: store)
        let a = try #require(store.people.first { $0.firstName == "Synthetic A" })
        let b = try #require(store.people.first { $0.firstName == "Synthetic B" })
        var child = try #require(store.people.first { $0.firstName == "Synthetic Child" })
        #expect(store.people.count == 3 && Set([a.id, b.id, child.id]).count == 3 && a.id == token)
        #expect(a.reference == 1 && b.reference == 2 && child.reference == 3)
        for person in [a, b, child] {
            #expect(person.isListed && person.connections == [.friend])
            #expect(person.birthday == .unknown && person.gender == .unknown)
            #expect(person.lastName == nil && person.notes.isEmpty && person.photo == nil)
        }
        #expect(store.parentLinks.isEmpty && store.partnerLinks.isEmpty)
        child.notes = "Synthetic later edit"
        try store.savePerson(child)
        try store.saveParentLink(ParentLink(parentID: a.id, childID: child.id, parentage: .step))
        try store.close(); try store.resume()
        let people = store.people, links = store.parentLinks
        try SyntheticNotebookFixture.seed("role-label-friends", token: token, store: store)
        #expect(store.people == people && store.parentLinks == links && links.count == 1)
        #expect(try store.person(child.id).notes == "Synthetic later edit")
        #expect(links.first?.parentID == a.id && links.first?.childID == child.id)
    }

    @Test("Partial fixture fails closed without overwriting data")
    func partialFixture() throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        let token = UUID()
        try store.savePerson(Person(id: token, firstName: "Synthetic A", connections: [.friend]))
        let before = store.people
        #expect(throws: SyntheticNotebookFixture.FixtureError.nonemptyNotebook) {
            try SyntheticNotebookFixture.seed("role-label-friends", token: token, store: store)
        }
        #expect(store.people == before && store.parentLinks.isEmpty && store.partnerLinks.isEmpty)
    }
}
#endif
