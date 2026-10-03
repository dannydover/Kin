import Foundation
import Testing
@testable import Kin

func utcCalendar() -> Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(secondsFromGMT: 0)!
    return value
}
func civil(_ year: Int, _ month: Int, _ day: Int) -> CivilDate { CivilDate(year: year, month: month, day: day) }
func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utcCalendar().date(from: DateComponents(year: year, month: month, day: day))!
}
@Suite("Ages, grades, and life stages") struct AgeRulesTests {
    let rules = AgeRules(calendar: utcCalendar())
    @Test("Exact birthdays advance on the birthday", arguments: [(6, 30, 6), (7, 1, 7), (7, 2, 7)])
    func exactBirthdaysAdvanceOnBirthday(_ month: Int, _ date: Int, _ expected: Int) {
        #expect(rules.age(for: .exact(civil(2019, 7, 1)), on: day(2026, month, date)) == expected)
    }
    @Test("Estimated age preserves entry at the reference date", arguments: [1, 6, 7, 12])
    func estimatedAgePreservesEntryAtReferenceDate(_ month: Int) {
        let birthday = Birthday.estimated(age: 3, referenceDate: civil(2024, month, 1))
        #expect(rules.age(for: birthday, on: day(2024, month, 1)) == 3)
        #expect(rules.birthDate(for: birthday)?.month == 7)
        #expect(rules.birthDate(for: birthday)?.day == 1)
    }
    @Test("Estimated ages advance each July first", arguments: [(6, 30, 3), (7, 1, 4), (7, 2, 4)])
    func estimatedAgesAdvanceEachJulyFirst(_ month: Int, _ date: Int, _ expected: Int) {
        let birthday = Birthday.estimated(age: 3, referenceDate: civil(2024, 1, 15))
        #expect(rules.age(for: birthday, on: day(2024, month, date)) == expected)
        #expect(rules.displayAge(for: birthday, on: day(2024, month, date)) == "~\(expected)")
    }
    @Test("Exact conversion removes the qualifier") func exactConversionRemovesQualifier() {
        #expect(rules.displayAge(for: .exact(civil(2020, 12, 1)), on: day(2026, 10, 2)) == "5")
    }
    @Test("Grade table covers every school age", arguments: [
        (4, nil as String?), (5, "Kindergarten"), (6, "1st Grade"), (7, "2nd Grade"),
        (8, "3rd Grade"), (9, "4th Grade"), (10, "5th Grade"), (11, "6th Grade"),
        (12, "7th Grade"), (13, "8th Grade"), (14, "9th Grade"), (15, "10th Grade"),
        (16, "11th Grade"), (17, "12th Grade"), (18, nil)])
    func gradeTableCoversEverySchoolAge(_ age: Int, _ grade: String?) {
        #expect(rules.grade(for: .exact(civil(2026 - age, 8, 1)), on: day(2026, 10, 2)) == grade)
    }
    @Test("School year uses most recent September first", arguments: [(8, 31, "1st Grade"), (9, 1, "2nd Grade"), (9, 2, "2nd Grade")])
    func schoolYearUsesMostRecentSeptemberFirst(_ month: Int, _ date: Int, _ grade: String) {
        #expect(rules.grade(for: .exact(civil(2019, 8, 1)), on: day(2026, month, date)) == grade)
    }
    @Test("Children turning eighteen have no grade") func childrenTurningEighteenHaveNoGrade() {
        #expect(rules.grade(for: .exact(civil(2008, 10, 1)), on: day(2026, 10, 2)) == nil)
    }
    @Test("Life stage changes at each threshold", arguments: [(0, LifeStage.baby), (1, .baby), (2, .toddler), (4, .toddler), (5, .youngKid), (9, .youngKid), (10, .olderKid), (12, .olderKid), (13, .teen), (17, .teen), (18, .adult), (50, .adult)])
    func lifeStageChangesAtEachThreshold(_ age: Int, _ stage: LifeStage) {
        #expect(LifeStage.forAge(age) == stage)
    }
    @Test("Invalid birthday entries are rejected", arguments: [Birthday.exact(civil(2027, 1, 1)), .estimated(age: -1, referenceDate: civil(2026, 1, 1)), .estimated(age: 2, referenceDate: civil(2027, 1, 1))])
    func invalidBirthdayEntriesAreRejected(_ birthday: Birthday) {
        #expect(throws: (any Error).self) { try rules.validate(birthday, on: day(2026, 10, 2)) }
    }
}
