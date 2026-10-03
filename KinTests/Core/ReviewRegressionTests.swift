import Foundation
import CoreData
import Testing
@testable import Kin

func zonedDay(_ year: Int, _ month: Int, _ day: Int, zone: String, hour: Int = 12) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}
@Suite("Review regressions") struct ReviewRegressionTests {
    @Test("Travel preserves the entered birthday and September cutoff") func travelPreservesBirthdayAndSeptemberCutoff() {
        let birthday = Birthday.exact(CivilDate(zonedDay(2019, 9, 2, zone: "Europe/London", hour: 0), timeZone: TimeZone(identifier: "Europe/London")!))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let rules = AgeRules(calendar: calendar)
        let today = zonedDay(2026, 9, 1, zone: "America/Los_Angeles")
        #expect(rules.age(for: birthday, on: today) == 6)
        #expect(rules.grade(for: birthday, on: today) == "1st Grade")
    }
    @Test("Travel does not change an estimated birth year around July first") func travelDoesNotChangeEstimatedBirthYearAroundJulyFirst() {
        let birthday = Birthday.estimated(age: 3, referenceDate: CivilDate(zonedDay(2026, 7, 1, zone: "Europe/London", hour: 0), timeZone: TimeZone(identifier: "Europe/London")!))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        #expect(AgeRules(calendar: calendar).age(for: birthday, on: zonedDay(2026, 7, 1, zone: "America/Los_Angeles")) == 3)
    }
    @Test("Device calendar preferences do not redefine July or September", arguments: [Calendar.Identifier.hebrew, .islamic, .buddhist])
    func deviceCalendarPreferencesDoNotRedefineJulyOrSeptember(_ identifier: Calendar.Identifier) {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let rules = AgeRules(calendar: calendar)
        #expect(rules.grade(for: .exact(civil(2019, 8, 1)), on: day(2026, 10, 2)) == "2nd Grade")
        let birthday = Birthday.estimated(age: 3, referenceDate: civil(2026, 1, 1))
        #expect(rules.age(for: birthday, on: day(2026, 6, 30)) == 3)
        #expect(rules.age(for: birthday, on: day(2026, 7, 1)) == 4)
    }
    @Test("Only primary friend hits allow family deletion") func onlyPrimaryFriendHitsAllowFamilyDeletion() {
        let friend = Friend(firstName: "Rowan", lastName: "Vale", partners: [Partner(firstName: "Mira", lastName: "Vale")], children: [Child(firstName: "Ari", lastName: "Vale", birthday: .exact(civil(2020, 1, 1)))])
        let hits = FamilySearch.results(in: [friend], query: "Vale")
        #expect(hits.count == 3)
        #expect(hits.first?.allowsFamilyDeletion == true)
        #expect(hits.dropFirst().allSatisfy { !$0.allowsFamilyDeletion })
    }
}

@MainActor private final class SaveFailureSwitch { var enabled = false }
@Suite("Core Data save-failure recovery") @MainActor struct SaveFailureTests {
    private let failure: SaveFailureSwitch
    let store: KinStore
    init() throws {
        let failure = SaveFailureSwitch()
        self.failure = failure
        store = try KinStore(inMemory: true, saveContext: { context in
            if failure.enabled {
                // Force Core Data's own nonoptional-attribute validation to fail during save.
                let insertedChild = context.insertedObjects.first { $0.entity.name == "ChildRecord" }
                insertedChild?.setValue(nil, forKey: "payload")
            }
            try context.save()
        })
    }
    @Test("A real failed context save rolls back the entire family replacement") func realFailedContextSaveRollsBackEntireFamilyReplacement() throws {
        let friend = Friend(firstName: "Rowan", lastName: "Vale")
        try store.saveFriend(friend)
        let partner = Partner(firstName: "Mira", lastName: "Vale")
        try store.savePartner(partner, friendID: friend.id)
        let child = Child(firstName: "Ari", lastName: "Vale", birthday: .exact(civil(2020, 1, 1)), partnerID: partner.id)
        try store.saveChild(child, friendID: friend.id, today: day(2026, 10, 2), calendar: utcCalendar())
        let before = store.friends
        failure.enabled = true
        var failedWithCoreDataError = false
        do { try store.savePartner(Partner(firstName: "Jules", lastName: "Ash"), friendID: friend.id, replaceCurrent: true) }
        catch { failedWithCoreDataError = (error as NSError).domain == NSCocoaErrorDomain }
        #expect(failedWithCoreDataError)
        #expect(store.friends == before)
        try store.reload()
        #expect(store.friends == before)
        #expect(try store.entityCount("PartnerRecord") == 1)
        #expect(try store.entityCount("ChildRecord") == 1)
        failure.enabled = false
        var edited = child; edited.notes = "A valid later save"
        try store.saveChild(edited, friendID: friend.id, today: day(2026, 10, 2), calendar: utcCalendar())
        #expect(store.friends.first?.children.first?.notes == edited.notes)
    }
}
