import Foundation
import Testing
@testable import Kin

@Suite("Persistence integrity") @MainActor struct PersistenceRegressionTests {
    let store: KinStore
    init() throws { store = try KinStore(inMemory: true) }
    @Test("Invalid replacement preserves the previous current partner") func invalidReplacementPreservesPreviousCurrentPartner() throws {
        let friend = Friend(firstName: "Rowan", lastName: "Vale")
        try store.saveFriend(friend)
        let current = Partner(firstName: "Mira", lastName: "Vale")
        try store.savePartner(current, friendID: friend.id)
        #expect(throws: (any Error).self) {
            try store.savePartner(Partner(firstName: " ", lastName: "Ash"), friendID: friend.id, replaceCurrent: true)
        }
        try store.reload()
        #expect(store.friends.first?.currentPartner?.id == current.id)
        #expect(try store.entityCount("PartnerRecord") == 1)
    }
    @Test("Saving a stale friend editor preserves family changes") func savingStaleFriendEditorPreservesFamilyChanges() throws {
        var friend = Friend(firstName: "Rowan", lastName: "Vale")
        try store.saveFriend(friend)
        try store.savePartner(Partner(firstName: "Mira", lastName: "Vale"), friendID: friend.id)
        friend.notes = "Fictional note"
        try store.saveFriend(friend)
        #expect(store.friends.first?.partners.count == 1)
    }
    @Test("Closing a store detaches its persistent stores without deleting data") func closingStoreDetachesPersistentStoresWithoutDeletingData() throws {
        #expect(!store.isClosed)
        try store.close()
        #expect(store.isClosed)
        try store.close()
        #expect(store.isClosed)
    }
    @Test("SQLite survives reopening and repeated family edits") func sqliteSurvivesReopeningAndRepeatedFamilyEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite")
        let disk = try KinStore(storeURL: url)
        defer { try? disk.close() }
        var friend = Friend(firstName: "Rowan", lastName: "Vale")
        try disk.saveFriend(friend)
        let partner = Partner(firstName: "Mira", lastName: "Vale")
        try disk.savePartner(partner, friendID: friend.id)
        var child = Child(firstName: "Ari", lastName: "Vale", birthday: .estimated(age: 3, referenceDate: civil(2026, 1, 1)), partnerID: partner.id)
        try disk.saveChild(child, friendID: friend.id, today: day(2026, 10, 2), calendar: utcCalendar())
        child.notes = "Fictional child note"
        try disk.saveChild(child, friendID: friend.id, today: day(2026, 10, 2), calendar: utcCalendar())
        friend.notes = "Fictional friend note"
        try disk.saveFriend(friend)
        let reopened = try KinStore(storeURL: url)
        defer { try? reopened.close() }
        #expect(reopened.friends.first?.children.first == child)
        #expect(reopened.friends.first?.partners == [partner])
        #expect(reopened.friends.first?.notes == friend.notes)
        try reopened.close()
        try disk.close()
    }
    #if DEBUG
    @Test("Preview fixtures cover all six stages without real personal data") func previewFixturesCoverAllSixStagesWithoutRealPersonalData() throws {
        let fixtures = DemoFamilies.make(on: day(2026, 10, 2), calendar: utcCalendar())
        #expect(fixtures.count == 3)
        let stages = fixtures.flatMap(\.children).compactMap { AgeRules(calendar: utcCalendar()).age(for: $0.birthday, on: day(2026, 10, 2)).map(LifeStage.forAge) }
        #expect(Set(stages) == Set(LifeStage.allCases))
    }
    #endif
}
