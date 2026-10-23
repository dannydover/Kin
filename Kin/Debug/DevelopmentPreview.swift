#if DEBUG
import Foundation
import CoreData
import SwiftUI

/// Synthetic, memory-only fixture for age/layout regressions. Never opens a notebook.
@MainActor enum DevelopmentPreview {
    static func relationshipNotebook(onlySource: Bool = false, failDeletion: Bool = false) throws -> KinStore {
        let store = try KinStore(inMemory: true,saveContext: { context in
            if failDeletion && !context.deletedObjects.isEmpty { throw CocoaError(.fileWriteNoPermission) }
            try context.save()
        })
        try store.savePerson(Person(firstName: "Synthetic Source",connections: [.friend]))
        if onlySource { return store }
        try store.savePerson(Person(firstName: "Synthetic Alex Example"))
        try store.savePerson(Person(firstName: "Synthetic Alex Example",birthday: .exact(CivilDate(year: 1990,month: 1,day: 1))))
        try store.savePerson(Person(firstName: "Synthetic Blair Example"))
        try store.savePerson(Person(firstName: "Synthetic Casey Example",connections: [.friend]))
        return store
    }
    static func relationshipActionsNotebook() throws -> KinStore {
        let store = try relationshipNotebook()
        let source = store.people.first { $0.firstName == "Synthetic Source" }!
        let parent = store.people.first { $0.reference == 3 }!
        let child = store.people.first { $0.firstName == "Synthetic Blair Example" }!
        let partner = store.people.first { $0.firstName == "Synthetic Casey Example" }!
        try store.saveParentLink(ParentLink(parentID: parent.id,childID: source.id,parentage: .step))
        try store.saveParentLink(ParentLink(parentID: source.id,childID: child.id,parentage: .adoptive))
        try store.savePartnerLink(PartnerLink(firstID: source.id,secondID: partner.id,status: .former))
        return store
    }
    static func importPreservationNotebook() throws -> KinStore {
        let store = try KinStore(inMemory: true)
        for (name,birthday): (String,Birthday) in [
            ("Synthetic Exact",.exact(CivilDate(year: 1980,month: 3,day: 14))),
            ("Synthetic Estimate",.estimated(age: 40,referenceDate: CivilDate(year: 2026,month: 10,day: 15))),
            ("Synthetic Unknown",.unknown)] {
            var person = Person(firstName: name,birthday: birthday,connections: [.friend])
            person.notes = "Synthetic preserved note"
            try store.savePerson(person)
        }
        return store
    }
    static func babyNotebook(today: Date = Date()) throws -> KinStore {
        let store = try KinStore(inMemory: true)
        let parent = Person(firstName: "Synthetic Parent",birthday: .exact(CivilDate(year: 1980,month: 1,day: 1)),connections: [.friend])
        try store.savePerson(parent,today: today)
        let day = CivilDate(today,timeZone: .current).pickerDate
        let fixtures: [(String,Int?)] = [("Synthetic Unknown",nil),("Synthetic Newborn",0),
            ("Synthetic One Month",1),("Synthetic Eleven Months",11),
            ("Synthetic Twelve Months",12),("Synthetic Twenty-Three Months",23)]
        for (name,months) in fixtures {
            let birthday: Birthday
            if let months {
                let date = CivilDate.pickerCalendar.date(byAdding: .month,value: -months,to: day)!
                birthday = .exact(CivilDate(date,timeZone: CivilDate.pickerCalendar.timeZone))
            } else { birthday = .unknown }
            try store.savePerson(Person(firstName: name,birthday: birthday),today: today,
                                 relationship: .child(of: parent.id,parentage: .unspecified))
        }
        return store
    }
}
/// The real action on its real row surface, without unrelated profile elements.
struct RelationshipActionAuditPreview: View {
    var body: some View {
        List {
            RelationshipEditAction(personName: "Synthetic Example", action: {})
                .listRowBackground(KinTheme.editableFormRow)
        }.kinForm()
    }
}
#endif
