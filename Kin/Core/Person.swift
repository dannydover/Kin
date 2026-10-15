import Foundation

enum Gender: String, CaseIterable, Codable, Sendable, Identifiable {
    case unknown, male, female, other
    var id: String { rawValue }
}
enum Connection: String, CaseIterable, Codable, Sendable, Identifiable {
    case friend, family, colleague
    var id: String { rawValue }
}
enum Birthday: Codable, Equatable, Sendable {
    case unknown
    case exact(CivilDate)
    case estimated(age: Int, referenceDate: CivilDate)
    var isStructurallyValid: Bool {
        switch self {
        case .unknown: return true
        case .exact(let date): return date.isValid
        case .estimated(let age, let reference):
            guard (0...120).contains(age), reference.isValid else { return false }
            return reference.year > age + 1
        }
    }
    var isEstimated: Bool { if case .estimated = self { true } else { false } }
}
struct Person: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var firstName: String?
    var lastName: String?
    var gender: Gender = .unknown
    var notes = ""
    var birthday: Birthday = .unknown
    var connections: Set<Connection> = []
    var photo: Data?
    // Assigned once by the store. A label describes the original entry context,
    // never birth order, legal name, gender, or inferred kinship.
    var revision = 0
    var reference = 0
    var unnamedRole = "Person"
    init(id: UUID = UUID(), firstName: String? = nil, lastName: String? = nil,
         gender: Gender = .unknown, birthday: Birthday = .unknown, connections: Set<Connection> = [], photo: Data? = nil) {
        self.id = id; self.firstName = firstName; self.lastName = lastName
        self.gender = gender; self.birthday = birthday; self.connections = connections; self.photo = photo
    }
    var displayName: String {
        let first = firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let last = lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if first.isEmpty {
            let label = "\(unnamedRole) \(reference)"
            return last.isEmpty ? label : label + " · " + last
        }
        return last.isEmpty ? first : first + " " + last
    }
    var nameUnknown: Bool { firstName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true }
    func visiblePhoto(on today: Date, calendar: Calendar = .current) -> Data? {
        AgeRules(calendar: calendar).allowsPhoto(birthday, on: today) ? photo : nil
    }
}
enum Parentage: String, CaseIterable, Codable, Sendable, Identifiable {
    case biological, adoptive, step, unspecified
    var id: String { rawValue }
}
enum PartnerStatus: String, CaseIterable, Codable, Sendable, Identifiable {
    case current, former, unknown
    var id: String { rawValue }
}
struct ParentLink: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var parentID: UUID
    var childID: UUID
    var parentage: Parentage = .unspecified
}
struct PartnerLink: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var firstID: UUID
    var secondID: UUID
    var status: PartnerStatus = .unknown
    func other(than id: UUID) -> UUID { firstID == id ? secondID : firstID }
}
enum KinError: LocalizedError, Equatable {
    case invalidName, invalidBirthday, missingPerson, invalidLink, cycle, invalidData, incompatibleStore, photoNotAllowed, photoRemovalRequired, staleEdit
    var errorDescription: String? {
        switch self {
        case .invalidName: "Names must be 200 characters or fewer. Leave unknown names blank."
        case .invalidBirthday: "Use a valid date on or before today and an age from 0 to 120."
        case .missingPerson: "This person is no longer available."
        case .invalidLink: "Choose two different existing people. This relationship may already exist."
        case .cycle: "A person cannot be their own ancestor. Review the parent links."
        case .invalidData: "Kin couldn’t read the saved notebook. Your data has not been reset."
        case .incompatibleStore: "This notebook uses an earlier or unsupported format. It has been left untouched. An explicit reset must be coordinated before using this version."
        case .photoNotAllowed: "Photos require a known age of at least 18. Every age represented by an estimate must be at least 18."
        case .photoRemovalRequired: "This age change requires removing the existing photo. Confirm removal before saving."
        case .staleEdit: "This person changed while the editor was open. Cancel and reopen to review the saved information."
        }
    }
}
enum PeopleIndex {
    static func results(_ people: [Person], query: String, includeUnlisted: Bool = false) -> [Person] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return people.filter { (includeUnlisted || !$0.connections.isEmpty) && (query.isEmpty || $0.displayName.localizedStandardContains(query)) }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}
