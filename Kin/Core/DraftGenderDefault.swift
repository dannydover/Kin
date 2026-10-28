import Foundation

/// Ephemeral draft intent; no stored Person or existing record is inferred again.
struct DraftGenderDefault {
    private(set) var value: Gender
    private(set) var isAutomatic: Bool
    init(value: Gender = .unknown, isNew: Bool, manuallyChosen: Bool = false) {
        self.value = value; isAutomatic = isNew && !manuallyChosen
    }
    mutating func nameChanged(_ name: String, lookup: (String) -> Gender) {
        if isAutomatic { value = lookup(name) }
    }
    mutating func choose(_ gender: Gender) { value = gender; isAutomatic = false }
}
