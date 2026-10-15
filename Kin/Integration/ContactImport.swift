import Foundation

/// Age eligibility is checked before decoding any Contacts photo. Imports never
/// supply an implied adult age or overwrite identity, links, notes or connections.
enum ContactImport {
    static func apply(_ snapshot: ContactSnapshot, to person: inout Person, today: Date = Date(), calendar: Calendar = .current) {
        person.firstName = snapshot.firstName.isEmpty ? nil : snapshot.firstName
        person.lastName = snapshot.lastName.isEmpty ? nil : snapshot.lastName
        if AgeRules(calendar: calendar).allowsPhoto(person.birthday, on: today) {
            person.photo = snapshot.photo.flatMap { PhotoProcessor.thumbnail($0) }
        }
    }
}
