import Foundation
import Testing
@testable import Kin

@Suite("Date storage migration") struct DateMigrationTests {
    @Test("Legacy exact instants require review and survive reencoding") func legacyExactInstantsRequireReviewAndSurviveReencoding() throws {
        let original = zonedDay(2019, 9, 2, zone: "Europe/London", hour: 0)
        let bytes = try JSONSerialization.data(withJSONObject: ["exact": ["_0": original.timeIntervalSinceReferenceDate]])
        let legacy = try JSONDecoder().decode(Birthday.self, from: bytes)
        #expect(legacy.requiresDateReview)
        #expect(AgeRules(calendar: utcCalendar()).displayAge(for: legacy, on: day(2026, 10, 2)) == "Review date")
        #expect(AgeRules(calendar: utcCalendar()).grade(for: legacy, on: day(2026, 10, 2)) == nil)
        #expect(try JSONDecoder().decode(Birthday.self, from: JSONEncoder().encode(legacy)) == legacy)
        #expect(throws: (any Error).self) { try AgeRules(calendar: utcCalendar()).validate(legacy, on: day(2026, 10, 2)) }
    }
    @Test("Legacy estimated entries retain the stated age and original instant") func legacyEstimatedEntriesRetainStatedAgeAndOriginalInstant() throws {
        let original = zonedDay(2026, 7, 1, zone: "Europe/London", hour: 0)
        let bytes = try JSONSerialization.data(withJSONObject: ["estimated": ["age": 3, "referenceDate": original.timeIntervalSinceReferenceDate]])
        let legacy = try JSONDecoder().decode(Birthday.self, from: bytes)
        #expect(legacy.requiresDateReview)
        #expect(try JSONDecoder().decode(Birthday.self, from: JSONEncoder().encode(legacy)) == legacy)
    }
    @Test("New entries encode an explicit civil-date schema") func newEntriesEncodeExplicitCivilDateSchema() throws {
        let bytes = try JSONEncoder().encode(Birthday.exact(civil(2019, 9, 2)))
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 2)
        #expect((object["date"] as? [String: Int]) == ["year": 2019, "month": 9, "day": 2])
    }
}

@Suite("Civil date integrity") struct CivilDateIntegrityTests {
    @Test("Civil dates survive encode decode across timezones", arguments: ["Europe/London", "America/Los_Angeles", "Pacific/Kiritimati", "Pacific/Honolulu"])
    func civilDatesSurviveEncodeDecodeAcrossTimezones(_ zone: String) throws {
        let birthday = Birthday.exact(civil(2019, 9, 2))
        let restored = try JSONDecoder().decode(Birthday.self, from: JSONEncoder().encode(birthday))
        let rules = AgeRules(calendar: CivilDate.gregorian(in: TimeZone(identifier: zone)!))
        #expect(rules.age(for: restored, on: zonedDay(2026, 9, 1, zone: zone)) == 6)
        #expect(rules.age(for: restored, on: zonedDay(2026, 9, 2, zone: zone)) == 7)
        #expect(rules.grade(for: restored, on: zonedDay(2026, 9, 2, zone: zone)) == "1st Grade")
    }
    @Test("Malformed dates and unknown schemas fail instead of normalizing", arguments: [
        "{\"schemaVersion\":2,\"kind\":\"exact\",\"date\":{\"year\":2025,\"month\":2,\"day\":29}}",
        "{\"schemaVersion\":2,\"kind\":\"exact\",\"date\":{\"year\":2025,\"month\":13,\"day\":1}}",
        "{\"schemaVersion\":99,\"kind\":\"exact\",\"date\":{\"year\":2020,\"month\":1,\"day\":1}}"
    ]) func malformedDatesAndUnknownSchemasFailInsteadOfNormalizing(_ json: String) {
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Birthday.self, from: Data(json.utf8)) }
    }
    @Test("Leap day birthdays advance on March first in common years") func leapDayBirthdaysAdvanceOnMarchFirstInCommonYears() {
        let rules = AgeRules(calendar: utcCalendar())
        #expect(rules.age(for: .exact(civil(2020, 2, 29)), on: day(2025, 2, 28)) == 4)
        #expect(rules.age(for: .exact(civil(2020, 2, 29)), on: day(2025, 3, 1)) == 5)
    }
}

@Suite("Legacy family preservation") @MainActor struct LegacyFamilyPreservationTests {
    let store: KinStore
    init() throws { store = try KinStore(inMemory: true) }
    @Test("Unrelated edits preserve legacy dates until explicit confirmation") func unrelatedEditsPreserveLegacyDatesUntilExplicitConfirmation() throws {
        let instant = zonedDay(2019, 9, 2, zone: "Europe/London", hour: 0)
        let original = try JSONDecoder().decode(Birthday.self, from: JSONSerialization.data(withJSONObject: ["exact": ["_0": instant.timeIntervalSinceReferenceDate]]))
        let child = Child(firstName: "Ari", lastName: "Vale", birthday: original)
        var friend = Friend(firstName: "Rowan", lastName: "Vale", children: [child])
        try store.saveFriend(friend)
        friend.notes = "Only the note changed"
        try store.saveFriend(friend)
        try store.reload()
        #expect(store.friends.first?.children.first?.birthday == original)
        #expect(store.friends.first?.children.first?.birthday.requiresDateReview == true)
        var reviewed = child; reviewed.birthday = .exact(civil(2019, 9, 2))
        try store.saveChild(reviewed, friendID: friend.id, today: day(2026, 10, 2), calendar: utcCalendar())
        try store.reload()
        #expect(store.friends.first?.children.first?.birthday == reviewed.birthday)
        #expect(store.friends.first?.children.first?.birthday.requiresDateReview == false)
    }
}
