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
    /// Render the stored civil day; a device calendar or UTC+14 timezone must
    /// never reinterpret the noon-UTC picker bridge as a different birthday.
    func formatted(locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Self.pickerCalendar
        formatter.timeZone = Self.pickerCalendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: pickerDate)
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
