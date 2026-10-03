import Foundation
import Observation

enum Gender: String, CaseIterable, Codable, Sendable, Identifiable {
    case unknown, male, female
    var id: String { rawValue }
}
struct Partner: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var firstName: String
    var lastName: String
    var photo: Data? = nil
    var gender: Gender = .unknown
    var isCurrent = true
    var fullName: String { "\(firstName) \(lastName)" }
}
struct Child: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var firstName: String
    var lastName: String
    var gender: Gender = .unknown
    var notes = ""
    var birthday: Birthday
    var partnerID: UUID? = nil
    var fullName: String { "\(firstName) \(lastName)" }
    func displayName(friendLastName: String) -> String {
        lastName.localizedCaseInsensitiveCompare(friendLastName) == .orderedSame ? firstName : fullName
    }
}
struct Friend: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var firstName: String
    var lastName: String
    var photo: Data? = nil
    var notes = ""
    var partners: [Partner] = []
    var children: [Child] = []
    var fullName: String { "\(firstName) \(lastName)" }
    var currentPartner: Partner? { partners.first(where: \.isCurrent) }
}
struct SearchHit: Identifiable, Sendable {
    var allowsFamilyDeletion: Bool { id == friendID && subtitle == nil }
    var id: UUID
    var friendID: UUID
    var title: String
    var subtitle: String?
}
enum FamilySearch {
    static func results(in friends: [Friend], query: String) -> [SearchHit] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sorted = friends.sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
        let direct = sorted.filter { query.isEmpty || $0.fullName.localizedStandardContains(query) }
            .map { SearchHit(id: $0.id, friendID: $0.id, title: $0.fullName, subtitle: nil) }
        guard !query.isEmpty else { return direct }
        var secondary: [SearchHit] = []
        for friend in sorted {
            for partner in friend.partners where partner.fullName.localizedStandardContains(query) {
                secondary.append(SearchHit(id: partner.id, friendID: friend.id, title: partner.fullName,
                    subtitle: "\(partner.fullName) · \(partner.isCurrent ? "Partner" : "Former partner") of \(friend.fullName)"))
            }
            for child in friend.children where child.fullName.localizedStandardContains(query) {
                secondary.append(SearchHit(id: child.id, friendID: friend.id, title: child.fullName,
                    subtitle: "\(child.fullName) · Child of \(friend.fullName)"))
            }
        }
        return direct + secondary
    }
}
struct FamilyGroup: Identifiable {
    var id: String
    var partner: Partner?
    var children: [Child]
}
struct FamilyLayout {
    var grouped = false
    var groups: [FamilyGroup] = []
    var compactFormerPartners: [Partner] = []
    init(friend: Friend) {
        grouped = friend.partners.count > 1 || friend.children.contains { $0.partnerID != nil }
        compactFormerPartners = friend.partners.filter { partner in
            !partner.isCurrent && !friend.children.contains { $0.partnerID == partner.id }
        }
        if grouped {
            if let current = friend.currentPartner {
                groups.append(FamilyGroup(id: current.id.uuidString, partner: current,
                    children: friend.children.filter { $0.partnerID == current.id }))
            }
            let unlinked = friend.children.filter { $0.partnerID == nil }
            if !unlinked.isEmpty { groups.append(FamilyGroup(id: "unlinked", partner: nil, children: unlinked)) }
            for partner in friend.partners where !partner.isCurrent {
                let children = friend.children.filter { $0.partnerID == partner.id }
                if !children.isEmpty { groups.append(FamilyGroup(id: partner.id.uuidString, partner: partner, children: children)) }
            }
        } else {
            groups = [FamilyGroup(id: "children", partner: nil, children: friend.children)]
        }
    }
}
