import Foundation
import Testing
@testable import Kin

private let regressionCalendar = CivilDate.pickerCalendar
private func regressionDay(_ year: Int, _ month: Int, _ day: Int, zone: TimeZone = regressionCalendar.timeZone) -> Date {
    CivilDate.gregorian(in: zone).date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}
@Suite("Retained civil age and presentation regressions") struct PersonAgeRegressionTests {
    @Test("Profile relationship sections use recorded age with an independent sixteen boundary", arguments: [
        (Birthday.unknown, CivilDate(year: 2026, month: 10, day: 15), true),
        (.exact(CivilDate(year: 2010, month: 10, day: 15)), CivilDate(year: 2026, month: 10, day: 14), false),
        (.exact(CivilDate(year: 2010, month: 10, day: 15)), CivilDate(year: 2026, month: 10, day: 15), true),
        (.estimated(age: 15, referenceDate: CivilDate(year: 2025, month: 10, day: 15)), CivilDate(year: 2026, month: 10, day: 14), false),
        (.estimated(age: 15, referenceDate: CivilDate(year: 2025, month: 10, day: 15)), CivilDate(year: 2026, month: 10, day: 15), true),
        (.estimated(age: 16, referenceDate: CivilDate(year: 2026, month: 10, day: 15)), CivilDate(year: 2026, month: 10, day: 15), true)
    ])
    func profileSections(_ birth: Birthday, _ day: CivilDate, _ expected: Bool) {
        let rules = AgeRules(calendar: regressionCalendar)
        #expect(rules.showsPartnerAndChildSections(for: birth, on: day.pickerDate) == expected)
        #expect(!rules.allowsPhoto(birth, on: day.pickerDate))
    }
    @Test("Estimated age boundaries remain zero through 120", arguments: [0,80,120,-1,121,Int.max])
    func estimatedAgeBoundaries(_ age: Int) {
        let birthday = Birthday.estimated(age: age,referenceDate: CivilDate(year: 2026,month: 10,day: 15))
        if (0...120).contains(age) {
            #expect(throws: Never.self) { try AgeRules(calendar: regressionCalendar).validate(birthday,on: regressionDay(2026,10,15)) }
        } else {
            #expect(throws: (any Error).self) { try AgeRules(calendar: regressionCalendar).validate(birthday,on: regressionDay(2026,10,15)) }
        }
    }
    @Test("Every school grade remains mapped correctly", arguments: [
        (4, nil as String?), (5, "Kindergarten"), (6, "1st Grade"), (7, "2nd Grade"), (8, "3rd Grade"),
        (9, "4th Grade"), (10, "5th Grade"), (11, "6th Grade"), (12, "7th Grade"), (13, "8th Grade"),
        (14, "9th Grade"), (15, "10th Grade"), (16, "11th Grade"), (17, "12th Grade"), (18, nil)])
    func grades(_ age: Int, _ expected: String?) {
        #expect(AgeRules(calendar: regressionCalendar).grade(for: .exact(CivilDate(year: 2026-age, month: 8, day: 1)), on: regressionDay(2026, 10, 2)) == expected)
    }
    @Test("School year rolls over on September first", arguments: [(8,31,"1st Grade"),(9,1,"2nd Grade"),(9,2,"2nd Grade")])
    func schoolYear(_ month: Int, _ day: Int, _ expected: String) {
        #expect(AgeRules(calendar: regressionCalendar).grade(for: .exact(CivilDate(year: 2019, month: 8, day: 1)), on: regressionDay(2026,month,day)) == expected)
    }
    @Test("All life stage boundaries remain intact", arguments: [(0,LifeStage.baby),(1,.baby),(2,.toddler),(4,.toddler),(5,.youngKid),(9,.youngKid),(10,.olderKid),(12,.olderKid),(13,.teen),(17,.teen),(18,.adult),(50,.adult)])
    func stages(_ age: Int, _ expected: LifeStage) { #expect(LifeStage.forAge(age) == expected) }
    @Test("Calendar preferences never redefine civil ages or school cutoff", arguments: [Calendar.Identifier.hebrew,.islamic,.buddhist])
    func calendars(_ identifier: Calendar.Identifier) {
        var preferred = Calendar(identifier: identifier); preferred.timeZone = regressionCalendar.timeZone
        let rules = AgeRules(calendar: preferred)
        #expect(rules.grade(for: .exact(CivilDate(year: 2019,month: 8,day: 1)), on: regressionDay(2026,10,2)) == "2nd Grade")
        let estimate = Birthday.estimated(age: 17,referenceDate: CivilDate(year: 2025,month: 10,day: 15))
        #expect(rules.age(for: estimate,on: regressionDay(2026,10,14)) == 17)
        #expect(rules.age(for: estimate,on: regressionDay(2026,10,15)) == 18)
        #expect(rules.allowsPhoto(estimate,on: regressionDay(2026,10,15)))
    }
    @Test("Travel preserves civil dates at birthdays and school cutoff", arguments: ["America/Los_Angeles","Europe/London","Pacific/Kiritimati"])
    func travel(_ identifier: String) throws {
        let zone = TimeZone(identifier: identifier)!, rules = AgeRules(calendar: CivilDate.gregorian(in: zone))
        let birthday = Birthday.exact(CivilDate(year: 2019,month: 9,day: 2))
        #expect(rules.age(for: birthday,on: regressionDay(2026,9,1,zone: zone)) == 6)
        #expect(rules.grade(for: birthday,on: regressionDay(2026,9,1,zone: zone)) == "1st Grade")
        let estimate = Birthday.estimated(age: 17,referenceDate: CivilDate(year: 2025,month: 10,day: 15))
        #expect(!rules.allowsPhoto(estimate,on: regressionDay(2026,10,14,zone: zone)))
        #expect(rules.allowsPhoto(estimate,on: regressionDay(2026,10,15,zone: zone)))
        #expect(try JSONDecoder().decode(Birthday.self,from: JSONEncoder().encode(birthday)) == birthday)
    }
    @Test("Exact leap birthday advances on March first in a common year")
    func exactLeap() {
        let rules = AgeRules(calendar: regressionCalendar), birth = Birthday.exact(CivilDate(year: 2008,month: 2,day: 29))
        #expect(rules.age(for: birth,on: regressionDay(2026,2,28)) == 17)
        #expect(!rules.allowsPhoto(birth,on: regressionDay(2026,2,28)))
        #expect(rules.age(for: birth,on: regressionDay(2026,3,1)) == 18)
        #expect(rules.allowsPhoto(birth,on: regressionDay(2026,3,1)))
    }
    @Test("Malformed estimate inputs are safe to present", arguments: [Int.min,-1,121,Int.max])
    func malformed(_ age: Int) {
        let rules = AgeRules(calendar: regressionCalendar), bad = Birthday.estimated(age: age,referenceDate: CivilDate(year: 2020,month: 1,day: 1))
        #expect(rules.age(for: bad,on: regressionDay(2026,10,15)) == nil)
        #expect(rules.displayAge(for: bad,on: regressionDay(2026,10,15)) == "Age unknown")
        #expect(rules.grade(for: bad,on: regressionDay(2026,10,15)) == nil)
        #expect(!rules.allowsPhoto(bad,on: regressionDay(2026,10,15)))
    }
    @Test("Civil label formatting uses Gregorian UTC even for an alternate locale calendar")
    func formatting() {
        let day = CivilDate(year: 2026,month: 10,day: 15)
        #expect(day.formatted(locale: Locale(identifier: "en_US")) == "Oct 15, 2026")
        #expect(day.formatted(locale: Locale(identifier: "en_US@calendar=hebrew")) == "Oct 15, 2026")
        let misleading = DateFormatter(); misleading.locale = Locale(identifier: "en_US")
        misleading.calendar = regressionCalendar; misleading.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!; misleading.dateStyle = .medium
        #expect(misleading.string(from: day.pickerDate) == "Oct 16, 2026")
        // The actual label formatter cannot inherit that timezone/calendar.
        #expect(day.formatted(locale: Locale(identifier: "en_US")) != misleading.string(from: day.pickerDate))
    }
}
@Suite("Retained person name and search regressions") @MainActor struct PersonNameRegressionTests {
    @Test("Optional names trim, unknown drafts cancel, and search folds accents")
    func namesAndSearch() throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        var p = Person(firstName: "  Élodie  ",lastName: "  Vale  ",connections: [.friend])
        try store.savePerson(p); p = try store.person(p.id)
        #expect(p.firstName == "Élodie" && p.lastName == "Vale")
        #expect(PeopleIndex.results(store.people,query: "elodie").map(\.id) == [p.id])
        var canceled = p; canceled.firstName = "  "; canceled.lastName = nil
        #expect(canceled.nameUnknown)
        try store.reload(); #expect(try store.person(p.id) == p)
        try store.savePerson(canceled)
        let unknown = try store.person(p.id)
        #expect(unknown.firstName == nil && unknown.nameUnknown && unknown.displayName == "Person 1")
        var tooLong = unknown; tooLong.lastName = String(repeating: "x",count: 201)
        #expect(throws: KinError.invalidName) { try store.savePerson(tooLong) }
        #expect(try store.person(p.id) == unknown)
    }
}
