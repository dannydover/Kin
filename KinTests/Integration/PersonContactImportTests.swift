import Foundation
import UIKit
import Contacts
import ContactsUI
import Testing
@testable import Kin

/// Models a system picker payload with only some of the contact keys fetched.
private final class PartialContact: CNContact {
    let keys: Set<String>
    let savedBirthday: DateComponents?
    let thumbnail: Data?
    let fullImage: Data?
    var photoReads = 0
    init(keys: Set<String>, birthday: DateComponents? = nil, thumbnail: Data? = nil, fullImage: Data? = nil) {
        self.keys = keys; savedBirthday = birthday; self.thumbnail = thumbnail; self.fullImage = fullImage
        super.init()
    }
    required init?(coder: NSCoder) { fatalError("Not a serialized test fixture") }
    override func isKeyAvailable(_ key: String) -> Bool { keys.contains(key) }
    override var birthday: DateComponents? { savedBirthday }
    override var nonGregorianBirthday: DateComponents? { nil }
    override var thumbnailImageData: Data? { photoReads += 1; return thumbnail }
    override var imageData: Data? { photoReads += 1; return fullImage }
}

@Suite("Person Contacts photo gate") @MainActor struct PersonContactImportTests {
    @Test("Unavailable birthday fields are distinguished from a genuinely empty birthday")
    func unavailableBirthday() {
        let payloads: [Set<String>] = [[], [CNContactBirthdayKey], [CNContactNonGregorianBirthdayKey]]
        for keys in payloads {
            let contact = PartialContact(keys: keys)
            #expect(ContactSnapshot(contact: contact).birthInformation == .unavailable)
            #expect(contact.photoReads == 0)
        }
        let empty = PartialContact(keys: [CNContactBirthdayKey, CNContactNonGregorianBirthdayKey])
        #expect(ContactSnapshot(contact: empty).birthInformation == .missing)
    }

    @Test("Partial picker images import only after adulthood, without requiring an availability flag", arguments: [true, false])
    func partialPhoto(thumbnail: Bool) {
        for year in [1980, 2020] {
            let imageKey = thumbnail ? CNContactThumbnailImageDataKey : CNContactImageDataKey
            let data = image()
            let contact = PartialContact(keys: [CNContactBirthdayKey, imageKey],
                birthday: DateComponents(year: year, month: 1, day: 1),
                thumbnail: thumbnail ? data : nil, fullImage: thumbnail ? nil : data)
            let snapshot = ContactSnapshot(contact: contact)
            #expect(snapshot.birthInformation == .exact(CivilDate(year: year, month: 1, day: 1)))
            #expect(contact.photoReads == 0)
            var person = Person()
            ContactImport.apply(snapshot, to: &person, today: CivilDate(year: 2026, month: 10, day: 15).pickerDate)
            #expect(contact.photoReads == (year == 1980 ? 1 : 0))
            #expect((person.photo != nil) == (year == 1980))
        }
    }

