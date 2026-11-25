import Foundation

/// Selection is a value-only operation. A choice must still be reviewed and saved.
enum ExistingPersonChoices {
    static func results(_ people: [Person], sourceID: UUID, query: String) -> [Person] {
        PeopleIndex.results(people,query: query,includeUnlisted: true)
            .filter { $0.id != sourceID }
            .sorted { first,second in
                let order = first.displayName.localizedStandardCompare(second.displayName)
                if order != .orderedSame { return order == .orderedAscending }
                if first.reference != second.reference { return first.reference < second.reference }
                return first.id.uuidString < second.id.uuidString
            }
    }
    static func currentPartners(of sourceID: UUID, in links: [PartnerLink]) -> Set<UUID> {
        Set(links.filter { $0.status == .current && ($0.firstID == sourceID || $0.secondID == sourceID) }
            .map { $0.other(than: sourceID) })
    }

    static func children(_ people: [Person], sourceID: UUID, query: String,
                         partners: [PartnerLink], parents: [ParentLink]) -> [Person] {
        let candidates = results(people, sourceID: sourceID, query: query)
        let current = currentPartners(of: sourceID, in: partners)
        let knownChildren = Set(parents.filter { current.contains($0.parentID) }.map(\.childID))
        let surname = people.first { $0.id == sourceID }?.lastName?.trimmingCharacters(in: .whitespacesAndNewlines)
        func rank(_ person: Person) -> Int {
            if knownChildren.contains(person.id) { return 0 }
            if let surname, !surname.isEmpty,
               person.lastName?.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(surname, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame { return 1 }
            return 2
        }
        // Swift's stable sort preserves the chooser's name, reference, and identity order.
        return candidates.sorted { rank($0) < rank($1) }
    }

    static func needsReference(for person: Person, in people: [Person]) -> Bool {
        people.filter { $0.displayName.compare(person.displayName,options: [.caseInsensitive,.diacriticInsensitive]) == .orderedSame }.count > 1
    }
}
