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
        case .invalidName: "Please shorten each name to 200 characters or less. You can leave a name blank if you don’t know it."
        case .invalidBirthday: "Choose a valid date that isn’t in the future. Enter an age between 0 and 120 for an estimate."
        case .missingPerson: "This person is no longer in your notebook. Go back to All people to check."
        case .invalidLink: "Choose two different people who are already saved. If they’re already linked, edit that relationship instead."
        case .cycle: "This would make someone their own ancestor. Check the parent and child you selected."
        case .invalidData: "Kin couldn’t read your saved notebook. Your data hasn’t been reset. Try opening it again."
        case .incompatibleStore: "This version of Kin can’t open this notebook’s format. Your data hasn’t been changed. Keep it until you’ve decided whether to use another version or arrange a reset."
        case .photoNotAllowed: "Kin can only keep photos when we can be sure the person is at least 18. Check their birthday or estimate, or remove the photo."
        case .photoRemovalRequired: "This age means Kin can’t keep the saved photo. Confirm that you want to remove it before saving."
        case .staleEdit: "This person’s details changed while you were editing. Cancel this edit and open it again to see what’s saved."
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
