import Foundation

/// This is a value-draft operation, never a store write. Photo access and decoding
/// both follow the resolved birthday gate, including user-entered import dates.
@MainActor enum ContactImport {
    static func apply(_ snapshot: ContactSnapshot, to person: inout Person, birthday: Birthday? = nil, importPhoto: Bool = true, today: Date = Date(), calendar: Calendar = .current) {
        person.firstName = snapshot.firstName.isEmpty ? nil : snapshot.firstName
        person.lastName = snapshot.lastName.isEmpty ? nil : snapshot.lastName
        if let birthday { person.birthday = birthday }
        else if case .exact(let date) = snapshot.birthInformation { person.birthday = .exact(date) }
        else { person.birthday = .unknown }
        // A selected card never inherits another draft's age or image. The import
        // review explains this replacement; cancel never calls apply.
        person.photo = nil
        guard importPhoto, AgeRules(calendar: calendar).allowsPhoto(person.birthday, on: today) else { return }
        if let data = snapshot.photo(for: person.birthday, today: today, calendar: calendar), let photo = PhotoProcessor.thumbnail(data) { person.photo = photo }
    }
}
