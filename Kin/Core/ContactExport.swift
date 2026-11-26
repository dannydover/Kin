import Foundation

/// Only a Contacts identifier and its container are retained, never the
/// destination's contact fields. A pending create is deliberately not retried.
enum ContactExportLink: Codable, Equatable, Sendable {
    case pendingCreation
    case linked(identifier: String, container: String)
}

enum ContactExportField: String, CaseIterable, Hashable, Identifiable {
    case firstName, lastName, birthday, photo
    var id: Self { self }
    var title: String {
        switch self {
        case .firstName: "First name"
        case .lastName: "Last name"
        case .birthday: "Birthday"
        case .photo: "Photo"
        }
    }
}

struct ContactExportValues: Equatable {
    var firstName: String = ""
    var lastName: String = ""
    var birthday: CivilDate?
    var photo: Data?

    init(firstName: String = "", lastName: String = "", birthday: CivilDate? = nil, photo: Data? = nil) {
        self.firstName = firstName
        self.lastName = lastName
        self.birthday = birthday
        self.photo = photo
    }

    init(person: Person, today: Date, calendar: Calendar = .current) {
        firstName = person.firstName ?? ""
        lastName = person.lastName ?? ""
        if case .exact(let exact) = person.birthday,
           (try? AgeRules(calendar: calendar).validate(person.birthday, on: today)) != nil {
            birthday = exact
        }
        photo = person.visiblePhoto(on: today, calendar: calendar)
    }

    var available: Set<ContactExportField> {
        var result: Set<ContactExportField> = []
        if !firstName.isEmpty { result.insert(.firstName) }
        if !lastName.isEmpty { result.insert(.lastName) }
        if birthday != nil { result.insert(.birthday) }
        if photo != nil { result.insert(.photo) }
        return result
    }

    func selected(_ fields: Set<ContactExportField>) -> Self {
        Self(firstName: fields.contains(.firstName) ? firstName : "",
             lastName: fields.contains(.lastName) ? lastName : "",
             birthday: fields.contains(.birthday) ? birthday : nil,
             photo: fields.contains(.photo) ? photo : nil)
    }
}

enum ContactExportError: LocalizedError {
    case alreadyLinked, noAccount, unavailable, reviewAgain, unknownResult
    var errorDescription: String? {
        switch self {
        case .alreadyLinked: "That contact is already linked to another person in Kin."
        case .noAccount: "Kin couldn’t identify the Contacts account. Check the default account in Settings or choose an existing contact."
        case .unavailable: "This contact is no longer available to Kin. Check Contacts access or choose the contact again."
        case .reviewAgain: "The person, contact, or account changed after review. Review again before saving."
        case .unknownResult: "Kin couldn’t verify the result. Check Contacts before continuing. Kin won’t create a second contact for this person."
        }
    }
}
