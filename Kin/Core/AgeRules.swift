import Foundation

enum LifeStage: String, CaseIterable, Codable, Sendable {
    case baby, toddler, youngKid, olderKid, teen, adult
    static func forAge(_ age: Int) -> Self {
        switch age {
        case ..<2: .baby
        case 2..<5: .toddler
        case 5..<10: .youngKid
        case 10..<13: .olderKid
        case 13..<18: .teen
        default: .adult
        }
    }
}
enum KinError: LocalizedError, Equatable {
    case dateReviewRequired, invalidName, invalidBirthday, missingFriend, invalidPartner, invalidChildSelection, replacementRequired(String), invalidData
    var errorDescription: String? {
        switch self {
        case .dateReviewRequired: "Review and confirm this date before saving. The earlier entry did not record its timezone."
        case .invalidName: "Enter a first and last name."
        case .invalidBirthday: "Use a birthday or reference date on or before today, and an age from 0 to 120."
        case .missingFriend: "This friend is no longer available."
        case .invalidPartner: "Choose a partner from this friend’s family."
        case .replacementRequired(let name): "Replace \(name) as current partner?"
        case .invalidData: "Kin couldn’t read the saved family data. Your data has not been reset."
        case .invalidChildSelection: "This family has changed. Cancel and reopen the partner to review the children before saving."
        }
    }
}
struct AgeRules: Sendable {
    let calendar: Calendar
    init(calendar: Calendar) {
        // The device timezone defines today; its preferred calendar never redefines July or September.
        self.calendar = CivilDate.gregorian(in: calendar.timeZone)
    }
    func birthDate(for birthday: Birthday) -> CivilDate? {
        switch birthday {
        case .exact(let date): return date.isValid ? date : nil
        case .estimated(let age, let reference):
            guard reference.isValid, (0...120).contains(age) else { return nil }
            let year = reference.year - age - (reference.month < 7 ? 1 : 0)
            let date = CivilDate(year: year, month: 7, day: 1)
            return date.isValid ? date : nil
        case .legacyExact, .legacyEstimated: return nil
        }
    }
    private func years(from birth: CivilDate, to today: CivilDate) -> Int {
        max(0, today.year - birth.year - ((today.month, today.day) < (birth.month, birth.day) ? 1 : 0))
    }
    func age(for birthday: Birthday, on date: Date) -> Int? {
        guard let birth = birthDate(for: birthday) else { return nil }
        return years(from: birth, to: CivilDate(date, timeZone: calendar.timeZone))
    }
    func displayAge(for birthday: Birthday, on date: Date) -> String {
        guard let age = age(for: birthday, on: date) else { return "Review date" }
        return "\(birthday.isEstimated ? "~" : "")\(age)"
    }
    func grade(for birthday: Birthday, on date: Date) -> String? {
        guard let currentAge = age(for: birthday, on: date), (5..<18).contains(currentAge),
              let birth = birthDate(for: birthday) else { return nil }
        let today = CivilDate(date, timeZone: calendar.timeZone)
        let cutoff = CivilDate(year: today.year - (today.month < 9 ? 1 : 0), month: 9, day: 1)
        let schoolAge = years(from: birth, to: cutoff)
        let grades = ["Kindergarten", "1st Grade", "2nd Grade", "3rd Grade", "4th Grade", "5th Grade", "6th Grade", "7th Grade", "8th Grade", "9th Grade", "10th Grade", "11th Grade", "12th Grade"]
        guard (5...17).contains(schoolAge) else { return nil }
        return grades[schoolAge - 5]
    }
    func validate(_ birthday: Birthday, on date: Date) throws {
        let today = CivilDate(date, timeZone: calendar.timeZone)
        switch birthday {
        case .exact(let birth):
            guard birth.isValid, birth <= today, years(from: birth, to: today) <= 120 else { throw KinError.invalidBirthday }
        case .estimated(let age, let reference):
            guard reference.isValid, (0...120).contains(age), reference <= today, birthDate(for: birthday) != nil else { throw KinError.invalidBirthday }
        case .legacyExact, .legacyEstimated: throw KinError.dateReviewRequired
        }
    }
}
