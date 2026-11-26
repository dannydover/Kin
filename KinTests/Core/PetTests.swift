import CoreData
import Foundation
import Testing
@testable import Kin

@MainActor private final class PetSaveFailure {
    var fail = false
}

@Suite("Profile pet records") @MainActor struct PetTests {
    @Test("Petless 2.1 payloads open without a model migration")
    func legacyPayload() throws {
        let data = Data("""
        {
          "id": "\(UUID().uuidString)",
          "firstName": "Synthetic",
          "gender": "unknown",
          "birthday": { "unknown": {} },
          "notes": "",
          "connections": ["family"],
          "revision": 1,
          "reference": 1,
          "unnamedRole": "Person"
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(Person.self, from: data)
        #expect(decoded.pets.isEmpty)
        #expect(decoded.isListed)
        #expect(decoded.hasValidPets)
        let encoded = try JSONEncoder().encode(decoded)
        let fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(fields["savedPets"] == nil)
    }

    @Test("Multiple profile pets persist and keep explicit species, age and association")
    func persistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("pets.sqlite")
        let owner = Person(firstName: "Synthetic Owner", birthday: .exact(CivilDate(year: 1980, month: 10, day: 8)), photo: Data([1, 2, 3]))
        let friend = Person(firstName: "Other Synthetic")
        let store = try KinStore(storeURL: url)
        defer { try? store.close() }
        try store.savePerson(owner)
        try store.savePerson(friend)
        let link = ParentLink(parentID: owner.id, childID: friend.id)
        try store.saveParentLink(link)
        let dog = Pet(name: "Biscuit", species: .dog, age: .estimated(.puppy))
        let cat = Pet(name: "Cloud", species: .cat, age: .exact(CivilDate(year: 2024, month: 2, day: 29)))
        let other = Pet(name: "  Echo  ", species: .other("  Parrot  "))
        try store.savePet(dog, on: owner.id)
        try store.savePet(cat, on: owner.id)
        try store.savePet(other, on: friend.id)
        try store.savePet(cat, on: owner.id) // explicit repeated save
        try store.close()

        let reopened = try KinStore(storeURL: url)
        defer { try? reopened.close() }
        let profile = try reopened.person(owner.id)
        #expect(profile.pets == [dog, cat])
        #expect(profile.photo == owner.photo)
        #expect(reopened.parentLinks == [link])
        #expect(try reopened.person(friend.id).pets == [other.validated()])
        var changed = dog
        changed.age = .estimated(.middleAged)
        try reopened.savePet(changed, on: owner.id, replacing: dog)
        try reopened.savePet(changed, on: owner.id, replacing: dog) // explicit repeated update
        try reopened.removePet(cat, from: owner.id)
        try reopened.removePet(cat, from: owner.id)
        var editedProfile = try reopened.person(owner.id)
        editedProfile.notes = "Synthetic notes"
        try reopened.savePerson(editedProfile)
        #expect(try reopened.person(owner.id).pets == [changed])
        try reopened.close()

        let final = try KinStore(storeURL: url)
        defer { try? final.close() }
        #expect(try final.person(owner.id).pets == [changed])
        try final.deletePerson(owner.id)
        #expect(try final.person(friend.id).pets == [other.validated()])
        #expect(final.parentLinks.isEmpty)
        try final.deleteAllPeople()
        #expect(final.people.isEmpty)
    }

    @Test("Without a confirmed valid save the last persisted pet stays intact")
    func validationAndStaleEdits() throws {
        let store = try KinStore(inMemory: true)
        defer { try? store.close() }
        let profile = Person(firstName: "Synthetic Owner")
        try store.savePerson(profile)
        let dog = Pet(name: "Biscuit", species: .dog, age: .estimated(.puppy))
        try store.savePet(dog, on: profile.id)
        let now = CivilDate(year: 2025, month: 12, day: 31).pickerDate
        var edit = dog
        edit.age = .exact(CivilDate(year: 2026, month: 1, day: 1))
        #expect(throws: PetError.invalidBirthday) {
            try store.savePet(edit, on: profile.id, replacing: dog, today: now, timeZone: CivilDate.pickerCalendar.timeZone)
        }
        edit.age = .estimated(.kitten)
        #expect(throws: PetError.invalidEstimate) { try store.savePet(edit, on: profile.id, replacing: dog) }
        edit.species = .other("Parrot")
        #expect(throws: PetError.invalidEstimate) { try store.savePet(edit, on: profile.id, replacing: dog) }
        edit.age = .unknown
        edit.species = .other("  ")
        #expect(throws: PetError.invalidSpecies) { try store.savePet(edit, on: profile.id, replacing: dog) }
        edit.species = .cat
        edit.name = " "
        #expect(throws: PetError.invalidName) { try store.savePet(edit, on: profile.id, replacing: dog) }
        #expect(try store.person(profile.id).pets == [dog])

        edit.name = "Biscuit"
        edit.age = .estimated(.kitten)
        let concurrentPet = Pet(name: "Cloud", species: .cat)
        try store.savePet(concurrentPet, on: profile.id)
        try store.savePet(edit, on: profile.id, replacing: dog)
        #expect(throws: PetError.staleEdit) { try store.removePet(dog, from: profile.id) }
        #expect(throws: PetError.staleEdit) { try store.savePet(dog, on: profile.id, replacing: dog) }
        #expect(try store.person(profile.id).pets == [edit, concurrentPet])
    }

    @Test("A failed pet write does not update the profile or lose its existing records")
    func rollback() throws {
        let failure = PetSaveFailure()
        let store = try KinStore(inMemory: true, saveContext: {
            if failure.fail { throw CocoaError(.fileWriteNoPermission) }
            try $0.save()
        })
        defer { try? store.close() }
        let profile = Person()
        try store.savePerson(profile)
        let original = Pet(name: "Biscuit", species: .dog)
        try store.savePet(original, on: profile.id)
        let snapshot = try store.person(profile.id)
        failure.fail = true
        #expect(throws: CocoaError.self) { try store.removePet(original, from: profile.id) }
        try store.reload()
        #expect(try store.person(profile.id) == snapshot)
    }

    @Test("Estimated age options are specific to dogs and cats")
    func stages() {
        #expect(PetSpecies.dog.estimatedStages == [.puppy, .middleAged, .elderly])
        #expect(PetSpecies.cat.estimatedStages == [.kitten, .middleAged, .elderly])
        #expect(PetSpecies.other("Parrot").estimatedStages.isEmpty)
    }
}
