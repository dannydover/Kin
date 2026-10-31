#if DEBUG
import Testing
@testable import Kin

@Suite("Synthetic UI fixture integrity") @MainActor struct DevelopmentPreviewTests {
    @Test("Filter preview contains three listed people with the expected categories")
    func filterNotebook() throws {
        let store = try DevelopmentPreview.filterNotebook()
        defer { try? store.close() }
        let people = store.people
        #expect(people.count == 3)
        #expect(Set(people.map(\.id)).count == 3)
        #expect(Set(people.compactMap(\.firstName)) == ["Alex Morgan", "Jamie Patel", "Robin Chen"])
        #expect(people.allSatisfy(\.isListed))
        #expect(people.first { $0.firstName == "Alex Morgan" }?.connections == [])
        #expect(people.first { $0.firstName == "Jamie Patel" }?.connections == [.friend])
        #expect(people.first { $0.firstName == "Robin Chen" }?.connections == [.family])
        #expect(store.parentLinks.isEmpty && store.partnerLinks.isEmpty)
    }
}
#endif