    @Test("Unnamed unsaved draft contexts never expose a temporary notebook reference", arguments: ["Person","Parent","Child","Partner"])
    func unnamedDraftReview(role: String) {
        var draft = Person(); draft.unnamedRole = role
        let original = draft
        #expect(ContactImport.reviewName(for: draft) == nil)
        #expect(draft == original && draft.reference == 0 && draft.revision == 0)
        #expect(draft.firstName == nil && draft.lastName == nil)
    }
    @Test("Named and surname-only unsaved drafts review the entered name without a synthetic identity")
    func namedDraftReview() {
        let named = Person(firstName: "  Synthetic ",lastName: " Draft ")
        let surnameOnly = Person(firstName: " \n",lastName: " Fictional Surname ")
        #expect(ContactImport.reviewName(for: named) == "Synthetic Draft")
        #expect(ContactImport.reviewName(for: surnameOnly) == "Fictional Surname")
        #expect(ContactImport.reviewName(for: Person(firstName: " ",lastName: "\n")) == nil)
        #expect(named.reference == 0 && surnameOnly.reference == 0)
    }
    @Test("Saved unnamed parent review preserves its stable label without changing stored names")
    func savedUnnamedReview() throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        let child = Person(), parent = Person(); try store.savePerson(child)
        try store.savePerson(parent,relationship: .parent(of: child.id,parentage: .unspecified))
        let saved = try store.person(parent.id)
        #expect(ContactImport.reviewName(for: saved) == "Parent 2")
        #expect(saved.firstName == nil && saved.lastName == nil && store.people.count == 2)
    }
    private func image() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).jpegData(withCompressionQuality: 1) { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
    @Test("Contacts imports names but no photo at unknown or minor ages", arguments: [Birthday.unknown, .exact(CivilDate(year: 2020, month: 1, day: 1)), .estimated(age: 17, referenceDate: CivilDate(year: 2026, month: 10, day: 15))])
    func blocked(birthday: Birthday) {
        var value = Person(birthday: birthday)
        ContactImport.apply(ContactSnapshot(firstName: "Synthetic", lastName: "", loadPhoto: { image() }), to: &value, today: CivilDate(year: 2026, month: 10, day: 15).pickerDate)
        #expect(value.firstName == "Synthetic" && value.lastName == nil && value.photo == nil)
    }
    @Test("Eligible adult import strips/bounds the photo and preserves identity and other fields")
    func adult() throws {
        var value = Person(gender: .other, birthday: .exact(CivilDate(year: 1980, month: 1, day: 1)), connections: [.colleague])
        value.notes = "Fictional"; let original = value
        ContactImport.apply(ContactSnapshot(firstName: "Synthetic", lastName: "Person", birthInformation: .exact(CivilDate(year: 1980,month: 1,day: 1)), loadPhoto: { image() }), to: &value)
        #expect(value.photo != nil && UIImage(data: value.photo!) != nil)
        #expect(value.id == original.id && value.gender == .other && value.notes == original.notes && value.connections == original.connections && value.birthday == original.birthday)
    }
    @Test("Selection imports complete birthday metadata without fetching a photo")
    func pickerGate() {
        let contact = CNMutableContact(); contact.givenName = "Synthetic"; contact.imageData = image()
        contact.birthday = DateComponents(year: 1980, month: 1, day: 1)
        var selected: ContactSnapshot?
        let picker = ContactPicker(onSelect: { selected = $0 }, onCancel: {})
        let coordinator = picker.makeCoordinator()
        coordinator.contactPicker(CNContactPickerViewController(), didSelect: contact); coordinator.pickerDidDismiss()
        #expect(selected?.birthInformation == .exact(CivilDate(year: 1980,month: 1,day: 1)))
        #expect(selected?.firstName == "Synthetic")
    }
    @Test("Ineligible Contacts photo never persists through relaunch", arguments: [Birthday.unknown,.exact(CivilDate(year: 2020,month: 1,day: 1)),.estimated(age: 17,referenceDate: CivilDate(year: 2026,month: 10,day: 15))])
    func blockedPersistence(birthday: Birthday) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite"), today = CivilDate(year: 2026,month: 10,day: 15).pickerDate
        let store = try KinStore(storeURL: url)
        var draft = Person(birthday: birthday)
        ContactImport.apply(ContactSnapshot(firstName: "Synthetic",lastName: "Import",loadPhoto: { image() }),to: &draft,today: today)
        try store.savePerson(draft,today: today); try store.close()
        let reopened = try KinStore(storeURL: url); defer { try? reopened.close() }
        #expect(try reopened.person(draft.id).photo == nil)
        #expect(PeopleIndex.results(reopened.people,query: "Synthetic",includeUnlisted: true).count == 1)
    }
    @Test("Contacts draft cancellation and explicit import preserve shared child links and persist one identity")
    func sharedGraphImport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite"), store = try KinStore(storeURL: url)
        let a = Person(), b = Person(), child = Person(firstName: "Before import",birthday: .exact(CivilDate(year: 1980,month: 1,day: 1)),connections: [.family])
        for p in [a,b,child] { try store.savePerson(p) }
        try store.saveParentLink(ParentLink(parentID: a.id,childID: child.id,parentage: .adoptive))
        try store.saveParentLink(ParentLink(parentID: b.id,childID: child.id,parentage: .step))
        let original = try store.person(child.id), links = store.parentLinks
        var canceled = original
        ContactImport.apply(ContactSnapshot(firstName: "Canceled import",lastName: "",birthInformation: .exact(CivilDate(year: 1980,month: 1,day: 1)),loadPhoto: { image() }),to: &canceled)
        try store.reload()
        #expect(try store.person(child.id) == original && store.parentLinks == links)
        var imported = original
        ContactImport.apply(ContactSnapshot(firstName: "Synthetic imported adult",lastName: "",birthInformation: .exact(CivilDate(year: 1980,month: 1,day: 1)),loadPhoto: { image() }),to: &imported)
        try store.savePerson(imported); let expected = try store.person(child.id); try store.close()
        let reopened = try KinStore(storeURL: url); defer { try? reopened.close() }
        #expect(try reopened.person(child.id) == expected)
        #expect(expected.photo != nil && expected.connections == original.connections)
        #expect(Set(reopened.parentLinks.map(\.id)) == Set(links.map(\.id)))
        #expect(try reopened.entityCount("PersonRecord") == 3)
    }

    @Test("Contact birthday is applied before lazy photo access", arguments: [1980, 2020, 2008, 2009])
    func importedBirthday(year: Int) throws {
        let today = CivilDate(year: 2026,month: 10,day: 15).pickerDate
        var reads = 0
        let day = CivilDate(year: year,month: 10,day: 15)
        let snapshot = ContactSnapshot(firstName: "Imported",lastName: "Adult",birthInformation: .exact(day),loadPhoto: { reads += 1; return image() })
        var person = Person()
        #expect(reads == 0)
        ContactImport.apply(snapshot,to: &person,today: today,calendar: CivilDate.pickerCalendar)
        #expect(person.birthday == .exact(day))
        #expect(reads == (year <= 2008 ? 1 : 0))
        #expect((person.photo != nil) == (year <= 2008))
        #expect((person.visiblePhoto(on: today) != nil) == (year <= 2008))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite"), store = try KinStore(storeURL: url)
        try store.savePerson(person,today: today); let saved = try store.person(person.id); try store.close()
        let reopened = try KinStore(storeURL: url); defer { try? reopened.close() }
        #expect(try reopened.person(person.id) == saved)
        #expect(saved.birthday == .exact(day) && (saved.photo != nil) == (year <= 2008))
    }
    @Test("A different unresolved contact cannot inherit the prefilled draft age or photo", arguments: [ContactBirthInformation.missing,.unavailable,.yearless,.invalid,.ambiguousCalendar])
    func unresolved(reason: ContactBirthInformation) {
        var reads = 0
        let snapshot = ContactSnapshot(firstName: "Imported",lastName: "Name",birthInformation: reason,loadPhoto: { reads += 1; return image() })
        let original = Person(firstName: "Before",birthday: .exact(CivilDate(year: 1980,month: 1,day: 1)))
        var value = original; value.photo = image(); let before = value
        // Cancel does not apply the staged card at all.
        #expect(value == before && reads == 0)
        ContactImport.apply(snapshot,to: &value,importPhoto: false)
        #expect(value.firstName == "Imported" && value.birthday == .unknown && value.photo == nil && reads == 0)
        #expect(value.id == original.id)
        var automatic = before
        ContactImport.apply(snapshot,to: &automatic)
        #expect(automatic.birthday == .unknown && automatic.photo == nil && reads == 0)
    }
    @Test("Prompt exact/estimated/unknown age choices gate reads conservatively", arguments: [Birthday.unknown,.estimated(age: 18,referenceDate: CivilDate(year: 2026,month: 10,day: 15)),.estimated(age: 19,referenceDate: CivilDate(year: 2026,month: 10,day: 15)),.exact(CivilDate(year: 2008,month: 10,day: 16)),.exact(CivilDate(year: 2008,month: 10,day: 15))])
    func promptChoices(birthday: Birthday) {
        let today = CivilDate(year: 2026,month: 10,day: 15).pickerDate
        var reads = 0; var value = Person()
        let snapshot = ContactSnapshot(firstName: "Imported",lastName: "",loadPhoto: { reads += 1; return image() })
        ContactImport.apply(snapshot,to: &value,birthday: birthday,today: today,calendar: CivilDate.pickerCalendar)
        let allowed = AgeRules(calendar: CivilDate.pickerCalendar).allowsPhoto(birthday,on: today)
        #expect(reads == (allowed ? 1 : 0)); #expect(value.birthday == birthday)
        #expect((value.photo != nil) == allowed)
    }
    @Test("A card with no photo clears the prior draft image on confirmed replacement") func absentPhoto() {
        var value = Person(birthday: .exact(CivilDate(year: 1980,month: 1,day: 1))); value.photo = image(); let before = value.photo
        ContactImport.apply(ContactSnapshot(firstName: "Imported",lastName: ""),to: &value)
        #expect(before != nil && value.photo == nil && value.birthday == .unknown)
    }

    @Test("Imported adulthood follows the user's civil day at the eighteen boundary", arguments: [-43200,50400])
    func timezoneBoundary(seconds: Int) {
        let instant = CivilDate(year: 2026,month: 10,day: 14).pickerDate
        let zone = TimeZone(secondsFromGMT: seconds)!, calendar = CivilDate.gregorian(in: zone)
        let contact = CNMutableContact(); contact.givenName = "Synthetic"
        contact.birthday = DateComponents(year: 2008,month: 10,day: 15)
        let captured = ContactSnapshot(contact: contact,today: instant,timeZone: zone)
        var reads = 0; let snapshot = ContactSnapshot(firstName: captured.firstName,lastName: captured.lastName,birthInformation: captured.birthInformation,loadPhoto: { reads += 1; return image() })
        var person = Person(); ContactImport.apply(snapshot,to: &person,today: instant,calendar: calendar)
        #expect(person.birthday == .exact(CivilDate(year: 2008,month: 10,day: 15)))
        #expect(reads == (seconds > 0 ? 1 : 0))
    }
    @Test("Imported minor correction requires removal confirmation and cancellation preserves saved adult photo")
    func minorCorrection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite"), today = CivilDate(year: 2026,month: 10,day: 15).pickerDate
        let store = try KinStore(storeURL: url)
        var original = Person(firstName: "Saved",birthday: .exact(CivilDate(year: 1980,month: 1,day: 1))); original.photo = image()
        try store.savePerson(original,today: today); let saved = try store.person(original.id)
        var reads = 0, draft = saved
        ContactImport.apply(ContactSnapshot(firstName: "Imported",lastName: "",birthInformation: .exact(CivilDate(year: 2020,month: 1,day: 1)),loadPhoto: { reads += 1; return image() }),to: &draft,today: today)
        #expect(reads == 0 && draft.visiblePhoto(on: today) == nil)
        #expect(throws: (any Error).self) { try store.savePerson(draft,today: today) }
        #expect(try store.person(original.id) == saved)
        try store.close(); let reopened = try KinStore(storeURL: url); defer { try? reopened.close() }
        #expect(try reopened.person(original.id) == saved)
        draft.photo = nil; try reopened.savePerson(draft,today: today,confirmPhotoRemoval: true)
        #expect(try reopened.person(original.id).photo == nil)
    }

}
