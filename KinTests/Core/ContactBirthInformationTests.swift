import Foundation
import Testing
@testable import Kin

@Suite("Contacts civil birth information") struct ContactBirthInformationTests {
    private let today = CivilDate(year: 2026, month: 10, day: 15)
    @Test("Complete Gregorian birthday is a civil date independent of component timezone", arguments: [-43200, 0, 50400])
    func civil(seconds: Int) {
        var parts = DateComponents(year: 2008, month: 10, day: 15)
        parts.timeZone = TimeZone(secondsFromGMT: seconds)
        #expect(ContactBirthInformation.resolve(gregorian: parts, alternate: nil, today: today) == .exact(CivilDate(year: 2008, month: 10, day: 15)))
    }
    @Test("Missing and yearless dates never acquire a year") func missing() {
        #expect(ContactBirthInformation.resolve(gregorian: nil, alternate: nil, today: today) == .missing)
        #expect(ContactBirthInformation.resolve(gregorian: DateComponents(month: 2, day: 29), alternate: nil, today: today) == .yearless)
        #expect(ContactBirthInformation.resolve(gregorian: DateComponents(year: NSDateComponentUndefined, month: 1, day: 1), alternate: nil, today: today) == .yearless)
    }
    @Test("Invalid, normalized, incomplete, future and overflowing components are rejected", arguments: [DateComponents(year: 2025,month: 2,day: 29), DateComponents(year: 1980,month: 13,day: 1), DateComponents(year: 1980,month: 1), DateComponents(year: 2026,month: 10,day: 16), DateComponents(year: Int.max - 1,month: 1,day: 1), DateComponents(era: 0,year: 1980,month: 1,day: 1)])
    func invalid(parts: DateComponents) {
        #expect(ContactBirthInformation.resolve(gregorian: parts, alternate: nil, today: today) == .invalid)
    }
    @Test("Leap day and today are accepted without normalization") func leap() {
        #expect(ContactBirthInformation.resolve(gregorian: DateComponents(year: 2000,month: 2,day: 29),alternate: nil,today: today) == .exact(CivilDate(year: 2000,month: 2,day: 29)))
        #expect(ContactBirthInformation.resolve(gregorian: DateComponents(year: 2026,month: 10,day: 15),alternate: nil,today: today) == .exact(today))
    }
    @Test("Alternate calendar is converted using its own era and components", arguments: [Calendar.Identifier.buddhist, .hebrew, .japanese, .chinese])
    func alternate(identifier: Calendar.Identifier) {
        let expected = CivilDate(year: 1980,month: 3,day: 8)
        var calendar = Calendar(identifier: identifier); calendar.timeZone = TimeZone(secondsFromGMT: 50400)!
        // Derive source civil components in UTC, then attach a foreign device timezone.
        var sourceCalendar = calendar; sourceCalendar.timeZone = CivilDate.pickerCalendar.timeZone
        var parts = sourceCalendar.dateComponents([.era,.year,.month,.day,.isLeapMonth],from: expected.pickerDate)
        parts.calendar = calendar; parts.timeZone = calendar.timeZone
        #expect(ContactBirthInformation.resolve(gregorian: nil,alternate: parts,today: today) == .exact(expected))
    }
    @Test("Ambiguous alternate calendars and Japanese eras require clarification") func ambiguous() {
        #expect(ContactBirthInformation.resolve(gregorian: nil,alternate: DateComponents(year: 40,month: 1,day: 1),today: today) == .ambiguousCalendar)
        var japanese = DateComponents(year: 40,month: 1,day: 1); japanese.calendar = Calendar(identifier: .japanese)
        #expect(ContactBirthInformation.resolve(gregorian: nil,alternate: japanese,today: today) == .ambiguousCalendar)
    }
    @Test("Canonical Gregorian date takes precedence; invalid dates do not silently switch calendars") func precedence() {
        var alternate = DateComponents(year: 2523,month: 1,day: 1); alternate.calendar = Calendar(identifier: .buddhist)
        #expect(ContactBirthInformation.resolve(gregorian: DateComponents(year: 2000,month: 1,day: 1),alternate: alternate,today: today) == .exact(CivilDate(year: 2000,month: 1,day: 1)))
        #expect(ContactBirthInformation.resolve(gregorian: DateComponents(month: 1,day: 1),alternate: alternate,today: today) == .exact(CivilDate(year: 1980,month: 1,day: 1)))
        #expect(ContactBirthInformation.resolve(gregorian: DateComponents(year: 3000,month: 1,day: 1),alternate: alternate,today: today) == .invalid)
    }
    @Test("Chinese leap months require explicit disambiguation") func chineseLeapMonth() {
        var calendar = Calendar(identifier: .chinese); calendar.timeZone = CivilDate.pickerCalendar.timeZone
        // These two civil dates have the same lunar year and numbered month.
        let ordinary = CivilDate(year: 2023,month: 2,day: 20), leap = CivilDate(year: 2023,month: 3,day: 22)
        for expected in [ordinary,leap] {
            var parts = calendar.dateComponents([.era,.year,.month,.day,.isLeapMonth],from: expected.pickerDate)
            parts.calendar = calendar
            #expect(ContactBirthInformation.resolve(gregorian: nil,alternate: parts,today: today) == .exact(expected))
            parts.isLeapMonth = nil
            #expect(ContactBirthInformation.resolve(gregorian: nil,alternate: parts,today: today) == .ambiguousCalendar)
        }
    }

}
