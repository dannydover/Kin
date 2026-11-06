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
