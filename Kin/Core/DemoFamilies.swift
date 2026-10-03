#if DEBUG
import Foundation
/// Fictional fixtures. Never loaded during ordinary launch or in Release builds.
enum DemoFamilies {
    static func make(on today: Date, calendar: Calendar) -> [Friend] {
        let calendar = CivilDate.gregorian(in: calendar.timeZone)
        func birthday(_ age: Int) -> Birthday { .exact(CivilDate(calendar.date(byAdding: .year, value: -age, to: today)!, timeZone: calendar.timeZone)) }
        let mira = Partner(firstName: "Mira", lastName: "Vale", gender: .female)
        let jules = Partner(firstName: "Jules", lastName: "Ash", gender: .unknown, isCurrent: false)
        let quinn = Partner(firstName: "Quinn", lastName: "Birch", gender: .male, isCurrent: false)
        let rowan = Friend(firstName: "Rowan", lastName: "Vale", notes: "Met at the neighborhood pottery class. Ask about the garden next time.", partners: [mira, jules, quinn], children: [
            Child(firstName: "Ari", lastName: "Vale", gender: .male, notes: "Building a cardboard rocket.", birthday: birthday(7), partnerID: mira.id),
            Child(firstName: "Wren", lastName: "Vale", gender: .female, birthday: .estimated(age: 3, referenceDate: CivilDate(today, timeZone: calendar.timeZone)), partnerID: mira.id),
            Child(firstName: "Kit", lastName: "Ash", gender: .unknown, notes: "Learning the guitar.", birthday: birthday(14), partnerID: jules.id)
        ])
        let eloise = Friend(firstName: "Éloise", lastName: "Willow", children: [Child(firstName: "Robin", lastName: "Willow", birthday: birthday(0)), Child(firstName: "Finch", lastName: "Willow", gender: .male, birthday: birthday(11))])
        let noa = Friend(firstName: "Noa", lastName: "Fern", children: [Child(firstName: "Sage", lastName: "Fern", gender: .female, birthday: birthday(19))])
        return [rowan, eloise, noa]
    }
}
#endif
