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
    static func needsReference(for person: Person, in people: [Person]) -> Bool {
        people.filter { $0.displayName.compare(person.displayName,options: [.caseInsensitive,.diacriticInsensitive]) == .orderedSame }.count > 1
    }
}
