#if DEBUG
import Foundation
import ImageIO
import Testing
@testable import Kin

@Suite("Isolated saved-photo fixture") @MainActor
struct SavedPhotoFixtureTests {
    @Test("A synthetic adult photo is decodable and remains unchanged after reopen")
    func savedPhotoPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let token = UUID()
        let today = CivilDate(year: 2026, month: 11, day: 3)
        let store = try KinStore(storeURL: directory.appendingPathComponent("photo-fixture.sqlite"))
        defer { try? store.close() }
        try SyntheticNotebookFixture.seed("estimated-contact-photo", token: token, store: store, today: today)
        let saved = try store.person(token)
        #expect(saved.firstName == "Synthetic Existing Draft" && saved.isListed && saved.connections == [.friend])
        #expect(saved.birthday == .estimated(age: 80, referenceDate: today))
        let data = try #require(saved.photo)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 96 && image.height == 96)
        try store.close(); try store.resume()
        #expect(try store.person(token) == saved)
        try SyntheticNotebookFixture.seed("estimated-contact-photo", token: token, store: store, today: today)
        #expect(try store.person(token) == saved)
    }

    @Test("An existing unrelated notebook is never overwritten")
    func refusesExistingNotebook() throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        try store.savePerson(Person(firstName: "Synthetic existing", connections: [.friend]))
        let before = store.people
        #expect(throws: SyntheticNotebookFixture.FixtureError.nonemptyNotebook) {
            try SyntheticNotebookFixture.seed("estimated-contact-photo", token: UUID(), store: store)
        }
        #expect(store.people == before && store.parentLinks.isEmpty && store.partnerLinks.isEmpty)
    }
}
#endif
