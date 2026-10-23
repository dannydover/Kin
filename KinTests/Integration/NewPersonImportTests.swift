import Foundation
import CoreData
import Testing
import UIKit
@testable import Kin

@Suite("Atomic new Contacts person confirmation") @MainActor struct NewPersonImportTests {
    @Test("Every entry point saves once with its reviewed relationship and category", arguments: [0,1,2,3])
    func entryPoints(_ route: Int) throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        let source = Person(firstName: "Synthetic source"); try store.savePerson(source)
        let relationship: NewRelationship? = switch route {
        case 1: .parent(of: source.id,parentage: .step)
        case 2: .child(of: source.id,parentage: .adoptive)
        case 3: .partner(of: source.id,status: .former)
        default: nil
        }
        var draft = Person(firstName: " Reviewed ",lastName: " Vale-Smith ",connections: [])
        draft.notes = "Synthetic notes"
        let commit = NewContactImportCommit()
        try commit.save(draft,store: store,relationship: relationship)
        try commit.save(draft,store: store,relationship: relationship)
        #expect(store.people.count == 2)
        let saved = try store.person(draft.id)
        #expect(saved.firstName == "Reviewed" && saved.lastName == "Vale-Smith" && saved.notes == draft.notes)
        #expect(saved.connections == draft.connections && saved.isListed == (route == 0))
        #expect(store.parentLinks.count == (route == 1 || route == 2 ? 1 : 0))
        #expect(store.partnerLinks.count == (route == 3 ? 1 : 0))
        if route == 1 { #expect(store.parentLinks.first?.parentage == .step) }
        if route == 2 { #expect(store.parentLinks.first?.parentage == .adoptive) }
        if route == 3 { #expect(store.partnerLinks.first?.status == .former) }
    }
    @Test("Failed save retains review identity; retry is atomic, including after commit", arguments: [false,true])
    func failure(_ afterCommit: Bool) throws {
        var fail = false
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try KinStore(storeURL: directory.appendingPathComponent("import.sqlite"),saveContext: { context in
            if fail && !afterCommit { throw CocoaError(.fileWriteNoPermission) }
            try context.save()
            if fail && afterCommit { throw CocoaError(.fileWriteNoPermission) }
        }); defer { try? store.close() }
        let source = Person(); try store.savePerson(source)
        let draft = Person(firstName: " Reviewed ",lastName: " ")
        let commit = NewContactImportCommit()
        fail = true
        #expect(throws: (any Error).self) { try commit.save(draft,store: store,relationship: .child(of: source.id,parentage: .unspecified)) }
        #expect(commit.completedID == nil)
        #expect(!store.isReady && store.isClosed)
        fail = false
        try store.resume()
        #expect(store.people.count == (afterCommit ? 2 : 1))
        #expect(store.parentLinks.count == (afterCommit ? 1 : 0))
        try commit.save(draft,store: store,relationship: .child(of: source.id,parentage: .unspecified))
        try commit.save(draft,store: store,relationship: .child(of: source.id,parentage: .unspecified))
        #expect(store.people.count == 2 && store.parentLinks.count == 1)
    }
    @Test("Validation and missing relationship endpoints leave no partial person")
    func validation() throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        let commit = NewContactImportCommit()
        #expect(throws: (any Error).self) { try commit.save(Person(),store: store,relationship: .child(of: UUID(),parentage: .unspecified)) }
        #expect(throws: KinError.invalidName) { try commit.save(Person(firstName: String(repeating: "x",count: 201),connections: [.family]),store: store,relationship: nil) }
        #expect(store.people.isEmpty && store.parentLinks.isEmpty && commit.completedID == nil)
        let existing = Person(firstName: "Saved",connections: [.friend]); try store.savePerson(existing)
        var edit = try store.person(existing.id); edit.firstName = "Must not replace"
        #expect(throws: KinError.staleEdit) { try commit.save(edit,store: store,relationship: nil) }
        #expect(try store.person(existing.id).firstName == "Saved")
    }
    @Test("Direct import without categories is visible after failure and explicit retry", arguments: [false,true])
    func directFailure(_ afterCommit: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var fail = true
        let store = try KinStore(storeURL: directory.appendingPathComponent("direct.sqlite"),saveContext: { context in
            if fail && !afterCommit { throw CocoaError(.fileWriteNoPermission) }
            try context.save()
            if fail && afterCommit { throw CocoaError(.fileWriteNoPermission) }
        }); defer { try? store.close() }
        let draft = Person(firstName: "Synthetic Imported")
        let commit = NewContactImportCommit()
        #expect(throws: (any Error).self) { try commit.save(draft,store: store,relationship: nil) }
        #expect(commit.completedID == nil)
        fail = false; try store.resume()
        try commit.save(draft,store: store,relationship: nil)
        try commit.save(draft,store: store,relationship: nil)
        #expect(store.people.count == 1 && store.people.first?.id == draft.id)
        #expect(PeopleIndex.results(store.people,query: "").count == 1)
        #expect(store.people.first?.connections.isEmpty == true)
    }
    @Test("Helper and relationship action inks meet 4.5 to 1 in appearance and contrast variants")
    func contrast() throws {
        func luminance(_ color: UIColor) -> Double {
            var r: CGFloat = 0,g: CGFloat = 0,b: CGFloat = 0,a: CGFloat = 0
            color.getRed(&r,green: &g,blue: &b,alpha: &a)
            return zip([Double(r),Double(g),Double(b)],[0.2126,0.7152,0.0722]).reduce(0) { sum,pair in
                let value = pair.0 <= 0.04045 ? pair.0 / 12.92 : pow((pair.0 + 0.055) / 1.055,2.4)
                return sum + value * pair.1
            }
        }
        let background = try #require(UIColor(named: "KinBackground"))
        let accent = try #require(UIColor(named: "KinAccent"))
        for style in [UIUserInterfaceStyle.light,.dark] {
            for contrast in [UIAccessibilityContrast.normal,.high] {
                let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: style), UITraitCollection(accessibilityContrast: contrast)])
                let ink = luminance(KinTheme.helperInk.resolvedColor(with: traits))
                let surface = luminance(background.resolvedColor(with: traits))
                #expect((max(ink,surface)+0.05)/(min(ink,surface)+0.05) >= 4.5)
                let button = luminance(accent.resolvedColor(with: traits))
                // Profile actions use clay ink on the actual elevated row surface.
                // Native bordered-fill appearance is checked in synthetic UI renders.
                let rowTraits = traits.modifyingTraits {
                    // NotebookRoot explicitly prefers dark appearance.
                    $0.userInterfaceStyle = .dark; $0.userInterfaceLevel = .elevated
                }
                let row = luminance(UIColor.secondarySystemGroupedBackground.resolvedColor(with: rowTraits))
                #expect((max(button,row)+0.05)/(min(button,row)+0.05) >= 4.5)
            }
        }
    }
}
