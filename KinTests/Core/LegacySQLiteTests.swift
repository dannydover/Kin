import Foundation
import CoreData
import Testing
@testable import Kin

// Independent copies of the earlier payload shape. No checked-in database or personal data.
private enum OriginalBirthdayPayload: Encodable { case exact(Date) }
private struct OriginalChildPayload: Encodable {
    let id: UUID
    let firstName: String
    let lastName: String
    let gender: Gender
    let notes: String
    let birthday: OriginalBirthdayPayload
    let partnerID: UUID? = nil
}
@Suite("Original SQLite payload compatibility") @MainActor struct LegacySQLiteTests {
    @Test("Opening an old SQLite payload preserves its instant until reviewed") func openingOldSQLitePayloadPreservesItsInstantUntilReviewed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("original.sqlite")
        let instant = zonedDay(2019, 9, 2, zone: "Europe/London", hour: 0)
        let child = Child(firstName: "Ari", lastName: "Vale", birthday: .exact(civil(2019, 9, 2)))
        let originalBytes = try JSONEncoder().encode(OriginalChildPayload(id: child.id, firstName: child.firstName, lastName: child.lastName, gender: .unknown, notes: "Fictional legacy fixture", birthday: .exact(instant)))
        let writer = try KinStore(storeURL: url, saveContext: { context in
            for record in context.insertedObjects where record.entity.name == "ChildRecord" {
                record.setValue(originalBytes, forKey: "payload")
            }
            try context.save()
        })
        defer { try? writer.close() }
        let friend = Friend(firstName: "Rowan", lastName: "Vale", children: [child])
        try writer.saveFriend(friend)
        try writer.close()

        let opened = try KinStore(storeURL: url)
        defer { try? opened.close() }
        let legacy = try #require(opened.friends.first?.children.first)
        #expect(legacy.birthday == .legacyExact(instant))
        #expect(legacy.notes == "Fictional legacy fixture")
        #expect(legacy.birthday.requiresDateReview)
        var reviewed = legacy; reviewed.birthday = .exact(civil(2019, 9, 2))
        try opened.saveChild(reviewed, friendID: friend.id, today: day(2026, 10, 2), calendar: utcCalendar())
        try opened.close()

        let verified = try KinStore(storeURL: url)
        defer { try? verified.close() }
        #expect(verified.friends.first?.children.first?.birthday == reviewed.birthday)
        #expect(verified.friends.first?.children.first?.birthday.requiresDateReview == false)
        try verified.close()
    }
}
