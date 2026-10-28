import SwiftUI

/// Keep exact control/screen names localizable and semibold inside a single
/// localized sentence. Text interpolation preserves reading order and avoids
/// exposing literal Markdown or splitting a sentence into accessibility items.
enum FeatureReference {
    static var people: Text { Text("People").fontWeight(.semibold) }
    static var allPeople: Text { Text("All people").fontWeight(.semibold) }
    static var showOnMainList: Text { Text("Show on main list").fontWeight(.semibold) }
    static var clearSearchAndFilters: Text { Text("Clear search and filters").fontWeight(.semibold) }
    static var edit: Text { Text("Edit").fontWeight(.semibold) }
    static var editPerson: Text { Text("Edit person").fontWeight(.semibold) }
    static var save: Text { Text("Save").fontWeight(.semibold) }
    static var cancel: Text { Text("Cancel").fontWeight(.semibold) }
    static var importAction: Text { Text("Import").fontWeight(.semibold) }
    static var importAndSave: Text { Text("Import and Save").fontWeight(.semibold) }
    static var includeContactsPhoto: Text { Text("Include eligible Contacts photo").fontWeight(.semibold) }
    static var friend: Text { Text("Friend").fontWeight(.semibold) }
    static var family: Text { Text("Family").fontWeight(.semibold) }
    static var colleague: Text { Text("Colleague").fontWeight(.semibold) }
}

enum FeatureHelp {
    static var newLinkedPerson: Text {
        Text("After saving, find this person in linked profiles or on the \(FeatureReference.allPeople) screen. To also show them on your main list, turn on the \(FeatureReference.showOnMainList) setting.")
    }
    static var listInclusion: Text {
        Text("Use the \(FeatureReference.showOnMainList) setting to include this person on the \(FeatureReference.people) screen. Categories are optional and don’t change list inclusion. Find this person on the \(FeatureReference.allPeople) screen or in linked profiles.")
    }
    static var directPerson: Text {
        Text("\(FeatureReference.friend), \(FeatureReference.family) and \(FeatureReference.colleague) are optional categories. This person stays on the \(FeatureReference.people) screen even if you don’t choose a category.")
    }
}
