import Foundation
import CoreData
import UIKit
import Testing
@testable import Kin

@Suite("Existing contact birth preservation") @MainActor
struct ExistingContactBirthPreservationTests {
    private let today = CivilDate(year: 2026, month: 10, day: 23).pickerDate
    private var known: [Birthday] { [.exact(CivilDate(year: 1980,month: 3,day: 14)), .estimated(age: 40,referenceDate: CivilDate(year: 2026,month: 10,day: 15)), .unknown] }
    private func saved(_ birthday: Birthday, in store: KinStore) throws -> Person {
        var person = Person(firstName: "Synthetic Saved",lastName: "Example",gender: .other,birthday: birthday,connections: [.family])
        person.notes = "Synthetic note"; person.isListed = false
        try store.savePerson(person,today: today)
        return try store.person(person.id)
    }
    @Test("Unusable source birthdays keep existing exact, estimated or unknown information without authorizing photos",
          arguments: [ContactBirthInformation.missing,.unavailable,.yearless,.invalid,.ambiguousCalendar])
    func unusable(_ reason: ContactBirthInformation) throws {
        for birthday in known {
            let store = try KinStore(inMemory: true)
            let before = try saved(birthday,in: store); var value = before; var reads = 0
            let snapshot = ContactSnapshot(firstName: "Synthetic Imported",lastName: "Contact",birthInformation: reason,loadPhoto: { reads += 1; return nil })
            ContactImport.apply(snapshot,to: &value,today: today)
            #expect(value.birthday == before.birthday)
            #expect(reads == 0 && value.photo == nil)
            #expect(value.id == before.id && value.reference == before.reference && value.revision == before.revision)
            #expect(value.notes == before.notes && value.gender == before.gender && value.connections == before.connections && value.indexInclusion == before.indexInclusion)
            #expect(try store.person(before.id) == before, "Import review is not a save")
        }
    }
    @Test("Current unsaved age edits are preserved; deliberate replacements and Unknown take priority")
    func explicitChanges() throws {
        let store = try KinStore(inMemory: true)
        let original = try saved(known[0],in: store)
        let missing = ContactSnapshot(firstName: "Synthetic Import",lastName: "")
        var edited = original; edited.birthday = known[1]; edited.notes = "Synthetic unsaved note"
        ContactImport.apply(missing,to: &edited,importPhoto: false,today: today)
        #expect(edited.birthday == known[1] && edited.notes == "Synthetic unsaved note")
        ContactImport.apply(missing,to: &edited,birthday: .unknown,importPhoto: false,today: today)
        #expect(edited.birthday == .unknown)
        let replacement = CivilDate(year: 1990,month: 2,day: 3)
        ContactImport.apply(ContactSnapshot(firstName: "Synthetic Valid",lastName: "",birthInformation: .exact(replacement)),to: &edited,importPhoto: false,today: today)
        #expect(edited.birthday == .exact(replacement) && edited.id == original.id)
        ContactImport.apply(missing,to: &edited,birthday: known[1],importPhoto: false,today: today)
        #expect(edited.birthday == known[1])
        #expect(try store.person(original.id) == original, "Canceling the edited value changes no saved record")
    }
    @Test("New drafts never borrow an unrelated age or authorize a photo")
    func newDraft() {
        var draft = Person(birthday: known[0]); var reads = 0
        ContactImport.apply(ContactSnapshot(firstName: "Synthetic New",lastName: "",loadPhoto: { reads += 1; return nil }),to: &draft,today: today)
        #expect(draft.birthday == .unknown && reads == 0)
    }
    @Test("Review defaults preserve current edits and require photo confirmation only for an existing unusable source")
    func reviewDefaults() {
        for reason in [ContactBirthInformation.missing,.unavailable,.yearless,.invalid,.ambiguousCalendar] {
            for birthday in known {
                #expect(ContactImport.initialBirthday(for: reason,currentBirthday: birthday,isNew: false) == birthday)
                #expect(ContactImport.initialBirthday(for: reason,currentBirthday: birthday,isNew: true) == .unknown)
                #expect(ContactImport.needsPhotoConfirmation(for: reason,isNew: false))
                #expect(!ContactImport.needsPhotoConfirmation(for: reason,isNew: true))
            }
        }
        let valid = CivilDate(year: 1990,month: 2,day: 3)
        #expect(ContactImport.initialBirthday(for: .exact(valid),currentBirthday: known[0],isNew: false) == .exact(valid))
        #expect(!ContactImport.needsPhotoConfirmation(for: .exact(valid),isNew: false))
    }
    @Test("Retained age alone never reads a photo; deliberate reviewed age and opt-in still obey eligibility")
    func photoEvidence() throws {
        let store = try KinStore(inMemory: true); let original = try saved(known[0],in: store)
        let data = UIGraphicsImageRenderer(size: CGSize(width: 8,height: 8)).pngData { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0,y: 0,width: 8,height: 8))
        }
        var reads = 0
        let snapshot = ContactSnapshot(firstName: "Synthetic Photo",lastName: "",birthInformation: .yearless,loadPhoto: { reads += 1; return data })
        var value = original
        ContactImport.apply(snapshot,to: &value,today: today)
        #expect(value.birthday == original.birthday && reads == 0 && value.photo == nil)
        ContactImport.apply(snapshot,to: &value,birthday: original.birthday,importPhoto: false,today: today)
        #expect(reads == 0 && value.photo == nil)
        ContactImport.apply(snapshot,to: &value,birthday: original.birthday,importPhoto: true,today: today)
        #expect(reads == 1 && value.photo != nil)
        for birthday in [Birthday.unknown,.exact(CivilDate(year: 2020,month: 1,day: 1)),.estimated(age: 17,referenceDate: CivilDate(year: 2026,month: 10,day: 23))] {
            ContactImport.apply(snapshot,to: &value,birthday: birthday,importPhoto: true,today: today)
            #expect(reads == 1 && value.photo == nil)
        }
    }
    @Test("Failure, explicit retry, relaunch and shared links preserve one existing identity and age", arguments: [false,true])
    func persistence(afterCommit: Bool) throws {
        for birthday in known {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let url = root.appendingPathComponent("synthetic.sqlite"); var failing = false
            let store = try KinStore(storeURL: url,saveContext: { context in
                if failing && !afterCommit { throw CocoaError(.fileWriteNoPermission) }
                try context.save()
                if failing && afterCommit { throw CocoaError(.fileWriteNoPermission) }
            }); defer { try? store.close() }
            let original = try saved(birthday,in: store)
            let other = Person(firstName: "Synthetic Relative"); try store.savePerson(other,today: today)
            try store.saveParentLink(ParentLink(parentID: other.id,childID: original.id,parentage: .adoptive))
            let links = store.parentLinks; var draft = original
            ContactImport.apply(ContactSnapshot(firstName: "Synthetic Renamed",lastName: "",birthInformation: .yearless),to: &draft,importPhoto: false,today: today)
            try store.reload(); #expect(try store.person(original.id) == original)
            failing = true
            #expect(throws: (any Error).self) { try store.savePerson(draft,today: today) }
            failing = false; try store.resume(); try store.savePerson(draft,today: today); try store.savePerson(draft,today: today)
            try store.close(); try store.resume()
            let saved = try store.person(original.id)
            #expect(saved.birthday == original.birthday && saved.notes == original.notes && saved.connections == original.connections && saved.gender == original.gender && saved.isListed == original.isListed)
            #expect(saved.firstName == "Synthetic Renamed" && saved.reference == original.reference)
            #expect(store.people.count == 2 && store.parentLinks == links)
        }
    }
    @Test("Existing imports retain every saved or explicitly edited gender", arguments: Gender.allCases)
    func genderPreservation(_ gender: Gender) throws {
        let store = try KinStore(inMemory: true)
        defer { try? store.close() }
        let original = try saved(known[0],in: store)
        for source in [ContactBirthInformation.missing,.exact(CivilDate(year: 1990,month: 2,day: 3))] {
            var draft = original; draft.gender = gender
            let snapshot = ContactSnapshot(firstName: "Michael",lastName: "Synthetic",birthInformation: source)
            ContactImport.apply(snapshot,to: &draft,importPhoto: false,today: today)
            #expect(draft.gender == gender && draft.id == original.id)
            #expect(try store.person(original.id) == original,"Canceling imported edits preserves the saved gender")
        }
    }

}
