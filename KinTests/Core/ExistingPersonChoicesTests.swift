import Foundation
import Testing
@testable import Kin

@Suite("Existing-person relationship choices") struct ExistingPersonChoicesTests {
    private func person(_ name: String, reference: Int, listed: Bool = false) -> Person {
        var value = Person(firstName: name,connections: listed ? [.friend] : [])
        value.reference = reference
        return value
    }
    @Test("An empty or whitespace search immediately lists everyone else, including unlisted people")
    func initialList() {
        let source = person("Source",reference: 1), visible = person("Blair",reference: 2,listed: true), unlisted = person("Alex",reference: 3)
        let people = [source,visible,unlisted], original = people
        for query in ["","  \n"] {
            #expect(ExistingPersonChoices.results(people,sourceID: source.id,query: query).map(\.id) == [unlisted.id,visible.id])
        }
        #expect(people == original)
    }
    @Test("Search filters names without inventing, selecting or linking a person")
    func filtering() {
        let source = person("Source",reference: 1), match = person("Élodie",reference: 2)
        let people = [source,match]
        #expect(ExistingPersonChoices.results(people,sourceID: source.id,query: "elodie").map(\.id) == [match.id])
        #expect(ExistingPersonChoices.results(people,sourceID: source.id,query: "no such person").isEmpty)
        #expect(ExistingPersonChoices.results([source],sourceID: source.id,query: "").isEmpty)
        #expect(people.count == 2)
    }
    @Test("Duplicate names remain distinct stable identities, ordered by notebook reference")
    func duplicates() {
        let source = person("Source",reference: 1), first = person("Alex Example",reference: 2), second = person("Alex Example",reference: 3)
        let choices = ExistingPersonChoices.results([second,source,first],sourceID: source.id,query: "Alex")
        #expect(choices.map(\.id) == [first.id,second.id])
        #expect(ExistingPersonChoices.needsReference(for: first,in: choices))
        #expect(!ExistingPersonChoices.needsReference(for: source,in: choices))
        #expect(ExistingPersonChoices.results([first,second,source],sourceID: source.id,query: "Alex").map(\.id) == choices.map(\.id))
    }
    @Test("Rank current partners’ recorded children before whole-surname matches while keeping everyone searchable")
    func childSuggestions() {
        let source = Person(firstName: "Source", lastName: "Vale-Smith")
        let a = Person(firstName: "Partner A"), b = Person(firstName: "Partner B"), past = Person(firstName: "Former")
        let z = Person(firstName: "Zed", lastName: "Vale-Smith"), y = Person(firstName: "Yara")
        let match = Person(firstName: "Xan", lastName: "vále-smith"), unrelated = Person(firstName: "Al", lastName: "Smith")
        let people = [source, a, b, past, z, y, match, unrelated]
        let partners = [PartnerLink(firstID: a.id, secondID: source.id, status: .current),
                        PartnerLink(firstID: source.id, secondID: b.id, status: .current),
                        PartnerLink(firstID: source.id, secondID: past.id, status: .former)]
        let parents = [ParentLink(parentID: a.id, childID: z.id), ParentLink(parentID: b.id, childID: y.id),
                       ParentLink(parentID: past.id, childID: unrelated.id)]
        func choices(_ query: String) -> [UUID] {
            ExistingPersonChoices.children(people, sourceID: source.id, query: query, partners: partners, parents: parents).map(\.id)
        }
        #expect(Array(choices("").prefix(3)) == [y.id, z.id, match.id])
        #expect(choices("").count == people.count - 1)
        #expect(choices("Smith") == [z.id, match.id, unrelated.id])
        #expect(choices("Yara") == [y.id])
        #expect(choices("absent").isEmpty)
    }
    @Test("Clearing an empty search restores both duplicate choices without selecting the source")
    func emptySearchResetPreservesDuplicateIdentity() {
        let source = person("Alex Example", reference: 1, listed: true)
        let hidden = person("Alex Example", reference: 2)
        let listed = person("Alex Example", reference: 3, listed: true)
        let people = [listed, source, hidden]
        let original = people
        let first = ExistingPersonChoices.results(people, sourceID: source.id, query: "alex")
        #expect(first.map(\.id) == [hidden.id, listed.id])
        #expect(ExistingPersonChoices.results(people, sourceID: source.id, query: "no synthetic match").isEmpty)
        let restored = ExistingPersonChoices.results(people, sourceID: source.id, query: "  \n")
        #expect(restored.map(\.id) == first.map(\.id))
        #expect(!restored.contains { $0.id == source.id })
        #expect(ExistingPersonChoices.needsReference(for: hidden, in: people))
        #expect(ExistingPersonChoices.needsReference(for: listed, in: people))
        #expect(people == original)
    }
}
