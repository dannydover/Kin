import Foundation

enum LifeStage: String, CaseIterable, Codable, Sendable {
    case baby, toddler, youngKid, olderKid, teen, adult
    static func forAge(_ age: Int) -> Self {
        switch age { case ..<2: .baby; case 2..<5: .toddler; case 5..<10: .youngKid; case 10..<13: .olderKid; case 13..<18: .teen; default: .adult }
    }
}
// Confirmed display policy. Storage, year calculations and photo eligibility stay independent.
enum BabyAgePresentation {
    static let monthsBeforeAge = 1
    static let newbornLabel = "Less than 1 month"
}
struct AgeRules: Sendable {
    let calendar: Calendar
    init(calendar: Calendar) { self.calendar = CivilDate.gregorian(in: calendar.timeZone) }
    static let estimatedAgeRange = 0...120
    private func years(from start: CivilDate, to end: CivilDate) -> Int {
        end.year - start.year - ((end.month, end.day) < (start.month, start.day) ? 1 : 0)
    }
    // This is an interval of possible birthdays, never a fabricated birthday.
    private func birthBounds(_ birthday: Birthday) -> (CivilDate, CivilDate)? {
        switch birthday {
        case .unknown: return nil
        case .exact(let day): return day.isValid ? (day, day) : nil
        case .estimated(let age, let reference):
            guard reference.isValid, Self.estimatedAgeRange.contains(age), reference.year > age + 1 else { return nil }
            let cal = CivilDate.pickerCalendar
            guard let oldest = cal.date(byAdding: .year, value: -age - 1, to: reference.pickerDate),
                  let earliest = cal.date(byAdding: .day, value: 1, to: oldest),
                  let latest = cal.date(byAdding: .year, value: -age, to: reference.pickerDate) else { return nil }
            return (CivilDate(earliest, timeZone: cal.timeZone), CivilDate(latest, timeZone: cal.timeZone))
        }
    }
    func ageRange(for birthday: Birthday, on date: Date) -> ClosedRange<Int>? {
        guard let (earliest, latest) = birthBounds(birthday) else { return nil }
        let today = CivilDate(date, timeZone: calendar.timeZone)
        guard today.isValid, latest <= today else { return nil }
        return max(0, years(from: latest, to: today))...max(0, years(from: earliest, to: today))
    }
    func age(for birthday: Birthday, on date: Date) -> Int? {
        guard birthday.isStructurallyValid else { return nil }
        switch birthday {
        case .unknown: return nil
        case .exact: return ageRange(for: birthday, on: date)?.lowerBound
        case .estimated(let age, let reference):
            let today = CivilDate(date, timeZone: calendar.timeZone)
            guard today.isValid, reference <= today else { return nil }
            let result = age.addingReportingOverflow(max(0, years(from: reference, to: today)))
            return result.overflow ? nil : result.partialValue
        }
    }
    func displayAge(for birthday: Birthday, on date: Date) -> String {
        guard let age = age(for: birthday, on: date) else { return "Age unknown" }
        if case .exact(let birth) = birthday, age < BabyAgePresentation.monthsBeforeAge {
            let today = CivilDate(date, timeZone: calendar.timeZone)
            var months = (today.year - birth.year) * 12 + today.month - birth.month
            // Calendar anniversaries clamp month-end births to the last valid day.
            // Recompute from the original birthday so February never shifts March.
            if let anniversary = CivilDate.pickerCalendar.date(byAdding: .month, value: months, to: birth.pickerDate),
               CivilDate(anniversary, timeZone: CivilDate.pickerCalendar.timeZone) > today { months -= 1 }
            // Keep the existing March-first leap-day year transition authoritative.
            months = min(months, BabyAgePresentation.monthsBeforeAge * 12 - 1)
            return months == 0 ? BabyAgePresentation.newbornLabel : "\(months) \(months == 1 ? "month" : "months")"
        }
        return "\(birthday.isEstimated ? "~" : "")\(age) \(age == 1 ? "year" : "years")"
    }
    // Profile presentation only; this never changes stored relationship records.
    func showsPartnerAndChildSections(for birthday: Birthday, on date: Date) -> Bool {
        guard let age = age(for: birthday, on: date) else { return true }
        return age >= 16
    }
    func allowsPhoto(_ birthday: Birthday, on date: Date) -> Bool {
        guard birthday.isStructurallyValid, let range = ageRange(for: birthday, on: date) else { return false }
        return range.lowerBound >= 18 && (age(for: birthday, on: date) ?? 0) >= 18
    }
    func grade(for birthday: Birthday, on date: Date) -> String? {
        guard let age = age(for: birthday, on: date), (5..<18).contains(age), let (_, latest) = birthBounds(birthday) else { return nil }
        let today = CivilDate(date, timeZone: calendar.timeZone)
        let cutoff = CivilDate(year: today.year - (today.month < 9 ? 1 : 0), month: 9, day: 1)
        let schoolAge = years(from: latest, to: cutoff)
        let grades = ["Kindergarten", "1st Grade", "2nd Grade", "3rd Grade", "4th Grade", "5th Grade", "6th Grade", "7th Grade", "8th Grade", "9th Grade", "10th Grade", "11th Grade", "12th Grade"]
        guard (5...17).contains(schoolAge) else { return nil }
        return (birthday.isEstimated ? "~" : "") + grades[schoolAge - 5]
    }
    func validate(_ birthday: Birthday, on date: Date) throws {
        let today = CivilDate(date, timeZone: calendar.timeZone)
        switch birthday {
        case .unknown: return
        case .exact(let birth):
            guard birth.isValid, birth <= today else { throw KinError.invalidBirthday }
        case .estimated(let age, let reference):
            guard reference.isValid, reference <= today, Self.estimatedAgeRange.contains(age), birthBounds(birthday) != nil else { throw KinError.invalidBirthday }
        }
    }
}
