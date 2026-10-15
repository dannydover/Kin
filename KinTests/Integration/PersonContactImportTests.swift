import Foundation
import UIKit
import Contacts
import ContactsUI
import Testing
@testable import Kin

@Suite("Person Contacts photo gate") @MainActor struct PersonContactImportTests {
    private func image() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).jpegData(withCompressionQuality: 1) { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
    @Test("Contacts imports names but no photo at unknown or minor ages", arguments: [Birthday.unknown, .exact(CivilDate(year: 2020, month: 1, day: 1)), .estimated(age: 17, referenceDate: CivilDate(year: 2026, month: 10, day: 15))])
    func blocked(birthday: Birthday) {
        var value = Person(birthday: birthday)
        ContactImport.apply(ContactSnapshot(firstName: "Synthetic", lastName: "", photo: image()), to: &value, today: CivilDate(year: 2026, month: 10, day: 15).pickerDate)
        #expect(value.firstName == "Synthetic" && value.lastName == nil && value.photo == nil)
    }
    @Test("Eligible adult import strips/bounds the photo and preserves identity and other fields")
    func adult() throws {
        var value = Person(gender: .other, birthday: .exact(CivilDate(year: 1980, month: 1, day: 1)), connections: [.colleague])
        value.notes = "Fictional"; let original = value
        ContactImport.apply(ContactSnapshot(firstName: "Synthetic", lastName: "Person", photo: image()), to: &value)
        #expect(value.photo != nil && UIImage(data: value.photo!) != nil)
        #expect(value.id == original.id && value.gender == .other && value.notes == original.notes && value.connections == original.connections && value.birthday == original.birthday)
    }
    @Test("System picker omits photo payload unless eligible caller explicitly enables it")
    func pickerGate() {
        let contact = CNMutableContact(); contact.givenName = "Synthetic"; contact.imageData = image()
        var blocked: ContactSnapshot?, allowed: ContactSnapshot?
        let noPhoto = ContactPicker(onSelect: { blocked = $0 }, onCancel: {})
        let eligible = ContactPicker(includePhoto: true, onSelect: { allowed = $0 }, onCancel: {})
        let one = noPhoto.makeCoordinator(), two = eligible.makeCoordinator()
        one.contactPicker(CNContactPickerViewController(), didSelect: contact); one.pickerDidDismiss()
        two.contactPicker(CNContactPickerViewController(), didSelect: contact); two.pickerDidDismiss()
        #expect(blocked?.photo == nil)
        #expect(allowed?.firstName == "Synthetic")
    }
    @Test("Ineligible Contacts photo never persists through relaunch", arguments: [Birthday.unknown,.exact(CivilDate(year: 2020,month: 1,day: 1)),.estimated(age: 17,referenceDate: CivilDate(year: 2026,month: 10,day: 15))])
    func blockedPersistence(birthday: Birthday) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite"), today = CivilDate(year: 2026,month: 10,day: 15).pickerDate
        let store = try KinStore(storeURL: url)
        var draft = Person(birthday: birthday)
        ContactImport.apply(ContactSnapshot(firstName: "Synthetic",lastName: "Import",photo: image()),to: &draft,today: today)
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
        ContactImport.apply(ContactSnapshot(firstName: "Canceled import",lastName: "",photo: image()),to: &canceled)
        try store.reload()
        #expect(try store.person(child.id) == original && store.parentLinks == links)
        var imported = original
        ContactImport.apply(ContactSnapshot(firstName: "Synthetic imported adult",lastName: "",photo: image()),to: &imported)
        try store.savePerson(imported); let expected = try store.person(child.id); try store.close()
        let reopened = try KinStore(storeURL: url); defer { try? reopened.close() }
        #expect(try reopened.person(child.id) == expected)
        #expect(expected.photo != nil && expected.connections == original.connections)
        #expect(Set(reopened.parentLinks.map(\.id)) == Set(links.map(\.id)))
        #expect(try reopened.entityCount("PersonRecord") == 3)
    }

}
