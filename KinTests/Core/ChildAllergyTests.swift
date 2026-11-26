import Foundation
import Testing
@testable import Kin

@Suite("Child allergy notes") @MainActor struct ChildAllergyTests {
    @Test("Older payloads leave allergies unset, and text in Notes is not inferred")
    func legacyPayloadWithoutAllergyInformation() throws {
        var value = Person(firstName: "Synthetic Preview")
        value.notes = "Synthetic mention of peanuts in an unrelated note"
        let encoded = try JSONEncoder().encode(value)
        let fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(fields["allergies"] == nil)
        let decoded = try JSONDecoder().decode(Person.self, from: encoded)
        #expect(decoded == value)
        #expect(decoded.recordedAllergies == nil)
    }

    @Test("Child context or known minor age offers the field; existing entries remain editable")
    func editorAvailability() {
        let today = Date()
        let person = Person()
        let recent = CivilDate(today.addingTimeInterval(-86_400), timeZone: .current)
        let old = CivilDate(year: 1980, month: 2, day: 3)
        #expect(person.showsAllergyEditor(isChildInNotebook: true, birthday: .unknown, on: today))
        #expect(person.showsAllergyEditor(isChildInNotebook: false, birthday: .exact(recent), on: today))
        #expect(!person.showsAllergyEditor(isChildInNotebook: false, birthday: .unknown, on: today))
        #expect(!person.showsAllergyEditor(isChildInNotebook: false, birthday: .exact(old), on: today))
        var edited = person
        edited.allergies = "Synthetic value"
        #expect(edited.showsAllergyEditor(isChildInNotebook: false, birthday: .exact(old), on: today))
    }

    @Test("Local save and reopen keep distinct child records; edits and whitespace removal stay scoped")
    func childAllergiesPersistIndependently() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("people.sqlite")
        let parent = Person(firstName: "Synthetic Parent")
        var child = Person(firstName: "Synthetic A")
        var sibling = Person(firstName: "Synthetic B")
        let missing = Person(firstName: "Synthetic C")
        let longValue = "Peanuts, sesame, soy\n" + String(repeating: "Synthetic detail. ", count: 22) + "End."
        child.allergies = "\n  " + longValue + "\t"
        sibling.allergies = "Shellfish"

        let storage = try KinStore(storeURL: url)
        defer { try? storage.close() }
        try storage.savePerson(parent)
        for person in [child, sibling, missing] {
            try storage.savePerson(person, relationship: .child(of: parent.id, parentage: .unspecified))
        }
        try storage.close()

        let reopened = try KinStore(storeURL: url)
        defer { try? reopened.close() }
        #expect(try reopened.person(child.id).recordedAllergies == longValue)
        #expect(try reopened.person(sibling.id).recordedAllergies == "Shellfish")
        #expect(try reopened.person(missing.id).recordedAllergies == nil)
        #expect(Set(reopened.parentLinks.filter { $0.parentID == parent.id }.map(\.childID)) == [child.id, sibling.id, missing.id])
        var edit = try reopened.person(child.id)
        edit.allergies = "Sesame"
        try reopened.savePerson(edit)
        #expect(try reopened.person(child.id).recordedAllergies == "Sesame")
        edit = try reopened.person(child.id)
        edit.allergies = " \n  "
        try reopened.savePerson(edit)
        try reopened.close()

        let final = try KinStore(storeURL: url)
        defer { try? final.close() }
        #expect(try final.person(child.id).allergies == nil)
        #expect(try final.person(sibling.id).recordedAllergies == "Shellfish")
        #expect(try final.person(missing.id).recordedAllergies == nil)
        #expect(final.parentLinks.count == 3)
    }
}
