import Foundation
import Testing
@testable import Kin

@Suite("People display state") struct PeopleFilterStateTests {
    @Test("Clear resets every combination of scope, query, category and search presentation")
    func clear() {
        var listed = Person(firstName: "Synthetic Listed", connections: [.friend])
        listed.isListed = true
        var uncategorized = Person(firstName: "Synthetic Unlabeled")
        uncategorized.isListed = true
        var hidden = Person(firstName: "Synthetic Hidden", connections: [.family])
        hidden.isListed = false
        let people = [listed, uncategorized, hidden]
        for scope: PeopleFilterState.Scope in [.yours, .all] {
            for query in ["", "Synthetic", "no match"] {
                for category: Connection? in [nil, .friend, .colleague] {
                    for searching in [false, true] {
                        var state = PeopleFilterState(scope: scope, query: query, searching: searching, category: category)
                        state.clearSearchAndFilters()
                        #expect(state == PeopleFilterState())
                        let result = state.results(people)
                        let resultIDs = Set(result.map { $0.id })
                        #expect(resultIDs == Set([listed.id, uncategorized.id]))
                        #expect(people == [listed, uncategorized, hidden])
                        state.clearSearchAndFilters()
                        #expect(state == PeopleFilterState())
                    }
                }
            }
        }
    }

    @Test("Scope switch clears filters but preserves search presentation")
    func scopeSwitch() {
        for searching in [false, true] {
            for destination: PeopleFilterState.Scope in [.yours, .all] {
                var state = PeopleFilterState(scope: .all, query: "Synthetic", searching: searching, category: .friend)
                state.switchScope(destination)
                #expect(state.scope == destination && state.query.isEmpty && state.category == nil)
                #expect(state.searching == searching)
            }
        }
    }

    @Test("Search all keeps existing query and category while including hidden people")
    func searchAll() {
        var hidden = Person(firstName: "Synthetic Hidden", connections: [.family])
        hidden.isListed = false
        var state = PeopleFilterState(scope: .yours, query: "Hidden", searching: true, category: .family)
        #expect(state.results([hidden]).isEmpty)
        state.scope = .all
        #expect(state.query == "Hidden" && state.searching && state.category == .family)
        let allIDs = state.results([hidden]).map { $0.id }
        #expect(allIDs == [hidden.id])
    }

    @Test("Whitespace-only search is not treated as a search")
    func whitespace() {
        var state = PeopleFilterState()
        state.query = " \n\t"
        #expect(!state.isSearching)
        state.query = " Name "
        #expect(state.isSearching)
    }
}
