import Foundation
import Testing
@testable import Kin

@Suite("Sequential reviewed imports across store restarts") @MainActor
struct SequentialImportRestartTests {
    @Test("Four routes retain every earlier person and relationship after each reopen")
    func fourRoutes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sequential-routes.sqlite")
        var store = try KinStore(storeURL: url)
        defer { try? store.close() }
        let source = Person(firstName: "Synthetic source")
        try store.savePerson(source)
        var imported: [Person] = []

        for route in 0..<4 {
            let relationship: NewRelationship? = switch route {
            case 1: .parent(of: source.id, parentage: .step)
            case 2: .child(of: source.id, parentage: .unspecified)
            case 3: .partner(of: source.id, status: .current)
            default: nil
            }
            let draft = Person(firstName: "Synthetic Saved \(route)", lastName: "Appleseed")
            try NewContactImportCommit().save(draft, store: store, relationship: relationship)
            imported.append(try store.person(draft.id))
            let people = store.people
            let parents = store.parentLinks
            let partners = store.partnerLinks
            try store.close()
            store = try KinStore(storeURL: url)

            #expect(store.people == people)
            #expect(store.parentLinks == parents)
            #expect(store.partnerLinks == partners)
            #expect(store.people.count == route + 2)
            #expect(store.parentLinks.count == min(route, 2))
            #expect(store.partnerLinks.count == (route == 3 ? 1 : 0))
            for (index, expected) in imported.enumerated() {
                let saved = try store.person(expected.id)
                #expect(saved == expected)
                #expect(saved.firstName == "Synthetic Saved \(index)")
                #expect(saved.isListed == (index == 0))
                #expect(PeopleIndex.results(store.people, query: "", includeUnlisted: true).contains { $0.id == expected.id })
            }
            if route >= 1 {
                #expect(store.parentLinks.contains { $0.parentID == imported[1].id && $0.childID == source.id && $0.parentage == .step })
            }
            if route >= 2 {
                #expect(store.parentLinks.contains { $0.parentID == source.id && $0.childID == imported[2].id && $0.parentage == .unspecified })
            }
            if route >= 3 {
                #expect(store.partnerLinks.contains { Set([$0.firstID, $0.secondID]) == Set([source.id, imported[3].id]) && $0.status == .current })
            }
        }
    }
}
