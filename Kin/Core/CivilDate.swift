import Foundation

/// A Gregorian date, not an instant. Travel and device calendar preferences cannot alter it.
struct CivilDate: Codable, Equatable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }
    init(_ instant: Date, timeZone: TimeZone) {
        let parts = Self.gregorian(in: timeZone).dateComponents([.year, .month, .day], from: instant)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }
    static func gregorian(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
    static var pickerCalendar: Calendar { gregorian(in: TimeZone(secondsFromGMT: 0)!) }
    var isValid: Bool {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              let instant = Self.pickerCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else { return false }
        return CivilDate(instant, timeZone: Self.pickerCalendar.timeZone) == self
    }
    /// Noon UTC is only a bridge to the Gregorian/UTC-configured DatePicker, never storage.
    var pickerDate: Date {
        Self.pickerCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
    private enum CodingKeys: String, CodingKey { case year, month, day }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        year = try values.decode(Int.self, forKey: .year)
        month = try values.decode(Int.self, forKey: .month)
        day = try values.decode(Int.self, forKey: .day)
        guard isValid else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid Gregorian civil date")) }
    }
}

enum Birthday: Equatable, Sendable {
    case exact(CivilDate)
    case estimated(age: Int, referenceDate: CivilDate)
    // Preserve old instants losslessly until the user confirms the intended civil date.
    case legacyExact(Date)
    case legacyEstimated(age: Int, referenceDate: Date)

    var requiresDateReview: Bool {
        switch self { case .legacyExact, .legacyEstimated: true; default: false }
    }
    var isEstimated: Bool {
        switch self { case .estimated, .legacyEstimated: true; default: false }
    }
    /// UTC is an explicitly disclosed starting suggestion, not an inferred original timezone.
    var editingSuggestion: Birthday {
        switch self {
        case .legacyExact(let instant): .exact(CivilDate(instant, timeZone: CivilDate.pickerCalendar.timeZone))
        case .legacyEstimated(let age, let instant): .estimated(age: age, referenceDate: CivilDate(instant, timeZone: CivilDate.pickerCalendar.timeZone))
        default: self
        }
    }
}
extension Birthday: Codable {
    private enum Keys: String, CodingKey { case schemaVersion, kind, date, age, exact, estimated }
    private enum LegacyKeys: String, CodingKey { case _0, age, referenceDate }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        if values.contains(.schemaVersion) {
            guard try values.decode(Int.self, forKey: .schemaVersion) == 2 else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported birthday schema; data preserved"))
            }
            let date = try values.decode(CivilDate.self, forKey: .date)
            switch try values.decode(String.self, forKey: .kind) {
            case "exact": self = .exact(date)
            case "estimated":
                let age = try values.decode(Int.self, forKey: .age)
                guard (0...120).contains(age) else { throw KinError.invalidBirthday }
                self = .estimated(age: age, referenceDate: date)
            default: throw KinError.invalidData
            }
        } else if values.contains(.exact) && !values.contains(.estimated) {
            let old = try values.nestedContainer(keyedBy: LegacyKeys.self, forKey: .exact)
            self = .legacyExact(try old.decode(Date.self, forKey: ._0))
        } else if values.contains(.estimated) && !values.contains(.exact) {
            let old = try values.nestedContainer(keyedBy: LegacyKeys.self, forKey: .estimated)
            self = .legacyEstimated(age: try old.decode(Int.self, forKey: .age), referenceDate: try old.decode(Date.self, forKey: .referenceDate))
        } else { throw KinError.invalidData }
    }
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        switch self {
        case .exact(let date):
            try values.encode(2, forKey: .schemaVersion); try values.encode("exact", forKey: .kind)
            try values.encode(date, forKey: .date)
        case .estimated(let age, let reference):
            try values.encode(2, forKey: .schemaVersion); try values.encode("estimated", forKey: .kind)
            try values.encode(reference, forKey: .date); try values.encode(age, forKey: .age)
        case .legacyExact(let instant):
            var old = values.nestedContainer(keyedBy: LegacyKeys.self, forKey: .exact)
            try old.encode(instant, forKey: ._0)
        case .legacyEstimated(let age, let instant):
            var old = values.nestedContainer(keyedBy: LegacyKeys.self, forKey: .estimated)
            try old.encode(age, forKey: .age); try old.encode(instant, forKey: .referenceDate)
        }
    }
}
