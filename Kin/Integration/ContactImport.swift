import Foundation

/// This is a value-draft operation, never a store write. Photo access and decoding
/// both follow the resolved birthday gate, including user-entered import dates.
@MainActor enum ContactImport {
    /// Unsaved unnamed drafts have no notebook reference to show. Real names
    /// remain useful in review; saved unnamed entries retain their stable label.
    static func reviewName(for person: Person) -> String? {
        if person.reference > 0 { return person.displayName }
        let name = [person.firstName, person.lastName].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? nil : name
    }
    static func hasUsableBirthday(_ source: ContactBirthInformation) -> Bool {
        if case .exact = source { return true }
        return false
    }
    /// Existing editor values may include unsaved corrections; never restore an older saved value.
    static func initialBirthday(for source: ContactBirthInformation, currentBirthday: Birthday, isNew: Bool) -> Birthday {
        if case .exact(let date) = source { return .exact(date) }
        return isNew ? .unknown : currentBirthday
    }
    static func needsPhotoConfirmation(for source: ContactBirthInformation, isNew: Bool) -> Bool {
        !isNew && !hasUsableBirthday(source)
    }
    static func apply(_ snapshot: ContactSnapshot, to person: inout Person, birthday: Birthday? = nil, importPhoto: Bool = true, today: Date = Date(), calendar: Calendar = .current) {
        person.firstName = snapshot.firstName.isEmpty ? nil : snapshot.firstName
        person.lastName = snapshot.lastName.isEmpty ? nil : snapshot.lastName
        let existing = person.reference > 0 && person.revision > 0
        person.birthday = birthday ?? initialBirthday(for: snapshot.birthInformation, currentBirthday: person.birthday, isNew: !existing)
        // Keeping an existing age is not evidence about a newly selected contact.
        // Only source evidence or a deliberately reviewed age can authorize its photo.
        person.photo = nil
        guard importPhoto, birthday != nil || hasUsableBirthday(snapshot.birthInformation),
              AgeRules(calendar: calendar).allowsPhoto(person.birthday, on: today) else { return }
        if let data = snapshot.photo(for: person.birthday, today: today, calendar: calendar), let photo = PhotoProcessor.thumbnail(data) { person.photo = photo }
    }
}
