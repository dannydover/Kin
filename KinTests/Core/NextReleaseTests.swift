import Foundation
import Testing
@testable import Kin

@Suite("Next release civil age presentation") struct BabyAgeTests {
    let rules = AgeRules(calendar: CivilDate.pickerCalendar)
    @Test("Completed calendar months and singular/plural", arguments: [
        (2026,1,15,"Less than 1 month"),(2026,2,14,"Less than 1 month"),
        (2026,2,15,"1 month"),(2026,2,16,"1 month"),(2026,12,15,"11 months"),
        (2027,1,14,"11 months"),(2027,1,15,"1 year"),(2027,1,16,"1 year"),(2027,12,15,"1 year"),(2028,1,14,"1 year"),
        (2028,1,15,"2 years"),(2028,1,16,"2 years")])
    func months(_ y: Int,_ m: Int,_ d: Int,_ expected: String) {
        #expect(rules.displayAge(for: .exact(CivilDate(year: 2026,month: 1,day: 15)),on: CivilDate(year: y,month: m,day: d).pickerDate) == expected)
    }
    @Test("Month-end anniversaries clamp to the final valid day; leap birthdays keep existing year rules")
    func monthEnds() {
        let jan = Birthday.exact(CivilDate(year: 2026,month: 1,day: 31))
        #expect(rules.displayAge(for: jan,on: CivilDate(year: 2026,month: 2,day: 27).pickerDate) == "Less than 1 month")
        #expect(rules.displayAge(for: jan,on: CivilDate(year: 2026,month: 2,day: 28).pickerDate) == "1 month")
        #expect(rules.displayAge(for: jan,on: CivilDate(year: 2026,month: 3,day: 30).pickerDate) == "1 month")
        #expect(rules.displayAge(for: jan,on: CivilDate(year: 2026,month: 3,day: 31).pickerDate) == "2 months")
        #expect(rules.displayAge(for: jan,on: CivilDate(year: 2027,month: 1,day: 30).pickerDate) == "11 months")
        #expect(rules.displayAge(for: jan,on: CivilDate(year: 2027,month: 1,day: 31).pickerDate) == "1 year")
        let leap = Birthday.exact(CivilDate(year: 2024,month: 2,day: 29))
        #expect(rules.displayAge(for: leap,on: CivilDate(year: 2025,month: 2,day: 27).pickerDate) == "11 months")
        #expect(rules.displayAge(for: leap,on: CivilDate(year: 2025,month: 2,day: 28).pickerDate) == "11 months")
        #expect(rules.displayAge(for: leap,on: CivilDate(year: 2025,month: 3,day: 1).pickerDate) == "1 year")
        #expect(rules.displayAge(for: leap,on: CivilDate(year: 2026,month: 2,day: 28).pickerDate) == "1 year")
        #expect(rules.displayAge(for: leap,on: CivilDate(year: 2026,month: 3,day: 1).pickerDate) == "2 years")
    }
    @Test("Approximate and malformed inputs never acquire month precision")
    func precision() {
        let day = CivilDate(year: 2026,month: 10,day: 22)
        #expect(rules.displayAge(for: .estimated(age: 0,referenceDate: day),on: day.pickerDate) == "~0 years")
        #expect(rules.displayAge(for: .estimated(age: 1,referenceDate: day),on: day.pickerDate) == "~1 year")
        for birth in [Birthday.unknown,.exact(CivilDate(year: 2026,month: 2,day: 30)),.exact(CivilDate(year: 2027,month: 1,day: 1))] {
            #expect(rules.displayAge(for: birth,on: day.pickerDate) == "Age unknown")
            #expect(!rules.allowsPhoto(birth,on: day.pickerDate))
        }
    }
    @Test("Local civil day governs month rollover across time zones", arguments: ["America/Los_Angeles","Pacific/Kiritimati","Europe/London"])
    func travel(_ zone: String) {
        var calendar = CivilDate.gregorian(in: TimeZone(identifier: zone)!)
        calendar.locale = Locale(identifier: "en_US")
        let date = calendar.date(from: DateComponents(year: 2026,month: 3,day: 15,hour: 0,minute: 1))!
        #expect(AgeRules(calendar: calendar).displayAge(for: .exact(CivilDate(year: 2026,month: 2,day: 15)),on: date) == "1 month")
    }
}
@Suite("Initial child surname suggestion") struct ChildSurnameTests {
    @Test("Only a fresh child uses its source person's complete surname")
    func source() {
        let parent = Person(firstName: "Synthetic",lastName: "Vale-Smith de Test")
        let other = Person(lastName: "Other")
        let draft = PersonDraftDefaults.newPerson(relationship: .child(of: parent.id,parentage: .unspecified),people: [other,parent])
        #expect(draft.lastName == parent.lastName && draft.firstName == nil && draft.connections.isEmpty)
        #expect(draft.revision == 0 && draft.reference == 0)
        #expect(PersonDraftDefaults.newPerson(relationship: .parent(of: parent.id,parentage: .step),people: [parent]).lastName == nil)
        #expect(PersonDraftDefaults.newPerson(relationship: .partner(of: parent.id,status: .current),people: [parent]).lastName == nil)
        #expect(PersonDraftDefaults.newPerson(relationship: nil,people: [parent]).lastName == nil)
        let blank = Person(lastName: "  ")
        #expect(PersonDraftDefaults.newPerson(relationship: .child(of: blank.id,parentage: .biological),people: [blank]).lastName == nil)
    }
}
