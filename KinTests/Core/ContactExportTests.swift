import Foundation
import Testing
@testable import Kin

@Suite("Apple Contacts export") @MainActor struct ContactExportTests {
    private let day = CivilDate(year: 2026, month: 11, day: 26)
    private let calendar = CivilDate.pickerCalendar

    @Test("Only exact dates are exported, and photos are separately selectable and age-gated")
    func fieldEligibility() {
        var person = Person(firstName: "Synthetic", lastName: "Example",
                            birthday: .exact(CivilDate(year: 2000, month: 2, day: 29)), photo: Data([1,2,3]))
        person.notes = "Not exported"
        let values = ContactExportValues(person: person, today: day.pickerDate, calendar: calendar)
        #expect(values.available == [.firstName, .lastName, .birthday, .photo])
        #expect(values.selected([.firstName, .birthday]) == .init(firstName: "Synthetic", birthday: CivilDate(year: 2000, month: 2, day: 29)))
        person.birthday = .estimated(age: 17, referenceDate: day)
        let estimated = ContactExportValues(person: person, today: day.pickerDate, calendar: calendar)
        #expect(estimated.birthday == nil && estimated.photo == nil)
        person.birthday = .estimated(age: 42, referenceDate: day)
        let mature = ContactExportValues(person: person, today: day.pickerDate, calendar: calendar)
        #expect(mature.birthday == nil && mature.photo == person.photo)
        person.birthday = .exact(CivilDate(year: 2027, month: 2, day: 28))
        #expect(ContactExportValues(person: person, today: day.pickerDate, calendar: calendar).available == [.firstName, .lastName])
        person.birthday = .unknown
        #expect(ContactExportValues(person: person, today: day.pickerDate, calendar: calendar).available == [.firstName, .lastName])
        #expect(ContactExportValues(person: Person(), today: day.pickerDate, calendar: calendar).available.isEmpty)
    }

    @Test("Interrupted create blocks retries across relaunch without changing person values")
    func durableLink() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notebook.sqlite")
        let store = try KinStore(storeURL: url)
        let id = UUID()
        var person = Person(id: id, firstName: "Synthetic", birthday: .exact(.init(year: 1980, month: 1, day: 1)), photo: Data([1,2,3]))
        person.notes = "Private note"
        try store.savePerson(person)
        let staleEditor = try store.person(id)
        try store.recordContactExport(.pendingCreation, for: id, replacing: nil)
        var expected = staleEditor
        expected.contactExportLink = .pendingCreation
        #expect(try store.person(id) == expected)
        try store.close()
        let reopened = try KinStore(storeURL: url)
        defer { try? reopened.close() }
        #expect(try reopened.person(id).contactExportLink == .pendingCreation)
        #expect(throws: KinError.staleEdit) { try reopened.recordContactExport(.pendingCreation, for: id, replacing: nil) }
        let link = ContactExportLink.linked(identifier: "test-id", container: "fixture-account")
        try reopened.recordContactExport(link, for: id, replacing: .pendingCreation)
        var editor = staleEditor
        editor.firstName = "Synthetic edit"
        try reopened.savePerson(editor)
        let saved = try reopened.person(id)
        #expect(saved.contactExportLink == link && saved.firstName == "Synthetic edit" && saved.notes == person.notes && saved.photo == person.photo)
        let other = Person(firstName: "Other synthetic")
        try reopened.savePerson(other)
        #expect(throws: ContactExportError.alreadyLinked) { try reopened.recordContactExport(link, for: other.id, replacing: nil) }
    }
}
