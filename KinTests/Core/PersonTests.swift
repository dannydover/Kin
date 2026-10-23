import Foundation
import CoreData
import Testing
@testable import Kin

private let testDay = CivilDate(year: 2026, month: 10, day: 15)
private let testNow = testDay.pickerDate
private let utc = CivilDate.pickerCalendar
private func adult(_ name: String = "Synthetic") -> Person {
    Person(firstName: name, birthday: .exact(CivilDate(year: 1980, month: 2, day: 3)), connections: [.friend])
}
@MainActor private final class FailureSwitch { var enabled = false }
@Suite("Person identity and graph") @MainActor struct PersonTests {
    @Test("Add parent creates the directed link atomically, keeps one stable identity, and persists every parent type", arguments: Parentage.allCases)
    func addParent(parentage: Parentage) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("people.sqlite")
        let store = try KinStore(storeURL: url)
        let child = Person(firstName: "Synthetic Child", birthday: .estimated(age: 3, referenceDate: testDay), connections: [.family])
        let parent = Person(), existing = adult("Synthetic Existing Parent")
        try store.savePerson(child)
        try store.savePerson(parent, relationship: .parent(of: child.id, parentage: parentage))
        try store.savePerson(existing)
        try store.saveParentLink(ParentLink(parentID: existing.id, childID: child.id, parentage: .adoptive))
        let saved = try store.person(parent.id)
        #expect(saved.firstName == nil && saved.displayName == "Parent 2" && saved.connections.isEmpty)
        #expect(PeopleIndex.results(store.people, query: "").count == 2)
        #expect(store.parentLinks.count == 2)
        #expect(store.parentLinks.contains { $0.parentID == parent.id && $0.childID == child.id && $0.parentage == parentage })
        var named = saved; named.firstName = "Named later"; named.notes = "Fictional parent note"
        try store.savePerson(named)
        try store.close()
        let reopened = try KinStore(storeURL: url); defer { try? reopened.close() }
        #expect(reopened.people.count == 3 && reopened.parentLinks.count == 2)
        var unnamed = try reopened.person(parent.id); unnamed.firstName = nil
        try reopened.savePerson(unnamed)
        #expect(try reopened.person(parent.id).displayName == "Parent 2")
        #expect(try reopened.person(parent.id).notes == "Fictional parent note")
        let link = try #require(reopened.parentLinks.first { $0.parentID == parent.id })
        try reopened.unlinkParent(link.id)
        #expect(reopened.people.count == 3 && reopened.parentLinks.count == 1)
        #expect(try reopened.person(existing.id).id == existing.id)
    }
    @Test("Add parent rejects missing children, self links, duplicates, and ancestry cycles before changing people")
    func addParentInvariants() throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        let a = Person(), b = Person(), c = Person()
        for person in [a,b,c] { try store.savePerson(person) }
        try store.saveParentLink(ParentLink(parentID: a.id, childID: b.id))
        try store.saveParentLink(ParentLink(parentID: b.id, childID: c.id))
        let before = store.people
        #expect(throws: KinError.invalidLink) { try store.savePerson(try store.person(a.id), relationship: .parent(of: a.id, parentage: .step)) }
        #expect(throws: KinError.invalidLink) { try store.savePerson(try store.person(a.id), relationship: .parent(of: b.id, parentage: .adoptive)) }
        #expect(throws: KinError.cycle) { try store.savePerson(try store.person(c.id), relationship: .parent(of: a.id, parentage: .biological)) }
        #expect(throws: KinError.missingPerson) { try store.savePerson(Person(), relationship: .parent(of: UUID(), parentage: .unspecified)) }
        #expect(store.people == before && store.parentLinks.count == 2)
    }
    @Test("One identity shared across friendships, partnerships and parent links persists after relaunch")
    func sharedIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("people.sqlite")
        let store = try KinStore(storeURL: url)
        let a = adult("Synthetic A"), b = adult("Synthetic B"), c = Person()
        try store.savePerson(a); try store.savePerson(b)
        try store.savePerson(c, relationship: .child(of: a.id, parentage: .adoptive))
        try store.saveParentLink(ParentLink(parentID: b.id, childID: c.id, parentage: .step))
        try store.savePartnerLink(PartnerLink(firstID: a.id, secondID: b.id, status: .current))
        var edit = try store.person(b.id); edit.firstName = "Revised"; edit.connections = [.friend, .family, .colleague]
        try store.savePerson(edit)
        let expected = store.people
        try store.close()
        let reopened = try KinStore(storeURL: url); defer { try? reopened.close() }
        #expect(Set(reopened.people.map(\.id)) == Set(expected.map(\.id)))
        #expect(try reopened.person(b.id).firstName == "Revised")
        #expect(reopened.partnerLinks.count == 1 && reopened.parentLinks.count == 2)
        #expect(PeopleIndex.results(reopened.people, query: "Revised").count == 1)
        #expect(try reopened.entityCount("PersonRecord") == 3)
    }
    @Test("Correcting a profile to under sixteen preserves every explicit relationship on reopen")
    func youngerProfilePreservesRelationships() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("people.sqlite")
        let store = try KinStore(storeURL: url)
        let a = adult("Synthetic A"), b = adult("Synthetic B"), c = Person()
        for person in [a,b,c] { try store.savePerson(person) }
        let parent = ParentLink(parentID: a.id, childID: c.id), partner = PartnerLink(firstID: a.id, secondID: b.id)
        try store.saveParentLink(parent); try store.savePartnerLink(partner)
        var edit = try store.person(a.id); edit.birthday = .estimated(age: 15, referenceDate: testDay)
        try store.savePerson(edit); try store.close()
        let reopened = try KinStore(storeURL: url); defer { try? reopened.close() }
        #expect(reopened.parentLinks == [parent]); #expect(reopened.partnerLinks == [partner])
        #expect(reopened.people.count == 3)
        #expect(!AgeRules(calendar: utc).showsPartnerAndChildSections(for: try reopened.person(a.id).birthday, on: testNow))
    }
    @Test("Unlinking never deletes people; deletion removes only incident links and the person's photo")
    func deletion() throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        var a = adult("A"); a.photo = Data([1, 2, 3])
        let b = adult("B"), c = Person(), unrelated = adult("D")
        for value in [a,b,c,unrelated] { try store.savePerson(value) }
        let parent = ParentLink(parentID: a.id, childID: c.id)
        let partner = PartnerLink(firstID: a.id, secondID: b.id)
        try store.saveParentLink(parent); try store.savePartnerLink(partner)
        try store.unlinkParent(parent.id); try store.unlinkPartner(partner.id)
        #expect(store.people.count == 4 && store.parentLinks.isEmpty && store.partnerLinks.isEmpty)
        try store.saveParentLink(parent); try store.savePartnerLink(partner)
        try store.saveParentLink(ParentLink(parentID: b.id, childID: c.id))
        try store.deletePerson(a.id)
        #expect(store.people.count == 3 && store.partnerLinks.isEmpty)
        #expect(store.parentLinks.count == 1 && store.parentLinks.first?.parentID == b.id)
        #expect(try store.person(b.id).displayName == "B")
        #expect(try store.entityCount("PersonRecord") == 3)
    }
    @Test("Self, duplicate, reversed partner, and deep parent cycles fail atomically")
    func invariants() throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        let a = adult("A"), b = adult("B"), c = adult("C")
        for p in [a,b,c] { try store.savePerson(p) }
        #expect(throws: KinError.invalidLink) { try store.saveParentLink(ParentLink(parentID: a.id, childID: a.id)) }
        #expect(throws: KinError.invalidLink) { try store.savePartnerLink(PartnerLink(firstID: a.id, secondID: a.id)) }
        try store.saveParentLink(ParentLink(parentID: a.id, childID: b.id))
        try store.saveParentLink(ParentLink(parentID: b.id, childID: c.id))
        #expect(throws: KinError.cycle) { try store.saveParentLink(ParentLink(parentID: c.id, childID: a.id)) }
        #expect(throws: KinError.invalidLink) { try store.saveParentLink(ParentLink(parentID: a.id, childID: b.id, parentage: .step)) }
        try store.savePartnerLink(PartnerLink(firstID: a.id, secondID: b.id))
        #expect(throws: KinError.invalidLink) { try store.savePartnerLink(PartnerLink(firstID: b.id, secondID: a.id, status: .former)) }
        #expect(store.parentLinks.count == 2 && store.partnerLinks.count == 1)
        #expect(throws: KinError.missingPerson) { try store.saveParentLink(ParentLink(parentID: a.id, childID: UUID())) }
    }
    @Test("Unknown entry reference is permanent, shared by every relationship, and never reused")
    func unknownNames() throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        let parent = adult(), otherParent = adult("Other"), child = Person(gender: .other)
        try store.savePerson(parent); try store.savePerson(otherParent)
        try store.savePerson(child, relationship: .child(of: parent.id, parentage: .unspecified))
        let saved = try store.person(child.id), label = try store.person(child.id).displayName
        #expect(saved.firstName == nil && saved.nameUnknown && label == "Child 3")
        try store.saveParentLink(ParentLink(parentID: otherParent.id, childID: child.id))
        var edit = saved; edit.firstName = "Named later"; edit.notes = "Fictional note"
        try store.savePerson(edit)
        var renamed = try store.person(child.id); renamed.firstName = nil
        try store.savePerson(renamed)
        #expect(try store.person(child.id).displayName == label)
        #expect(try store.person(child.id).notes == "Fictional note")
        #expect(store.parentLinks.count == 2)
        try store.deletePerson(child.id)
        let next = Person(); try store.savePerson(next)
        #expect(try store.person(next.id).reference == 4)
        var lastOnly = Person(lastName: "Only surname"); try store.savePerson(lastOnly)
        lastOnly = try store.person(lastOnly.id)
        #expect(lastOnly.nameUnknown && lastOnly.displayName == "Person 5 · Only surname")
    }
    @Test("Explicit membership is independent of connections and All people recovers unlisted entries")
    func connections() throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        var a = adult(); a.connections = [.friend, .family, .colleague]
        let b = Person(); try store.savePerson(a); try store.savePerson(b)
        #expect(PeopleIndex.results(store.people, query: "").map(\.id) == [a.id])
        #expect(PeopleIndex.results(store.people, query: "Person", includeUnlisted: true).map(\.id) == [b.id])
        var edit = try store.person(a.id); edit.connections = []
        try store.savePerson(edit)
        #expect(PeopleIndex.results(store.people, query: "").map(\.id) == [a.id])
        edit = try store.person(a.id); edit.isListed = false
        try store.savePerson(edit)
        #expect(PeopleIndex.results(store.people, query: "").isEmpty)
        #expect(PeopleIndex.results(store.people, query: "", includeUnlisted: true).count == 2)
    }
    @Test("Link attributes update without replacing identities")
    func editLinks() throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        let a = adult(), b = Person(); try store.savePerson(a); try store.savePerson(b)
        var parent = ParentLink(parentID: a.id, childID: b.id); try store.saveParentLink(parent)
        parent.parentage = .biological; try store.saveParentLink(parent)
        var partner = PartnerLink(firstID: a.id, secondID: b.id); try store.savePartnerLink(partner)
        partner.status = .former; try store.savePartnerLink(partner)
        #expect(store.parentLinks == [parent] && store.partnerLinks == [partner] && store.people.count == 2)
    }
    @Test("A canceled value draft cannot alter persisted fields, links or photos")
    func cancelAndStaleDraft() throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        var a = adult(); a.photo = Data([5]); try store.savePerson(a)
        let original = try store.person(a.id)
        var canceled = original; canceled.firstName = nil; canceled.birthday = .unknown; canceled.photo = nil
        try store.reload(); #expect(try store.person(a.id) == original)
        var updated = original; updated.notes = "Updated"; try store.savePerson(updated)
        #expect(throws: KinError.staleEdit) { try store.savePerson(canceled, confirmPhotoRemoval: true) }
        #expect(try store.person(a.id).photo == original.photo)
    }
    @Test("Saving an editor for a deleted person never resurrects their identity")
    func deletedEditor() throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        let p = Person(); try store.savePerson(p)
        var edit = try store.person(p.id); edit.notes = "Draft"
        try store.deletePerson(p.id)
        #expect(throws: KinError.missingPerson) { try store.savePerson(edit) }
        #expect(store.people.isEmpty)
    }
    @Test("New person plus relationship rolls back together on save failure")
    func atomicCreate() throws {
        let failure = FailureSwitch()
        let store = try KinStore(inMemory: true, saveContext: { if failure.enabled { throw CocoaError(.fileWriteNoPermission) }; try $0.save() })
        defer { try? store.close() }
        let a = adult(); try store.savePerson(a); failure.enabled = true
        let child = Person()
        #expect(throws: (any Error).self) { try store.savePerson(child, relationship: .child(of: a.id, parentage: .step)) }
        #expect(store.people.count == 1 && store.parentLinks.isEmpty)
        failure.enabled = false
        try store.savePerson(child, relationship: .child(of: a.id, parentage: .step))
        #expect(store.people.count == 2 && store.parentLinks.count == 1)
        #expect(try store.person(child.id).reference == 2)
    }
}
@Suite("Civil ages and photo rules") struct PersonAgeTests {
    @Test("Exact adult boundary is a civil day", arguments: [14,15,16])
    func exactBoundary(day: Int) throws {
        let rules = AgeRules(calendar: utc)
        let birthday = Birthday.exact(CivilDate(year: 2008, month: 10, day: day))
        #expect(rules.allowsPhoto(birthday, on: testNow) == (day <= 15))
        #expect(rules.age(for: birthday, on: testNow) == (day <= 15 ? 18 : 17))
    }
    @Test("Estimates keep the civil reference, advance on its anniversary and never invent a birthday")
    func estimates() throws {
        let rules = AgeRules(calendar: utc)
        let birthday = Birthday.estimated(age: 17, referenceDate: CivilDate(year: 2025, month: 10, day: 16))
        #expect(rules.age(for: birthday, on: testNow) == 17)
        #expect(rules.ageRange(for: birthday, on: testNow) == 17...18)
        #expect(!rules.allowsPhoto(birthday, on: testNow))
        let next = CivilDate(year: 2026, month: 10, day: 16).pickerDate
        #expect(rules.age(for: birthday, on: next) == 18)
        #expect(rules.allowsPhoto(birthday, on: next))
        #expect(rules.displayAge(for: birthday, on: testNow).hasPrefix("~"))
        #expect(try JSONDecoder().decode(Birthday.self, from: JSONEncoder().encode(birthday)) == birthday)
    }
    @Test("Unknown and invalid ages prohibit photos; adults and children share exact/estimated rules")
    func validation() throws {
        let rules = AgeRules(calendar: utc)
        #expect(!rules.allowsPhoto(.unknown, on: testNow))
        #expect(rules.age(for: .unknown, on: testNow) == nil)
        #expect(rules.displayAge(for: .unknown, on: testNow) == "Age unknown")
        for age in [0,5,17,18,45,120] {
            let birthday = Birthday.estimated(age: age, referenceDate: testDay)
            try rules.validate(birthday, on: testNow)
            #expect(rules.age(for: birthday, on: testNow) == age)
            #expect(rules.allowsPhoto(birthday, on: testNow) == (age >= 18))
        }
        for age in [-1,121] { #expect(throws: KinError.invalidBirthday) { try rules.validate(.estimated(age: age, referenceDate: testDay), on: testNow) } }
        #expect(throws: KinError.invalidBirthday) { try rules.validate(.exact(CivilDate(year: 2027, month: 1, day: 1)), on: testNow) }
        #expect(throws: KinError.invalidBirthday) { try rules.validate(.estimated(age: 18, referenceDate: CivilDate(year: 2027, month: 1, day: 1)), on: testNow) }
        #expect(!CivilDate(year: 2025, month: 2, day: 29).isValid)
    }
    @Test("Gregorian dates survive timezone and calendar preference changes")
    func civilDates() throws {
        let birthday = Birthday.exact(CivilDate(year: 2008, month: 10, day: 15))
        var buddhist = Calendar(identifier: .buddhist); buddhist.timeZone = utc.timeZone
        #expect(AgeRules(calendar: buddhist).age(for: birthday, on: testNow) == 18)
        let decoded = try JSONDecoder().decode(Birthday.self, from: JSONEncoder().encode(birthday))
        #expect(decoded == birthday)
        #expect(AgeRules(calendar: utc).grade(for: .exact(CivilDate(year: 2016, month: 8, day: 31)), on: testNow) == "5th Grade")
        #expect(AgeRules(calendar: utc).grade(for: .estimated(age: 10, referenceDate: testDay), on: testNow)?.hasPrefix("~") == true)
        #expect(AgeRules(calendar: utc).grade(for: birthday, on: testNow) == nil)
    }
    @Test("Leap day estimates conservatively exclude minors")
    func leapDay() throws {
        let rules = AgeRules(calendar: utc)
        let estimate = Birthday.estimated(age: 17, referenceDate: CivilDate(year: 2024, month: 2, day: 29))
        #expect(!rules.allowsPhoto(estimate, on: CivilDate(year: 2025, month: 2, day: 28).pickerDate))
        #expect(rules.allowsPhoto(estimate, on: CivilDate(year: 2025, month: 3, day: 1).pickerDate))
    }
}
@Suite("Photo mutation policy") @MainActor struct PersonPhotoTests {
    @Test("Storage rejects photos for every ineligible age", arguments: [Birthday.unknown, .exact(CivilDate(year: 2010, month: 1, day: 1)), .estimated(age: 17, referenceDate: testDay)])
    func reject(birthday: Birthday) throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        let p = Person(birthday: birthday, photo: Data([9]))
        #expect(throws: KinError.photoNotAllowed) { try store.savePerson(p, today: testNow, calendar: utc) }
        #expect(store.people.isEmpty)
    }
    @Test("Age correction must explicitly confirm photo removal; canceled correction preserves it", arguments: [Birthday.unknown, .exact(CivilDate(year: 2015, month: 5, day: 2)), .estimated(age: 17, referenceDate: testDay)])
    func removal(birthday: Birthday) throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        var p = adult(); p.photo = Data([1, 2]); try store.savePerson(p, today: testNow)
        let original = try store.person(p.id)
        var edit = original; edit.birthday = birthday
        #expect(edit.visiblePhoto(on: testNow) == nil)
        #expect(throws: KinError.photoRemovalRequired) { try store.savePerson(edit, today: testNow) }
        #expect(try store.person(p.id) == original)
        // Even removing the draft photo cannot bypass the warning.
        edit.photo = nil
        #expect(throws: KinError.photoRemovalRequired) { try store.savePerson(edit, today: testNow) }
        try store.savePerson(edit, today: testNow, confirmPhotoRemoval: true)
        #expect(try store.person(p.id).photo == nil)
        #expect(try store.person(p.id).birthday == birthday)
    }
}
