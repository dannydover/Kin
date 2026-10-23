import Foundation

/// A one-time convenience for a fresh draft, never an inference about parentage.
enum PersonDraftDefaults {
    static func newPerson(relationship: NewRelationship?, people: [Person]) -> Person {
        var person = Person()
        person.isListed = relationship == nil
        if case .child(let sourceID, _) = relationship,
           let source = people.first(where: { $0.id == sourceID }),
           let surname = source.lastName?.trimmingCharacters(in: .whitespacesAndNewlines), !surname.isEmpty {
            person.lastName = surname
        }
        return person
    }
}
