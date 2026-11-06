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
        let ids = Set(people.map { $0.id })
        #expect(ids.count == 3)
        let names = Set(people.compactMap { $0.firstName })
        let allListed = people.allSatisfy { $0.isListed }
        let alex = people.first { $0.firstName == "Alex Morgan" }
        let jamie = people.first { $0.firstName == "Jamie Patel" }
        let robin = people.first { $0.firstName == "Robin Chen" }
        #expect(names == ["Alex Morgan", "Jamie Patel", "Robin Chen"])
        #expect(allListed)
        #expect(alex?.connections == [])
        #expect(jamie?.connections == [.friend])
        #expect(robin?.connections == [.family])
        #expect(store.parentLinks.isEmpty && store.partnerLinks.isEmpty)
    }
}
#endif
