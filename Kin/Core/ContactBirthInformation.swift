import Foundation

/// Contacts dates are civil components. Never let Foundation fill a missing year,
/// normalize an invalid day, or select a current era for an ambiguous calendar.
enum ContactBirthInformation: Equatable {
    case exact(CivilDate), missing, unavailable, yearless, invalid, ambiguousCalendar

    static func resolve(gregorian: DateComponents?, alternate: DateComponents?, today: CivilDate) -> Self {
        if let gregorian {
            let result = resolve(gregorian, requiresCalendar: false, today: today)
            // A yearless Gregorian reminder does not discard a fully recorded
            // alternate-calendar birth date. Never repair an invalid full date.
            if result == .yearless, let alternate {
                let other = resolve(alternate, requiresCalendar: true, today: today)
                if case .exact = other { return other }
            }
            return result
        }
        if let alternate { return resolve(alternate, requiresCalendar: true, today: today) }
        return .missing
    }

    private static func resolve(_ components: DateComponents, requiresCalendar: Bool, today: CivilDate) -> Self {
        guard let year = components.year, year != NSDateComponentUndefined else { return .yearless }
        guard let month = components.month, let day = components.day,
              year > 0, year < 10000, month > 0, month <= 13, day > 0, day <= 31 else { return .invalid }
        guard !requiresCalendar || components.calendar != nil else { return .ambiguousCalendar }
        var calendar = components.calendar ?? CivilDate.pickerCalendar
        calendar.timeZone = CivilDate.pickerCalendar.timeZone
        if [.japanese, .chinese].contains(calendar.identifier), components.era == nil { return .ambiguousCalendar }
        if calendar.identifier == .chinese, components.isLeapMonth == nil { return .ambiguousCalendar }
        if let era = components.era, !(0..<10000).contains(era) { return .invalid }
        if calendar.identifier == .gregorian, let era = components.era, era != 1 { return .invalid }
        var civil = DateComponents()
        civil.era = components.era; civil.year = year; civil.month = month; civil.day = day
        civil.isLeapMonth = components.isLeapMonth; civil.hour = 12
        guard let instant = calendar.date(from: civil) else { return .invalid }
        let roundTrip = calendar.dateComponents([.era, .year, .month, .day, .isLeapMonth], from: instant)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day,
              components.era == nil || components.era == roundTrip.era,
              components.isLeapMonth == nil || components.isLeapMonth == roundTrip.isLeapMonth else { return .invalid }
        guard CivilDate.pickerCalendar.component(.era, from: instant) == 1 else { return .invalid }
        let date = CivilDate(instant, timeZone: CivilDate.pickerCalendar.timeZone)
        guard date.isValid, date <= today else { return .invalid }
        return .exact(date)
    }

    var explanation: String {
        switch self {
        case .exact: "This contact has a birthday with a year."
        case .missing: "This contact doesn’t have a full birthday saved."
        case .unavailable: "Contacts didn’t share this person’s birthday with Kin. Enter their birthday or estimated age here, or continue without a photo."
        case .yearless: "This contact’s birthday has no year, so Kin can’t tell their age. The birthday stays in Contacts as it is."
        case .invalid: "Kin couldn’t use this birthday as written. Check that it’s a real date that isn’t in the future, or leave the age unknown."
        case .ambiguousCalendar: "Kin can’t tell the exact date from this contact’s calendar details. Check the birthday here or leave the age unknown."
        }
    }
}
