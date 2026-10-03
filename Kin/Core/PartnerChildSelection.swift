import Foundation

/// A value draft: changing or discarding a checklist never writes to the store.
struct PartnerChildSelection {
    struct Option: Identifiable {
        let id: UUID
        let name: String
        let association: String
        let reassigns: Bool
    }
    let options: [Option]
    private(set) var selectedIDs: Set<UUID>

    init(friend: Friend, partnerID: UUID) {
        selectedIDs = Set(friend.children.filter { $0.partnerID == partnerID }.map(\.id))
        options = friend.children.sorted {
            $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending
        }.map { child in
            let linked = friend.partners.first { $0.id == child.partnerID }
            return Option(id: child.id, name: child.fullName,
                association: linked.map { "Currently linked to \($0.fullName)" } ?? "No partner linked",
                reassigns: child.partnerID != nil && child.partnerID != partnerID)
        }
    }
    mutating func toggle(_ id: UUID) {
        guard options.contains(where: { $0.id == id }) else { return }
        if !selectedIDs.insert(id).inserted { selectedIDs.remove(id) }
    }
}
