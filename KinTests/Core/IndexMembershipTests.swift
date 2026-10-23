import Foundation
import CoreData
import Testing
@testable import Kin

@Suite("Explicit index membership and legacy notebooks") @MainActor struct IndexMembershipTests {
    @Test("Missing membership decodes with original visibility; explicit true and false round trip")
    func decoding() throws {
        for connections: Set<Connection> in [[],[.friend]] {
            let original = Person(firstName: "Synthetic Legacy",connections: connections)
            var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String:Any])
            payload.removeValue(forKey: "indexInclusion")
            let legacy = try JSONDecoder().decode(Person.self,from: JSONSerialization.data(withJSONObject: payload))
            #expect(legacy.id == original.id && legacy.isListed == !connections.isEmpty)
            for listed in [true,false] {
                var explicit = legacy; explicit.isListed = listed
                let decoded = try JSONDecoder().decode(Person.self,from: JSONEncoder().encode(explicit))
                #expect(decoded == explicit && decoded.isListed == listed)
            }
            payload["indexInclusion"] = "invalid"
            #expect(throws: (any Error).self) { try JSONDecoder().decode(Person.self,from: JSONSerialization.data(withJSONObject: payload)) }
        }
    }
    @Test("Direct drafts are listed without categories; linked drafts opt in explicitly")
    func defaults() {
        let source = Person()
        let direct = PersonDraftDefaults.newPerson(relationship: nil,people: [])
        #expect(direct.isListed && direct.connections.isEmpty)
        for link: NewRelationship in [.parent(of: source.id,parentage: .unspecified),.child(of: source.id,parentage: .step),.partner(of: source.id,status: .current)] {
            let draft = PersonDraftDefaults.newPerson(relationship: link,people: [source])
            #expect(!draft.isListed && draft.connections.isEmpty)
        }
    }
    @Test("Legacy SQLite payloads preserve visibility, identities, precision, photos and links without write-on-open")
    func legacyNotebook() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.sqlite")
        let store = try KinStore(storeURL: url,saveContext: { context in
            for object in try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "PersonRecord")) {
                let data = try #require(object.value(forKey: "payload") as? Data)
                var payload = try #require(JSONSerialization.jsonObject(with: data) as? [String:Any])
                payload.removeValue(forKey: "indexInclusion")
                object.setValue(try JSONSerialization.data(withJSONObject: payload),forKey: "payload")
            }
            try context.save()
        })
        let visible = Person(firstName: "Synthetic Listed",birthday: .exact(CivilDate(year: 1980,month: 1,day: 1)),connections: [.family],photo: Data([1,2,3]))
        var hidden = Person(firstName: "Synthetic Linked",birthday: .estimated(age: 3,referenceDate: CivilDate(year: 2026,month: 1,day: 1)))
        hidden.notes = "Synthetic preserved note"
        try store.savePerson(visible)
        try store.savePerson(hidden,relationship: .child(of: visible.id,parentage: .step))
        let expected = store.people, links = store.parentLinks
        try store.close()
        var writes = 0
        let reopened = try KinStore(storeURL: url,saveContext: { writes += 1; try $0.save() }); defer { try? reopened.close() }
        #expect(writes == 0 && reopened.people == expected && reopened.parentLinks == links)
        #expect(PeopleIndex.results(reopened.people,query: "").map(\.id) == [visible.id])
        var first = try reopened.person(visible.id); first.connections = []
        var second = try reopened.person(hidden.id); second.connections = [.friend]
        try reopened.savePerson(first); try reopened.savePerson(second)
        #expect(try reopened.person(visible.id).isListed)
        #expect(try !reopened.person(hidden.id).isListed)
        first = try reopened.person(visible.id); first.isListed = false
        second = try reopened.person(hidden.id); second.isListed = true
        try reopened.savePerson(first); try reopened.savePerson(second)
        try reopened.close(); try reopened.resume()
        #expect(PeopleIndex.results(reopened.people,query: "").map(\.id) == [hidden.id])
        #expect(reopened.parentLinks == links && reopened.people.count == 2)
        #expect(try reopened.person(visible.id).photo == visible.photo)
        #expect(try reopened.person(hidden.id).birthday == hidden.birthday)
    }
    @Test("Failed direct save retains draft and retries once, before and after commit", arguments: [false,true])
    func failure(afterCommit: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var fail = true
        let store = try KinStore(storeURL: directory.appendingPathComponent("direct.sqlite"),saveContext: { context in
            if fail && !afterCommit { throw CocoaError(.fileWriteNoPermission) }
            try context.save()
            if fail && afterCommit { throw CocoaError(.fileWriteNoPermission) }
        }); defer { try? store.close() }
        let draft = PersonDraftDefaults.newPerson(relationship: nil,people: [])
        #expect(throws: (any Error).self) { try store.savePerson(draft) }
        fail = false; try store.resume()
        #expect(store.people.count == (afterCommit ? 1 : 0))
        try store.savePerson(draft); try store.savePerson(draft)
        #expect(store.people.count == 1 && store.people.first?.isListed == true)
        #expect(store.people.first?.id == draft.id && store.people.first?.connections.isEmpty == true)
    }
}
