import Foundation
import CoreData
import Testing
@testable import Kin

@MainActor private final class SaveFailure {
    var fail = false
    var committed = false
    var corruptAge: Int?
}
@Suite("Store preservation and transaction recovery") @MainActor struct StoreSafetyTests {
    @Test("An earlier model is rejected without touching its bytes or silently resetting", arguments: [false, true])
    func oldModel(liveWAL: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.sqlite")
        let model = NSManagedObjectModel(), entity = NSEntityDescription(), id = NSAttributeDescription()
        entity.name = "FriendRecord"; entity.managedObjectClassName = "NSManagedObject"
        id.name = "id"; id.attributeType = .UUIDAttributeType
        entity.properties = [id]; model.entities = [entity]
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let legacy = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType); context.persistentStoreCoordinator = coordinator
        let object = NSEntityDescription.insertNewObject(forEntityName: "FriendRecord", into: context)
        object.setValue(UUID(), forKey: "id"); try context.save(); context.reset()
        if !liveWAL { try coordinator.remove(legacy) }
        defer { if liveWAL { try? coordinator.remove(legacy) } }
        if liveWAL { #expect(try Data(contentsOf: URL(fileURLWithPath: url.path + "-wal")).count > 32) }
        let before = try snapshot(directory)
        #expect(throws: KinError.incompatibleStore) { _ = try KinStore(storeURL: url) }
        #expect(try snapshot(directory) == before)
        // Original model still opens and reads its record afterward.
        if liveWAL { try coordinator.remove(legacy) }
        let reopened = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url)
        #expect(try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "FriendRecord")) == 1)
        context.reset(); try coordinator.remove(reopened)
    }
    @Test("Missing main database with surviving companions is never treated as a fresh notebook")
    func orphanedCompanions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite")
        let companion = directory.appendingPathComponent("test.sqlite-wal")
        let bytes = Data("Synthetic surviving companion".utf8); try bytes.write(to: companion)
        #expect(throws: KinError.invalidData) { _ = try KinStore(storeURL: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: companion) == bytes)
    }
    @Test("Corrupt-store failure preserves the source instead of creating an empty notebook")
    func corruptStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("corrupt.sqlite")
        let bytes = Data("Synthetic deliberately invalid notebook".utf8); try bytes.write(to: url)
        #expect(throws: (any Error).self) { _ = try KinStore(storeURL: url) }
        #expect(try Data(contentsOf: url) == bytes)
    }
    @Test("Failed confirmed photo removal leaves persisted adult age and photo intact")
    func failedRemoval() throws {
        let failure = SaveFailure()
        let store = try KinStore(inMemory: true, saveContext: { if failure.fail { throw CocoaError(.fileWriteNoPermission) }; try $0.save() })
        defer { try? store.close() }
        let value = Person(firstName: "Synthetic", birthday: .exact(CivilDate(year: 1980, month: 1, day: 1)), photo: Data([3,4,5]))
        try store.savePerson(value)
        let original = try store.person(value.id)
        var edit = original; edit.birthday = .unknown
        failure.fail = true
        #expect(throws: (any Error).self) { try store.savePerson(edit, confirmPhotoRemoval: true) }
        try store.reload(); #expect(try store.person(value.id) == original)
        failure.fail = false
        try store.savePerson(edit, confirmPhotoRemoval: true)
        #expect(try store.person(value.id).photo == nil)
    }
    @Test("Deletion rolls back identity and every link when saving fails")
    func failedDelete() throws {
        let failure = SaveFailure()
        let store = try KinStore(inMemory: true, saveContext: { if failure.fail { throw CocoaError(.fileWriteNoPermission) }; try $0.save() })
        defer { try? store.close() }
        let a = Person(), b = Person(); try store.savePerson(a); try store.savePerson(b)
        let parent = ParentLink(parentID: a.id, childID: b.id), partner = PartnerLink(firstID: a.id, secondID: b.id)
        try store.saveParentLink(parent); try store.savePartnerLink(partner)
        failure.fail = true
        #expect(throws: (any Error).self) { try store.deletePerson(a.id) }
        try store.reload()
        #expect(store.people.count == 2 && store.parentLinks == [parent] && store.partnerLinks == [partner])
        #expect(throws: (any Error).self) { try store.unlinkPartner(partner.id) }
        #expect(store.partnerLinks == [partner])
    }
    @Test("Creation/link explicit retry after post-commit failure does not duplicate either", arguments: [false,true], [false,true])
    func postCommit(committed: Bool, addingParent: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let failure = SaveFailure()
        let store = try KinStore(storeURL: directory.appendingPathComponent("test.sqlite"), saveContext: {
            if failure.fail { if committed { try $0.save() }; throw CocoaError(.fileReadNoPermission) }
            try $0.save()
        })
        defer { try? store.close() }
        let parent = Person(); try store.savePerson(parent)
        let child = Person(); failure.fail = true
        let relationship: NewRelationship = addingParent ? .parent(of: parent.id, parentage: .adoptive) : .child(of: parent.id, parentage: .adoptive)
        #expect(throws: (any Error).self) { try store.savePerson(child, relationship: relationship) }
        #expect(!store.isReady && store.isClosed)
        failure.fail = false; try store.resume()
        #expect(store.people.count == (committed ? 2 : 1))
        try store.savePerson(child, relationship: relationship)
        #expect(store.people.count == 2 && store.parentLinks.count == 1)
        #expect(store.parentLinks.first?.parentID == (addingParent ? child.id : parent.id))
        #expect(store.parentLinks.first?.childID == (addingParent ? parent.id : child.id))
    }
    @Test("Compatible corrupt person payload is rejected before opening or modifying source files", arguments: [Int.min,-1,121,Int.max])
    func corruptPayload(age: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite"), failure = SaveFailure()
        let store = try KinStore(storeURL: url, saveContext: { context in
            if let age = failure.corruptAge, let object = context.updatedObjects.first(where: { $0.entity.name == "PersonRecord" }) {
                var broken = try JSONDecoder().decode(Person.self,from: object.value(forKey: "payload") as! Data)
                broken.birthday = .estimated(age: age,referenceDate: CivilDate(year: 2020,month: 1,day: 1))
                object.setValue(try JSONEncoder().encode(broken),forKey: "payload")
            }
            try context.save()
        })
        let p = Person(); try store.savePerson(p)
        var edit = try store.person(p.id); edit.notes = "Synthetic deliberate corruption fixture"
        failure.corruptAge = age
        #expect(throws: KinError.invalidData) { try store.savePerson(edit) }
        try store.close()
        let before = try snapshot(directory)
        #expect(throws: KinError.invalidData) { _ = try KinStore(storeURL: url) }
        #expect(try snapshot(directory) == before)
    }
    @Test("A valid stated age of 120 remains readable and eligible after another year")
    func naturallyAgedEstimate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite")
        let store = try KinStore(storeURL: url)
        let birthday = Birthday.estimated(age: 120,referenceDate: CivilDate(year: 2025,month: 1,day: 1))
        let p = Person(birthday: birthday,photo: Data([1,2,3]))
        try store.savePerson(p,today: CivilDate(year: 2025,month: 1,day: 1).pickerDate)
        try store.close()
        let reopened = try KinStore(storeURL: url); defer { try? reopened.close() }
        let saved = try reopened.person(p.id), today = CivilDate(year: 2026,month: 1,day: 1).pickerDate
        #expect(AgeRules(calendar: CivilDate.pickerCalendar).age(for: saved.birthday,on: today) == 121)
        #expect(saved.visiblePhoto(on: today,calendar: CivilDate.pickerCalendar) == p.photo)
        var edit = saved; edit.notes = "Natural aging does not invalidate an unchanged estimate"
        try reopened.savePerson(edit,today: today)
    }
    @Test("Core Data mandatory-property validation failure rolls back a whole transaction", arguments: [false,true])
    func genuineValidationFailure(creating: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let failure = SaveFailure()
        let store = try KinStore(storeURL: directory.appendingPathComponent("test.sqlite"),saveContext: { context in
            if failure.fail {
                let object = creating ? context.insertedObjects.first(where: { $0.entity.name == "ParentLinkRecord" }) : context.updatedObjects.first(where: { $0.entity.name == "PersonRecord" })
                object?.setValue(nil,forKey: "payload")
            }
            try context.save()
        })
        defer { try? store.close() }
        let p = Person(firstName: "Synthetic",birthday: .exact(CivilDate(year: 1980,month: 1,day: 1)),photo: Data([1,2,3]))
        try store.savePerson(p)
        let original = try store.person(p.id), child = Person()
        var edit = original; edit.photo = Data([4,5]); edit.notes = "Unsaved change"
        failure.fail = true
        var cocoaValidationError = false
        do {
            if creating { try store.savePerson(child,relationship: .child(of: p.id,parentage: .adoptive)) }
            else { try store.savePerson(edit) }
        } catch { cocoaValidationError = (error as NSError).domain == NSCocoaErrorDomain }
        #expect(cocoaValidationError && !store.isReady)
        failure.fail = false; try store.resume()
        #expect(store.people == [original] && store.parentLinks.isEmpty)
        #expect(try store.entityCount("PersonRecord") == 1)
        if creating {
            try store.savePerson(child,relationship: .child(of: p.id,parentage: .adoptive))
            #expect(try store.person(child.id).reference == 2)
        } else { try store.savePerson(edit); #expect(try store.person(p.id).photo == edit.photo) }
    }
    private func snapshot(_ directory: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) {
            if try !file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory! { result[file.lastPathComponent] = try Data(contentsOf: file) }
        }
        return result
    }
}
