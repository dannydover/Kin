import Foundation
import Testing
@testable import Kin

@Suite("Name-default draft intent") struct DraftGenderDefaultTests {
    private func lookup(_ name: String) -> Gender { ["Michael":Gender.male,"Mike":.male,"Chris":.male,"Synthetic Female":.female][name] ?? .unknown }
    @Test("Fresh automatic drafts recalculate and clear without any confirmation")
    func automatic() {
        var state = DraftGenderDefault(isNew: true)
        for name in ["Michael","Mike","Chris"] { state.nameChanged(name,lookup: lookup); #expect(state.value == .male && state.isAutomatic) }
        state.nameChanged("Synthetic Female",lookup: lookup); #expect(state.value == .female)
        state.nameChanged("Unmatched Fixture",lookup: lookup); #expect(state.value == .unknown)
    }
    @Test("Every explicit choice, including reselecting Unspecified, is sticky",arguments: Gender.allCases)
    func manual(_ gender: Gender) {
        var state = DraftGenderDefault(isNew: true); state.choose(gender)
        state.nameChanged("Michael",lookup: lookup); #expect(state.value == gender && !state.isAutomatic)
    }
    @Test("Existing values and pre-existing explicit draft choices remain untouched",arguments: Gender.allCases)
    func existing(_ gender: Gender) {
        for new in [false,true] {
            var state = DraftGenderDefault(value: gender,isNew: new,manuallyChosen: true)
            state.nameChanged("Synthetic Female",lookup: lookup); #expect(state.value == gender && !state.isAutomatic)
        }
        var saved = DraftGenderDefault(value: gender,isNew: false)
        saved.nameChanged("Michael",lookup: lookup); #expect(saved.value == gender)
    }
    @Test("Import review is a copy: cancellation and manual override preserve the earlier draft")
    func reviewCopy() {
        var earlier = DraftGenderDefault(isNew: true); earlier.nameChanged("Michael",lookup: lookup)
        var review = earlier; review.nameChanged("Synthetic Female",lookup: lookup); review.choose(.unknown); review.nameChanged("Chris",lookup: lookup)
        #expect(earlier.value == .male && earlier.isAutomatic)
        #expect(review.value == .unknown && !review.isAutomatic)
    }
}

@Suite("Independent category display filters") struct CategoryFilterTests {
    @Test("All includes visible uncategorized people; filters never promote linked-only people or duplicate overlaps")
    func categories() {
        var uncategorized = Person(firstName: "Synthetic Visible"); uncategorized.isListed = true
        var hidden = Person(firstName: "Synthetic Linked",connections: [.family]); hidden.isListed = false
        let shared = Person(firstName: "Synthetic Shared",connections: [.friend,.family])
        let colleague = Person(firstName: "Synthetic Colleague",connections: [.colleague])
        let people = [uncategorized,hidden,shared,colleague],before = people
        #expect(Set(PeopleIndex.results(people,query: "").map(\.id)) == Set([uncategorized.id,shared.id,colleague.id]))
        #expect(PeopleIndex.results(people,query: "",category: .friend).map(\.id) == [shared.id])
        #expect(PeopleIndex.results(people,query: "",category: .family).map(\.id) == [shared.id])
        #expect(PeopleIndex.results(people,query: "",category: .colleague).map(\.id) == [colleague.id])
        #expect(Set(PeopleIndex.results(people,query: "",includeUnlisted: true,category: .family).map(\.id)) == Set([hidden.id,shared.id]))
        #expect(PeopleIndex.results(people,query: "  SHARED  ",category: .family).map(\.id) == [shared.id])
        #expect(PeopleIndex.results(people,query: "Visible",category: .friend).isEmpty)
        #expect(people == before)
    }
    @Test("Category edits and list edits are reflected without changing the search or source identities")
    func updates() {
        var person = Person(firstName: "Synthetic Update",connections: [.friend])
        let id = person.id; person.connections = [.colleague]
        #expect(PeopleIndex.results([person],query: "Update",category: .friend).isEmpty)
        #expect(PeopleIndex.results([person],query: "Update",category: .colleague).first?.id == id)
        person.isListed = false
        #expect(PeopleIndex.results([person],query: "",category: .colleague).isEmpty)
        #expect(PeopleIndex.results([person],query: "",includeUnlisted: true,category: .colleague).first?.id == id)
    }
}

@Suite("Offline exact-spelling association lookup") struct NameAssociationsTests {
    @Test("Case and outer whitespace only, independent names, ambiguous case collisions fail closed")
    func normalizedLookup() throws {
        let data = Data(#"{"male":["Michael","Chris","Sam","CASE"],"female":["Mike","Case"]}"#.utf8)
        let lookup = try NameAssociations(data: data)
        #expect(lookup.gender(for: "  cHrIs\n") == .male)
        #expect(lookup.gender(for: "Michael") == .male)
        #expect(lookup.gender(for: "Mike") == .female)
        #expect(lookup.gender(for: "Samuel") == .unknown)
        #expect(lookup.gender(for: "Samantha") == .unknown)
        #expect(lookup.gender(for: "Míchael") == .unknown)
        #expect(lookup.gender(for: "Case") == .unknown)
        #expect(lookup.gender(for: "") == .unknown)
    }
    @Test("Invalid payload fails without inventing a value")
    func invalid() { #expect(throws: (any Error).self) { try NameAssociations(data: Data("{}".utf8)) } }
    @Test("Verified bundled snapshot is present and agreed examples resolve independently")
    func bundledResource() {
        let lookup = NameAssociations.bundled
        #expect(lookup.sourceAssociationCount == 35859)
        for name in ["Michael", "Mike", "Chris", "  cHrIs  "] { #expect(lookup.gender(for: name) == .male) }
        #expect(lookup.gender(for: "Samantha") == .female)
        #expect(lookup.gender(for: "Synthetic Unmatched Fixture") == .unknown)
    }

}
