import Foundation

/// Display controls only; changing these never modifies notebook records.
struct PeopleFilterState: Equatable {
    enum Scope { case yours, all }
    var scope: Scope = .yours
    var query = ""
    var searching = false
    var category: Connection?

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func results(_ people: [Person]) -> [Person] {
        PeopleIndex.results(people, query: query, includeUnlisted: scope == .all, category: category)
    }

    /// The navigation menu clears display filters but preserves search presentation.
    mutating func switchScope(_ selection: Scope) {
        scope = selection; query = ""; category = nil
    }

    /// Clear returns to People and dismisses the search interface.
    mutating func clearSearchAndFilters() {
        scope = .yours; query = ""; category = nil; searching = false
    }
}
