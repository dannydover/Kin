import Foundation
import CoreData
import Testing
@testable import Kin

@MainActor private final class DeleteFailure { var active = false; var unlocked = true }
@Suite("Delete all notebook people safely") @MainActor struct DeleteAllPeopleTests {
    private func seed(_ store: KinStore, photo: Data? = nil) throws -> [Person] {
        var source = Person(firstName: "Synthetic Listed",birthday: .exact(CivilDate(year: 1980,month: 1,day: 1)),connections: [.friend],photo: photo)
        source.notes = "Synthetic private note"
        let hidden = Person(firstName: "Synthetic Hidden"), partner = Person(firstName: "Synthetic Partner")
        try store.savePerson(source)
        try store.savePerson(hidden,relationship: .child(of: source.id,parentage: .step))
        try store.savePerson(partner,relationship: .partner(of: source.id,status: .former))
        return store.people
    }
    @Test("All people, hidden people, notes, links and managed media disappear together and stay deleted")
    func allPeopleAndMedia() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let notebook = directory.appendingPathComponent("notebook")
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        let unrelated = directory.appendingPathComponent("synthetic-unrelated-settings")
        let settings = Data("Synthetic settings and external copy stay".utf8); try settings.write(to: unrelated)
        let store = try KinStore(storeURL: notebook.appendingPathComponent("test.sqlite")); defer { try? store.close() }
        let photo = Data((0..<1_000_000).map { UInt8($0 % 251) })
        _ = try seed(store,photo: photo)
        func mediaFiles() -> [URL] {
            (FileManager.default.enumerator(at: notebook,includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
                .filter { $0.path.contains("_EXTERNAL_DATA") && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        }
        #expect(!mediaFiles().isEmpty, "Large synthetic media must exercise Core Data external storage")
        try store.deleteAllPeople(); try store.deleteAllPeople()
        #expect(store.people.isEmpty && store.parentLinks.isEmpty && store.partnerLinks.isEmpty)
        for entity in ["PersonRecord","ParentLinkRecord","PartnerLinkRecord"] { #expect(try store.entityCount(entity) == 0) }
        #expect(mediaFiles().isEmpty)
        try store.close(); try store.resume()
        #expect(store.people.isEmpty && store.parentLinks.isEmpty && store.partnerLinks.isEmpty && mediaFiles().isEmpty)
        #expect(try Data(contentsOf: unrelated) == settings)
        let new = PersonDraftDefaults.newPerson(relationship: nil,people: [])
        try store.savePerson(new)
        #expect(try store.person(new.id).reference == 4, "Notebook counter is retained without reusing identities")
    }
    @Test("Empty deletion is idempotent and performs no save")
    func empty() throws {
        var writes = 0
        let store = try KinStore(inMemory: true,saveContext: { writes += 1; try $0.save() }); defer { try? store.close() }
        try store.deleteAllPeople(); try store.deleteAllPeople()
        #expect(writes == 0 && store.people.isEmpty)
    }
    @Test("Failure before or after commit reopens a consistent notebook without automatic replay", arguments: [false,true])
    func failure(afterCommit: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let failure = DeleteFailure()
        let store = try KinStore(storeURL: directory.appendingPathComponent("test.sqlite"),saveContext: { context in
            if failure.active && !afterCommit { throw CocoaError(.fileWriteNoPermission) }
            try context.save()
            if failure.active && afterCommit { throw CocoaError(.fileWriteNoPermission) }
        }); defer { try? store.close() }
        let people = try seed(store,photo: Data([1,2,3])), parents = store.parentLinks, partners = store.partnerLinks
        failure.active = true
        #expect(throws: (any Error).self) { try store.deleteAllPeople() }
        #expect(!store.isReady && store.isClosed)
        failure.active = false; try store.resume()
        if afterCommit { #expect(store.people.isEmpty && store.parentLinks.isEmpty && store.partnerLinks.isEmpty) }
        else { #expect(store.people == people && store.parentLinks == parents && store.partnerLinks == partners) }
        try store.deleteAllPeople(); try store.close(); try store.resume()
        #expect(store.people.isEmpty && store.parentLinks.isEmpty && store.partnerLinks.isEmpty)
    }
    @Test("Unavailable protected data prevents deletion; unconfirmed interruption preserves every record")
    func protectedAndInterrupted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = DeleteFailure()
        let store = try KinStore(storeURL: directory.appendingPathComponent("test.sqlite"),protectedDataAvailable: { state.unlocked }); defer { try? store.close() }
        let people = try seed(store,photo: Data([4,5,6])), parents = store.parentLinks, partners = store.partnerLinks
        try store.close(); try store.resume()
        #expect(store.people == people && store.parentLinks == parents && store.partnerLinks == partners)
        state.unlocked = false
        #expect(throws: NotebookAccessError.locked) { try store.deleteAllPeople() }
        state.unlocked = true; try store.resume()
        #expect(store.people == people && store.parentLinks == parents && store.partnerLinks == partners)
    }
}
