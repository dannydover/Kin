import Foundation
import CoreData
import Testing
@testable import Kin

@MainActor private final class ChildSelectionFailure { var enabled = false }
@Suite("Partner children checklist") @MainActor struct PartnerChildrenTests {
    private func fixture() -> Friend {
        let target = Partner(firstName: "Mira", lastName: "Vale")
        let other = Partner(firstName: "Jules", lastName: "Ash", isCurrent: false)
        return Friend(firstName: "Rowan", lastName: "Vale", notes: "Preserve notebook", partners: [target, other], children: [
            Child(firstName: "Ari", lastName: "Vale", notes: "Preserve note", birthday: .exact(civil(2020, 1, 1)), partnerID: target.id),
            Child(firstName: "Kit", lastName: "Ash", birthday: .exact(civil(2012, 1, 1)), partnerID: other.id),
            Child(firstName: "Wren", lastName: "Vale", birthday: .estimated(age: 3, referenceDate: civil(2026, 1, 1))),
            Child(firstName: "Finch", lastName: "Ash", birthday: .exact(civil(2015, 1, 1)), partnerID: other.id)
        ])
    }
    @Test("Selections initialize from links, describe reassignment and remain drafts on cancel")
    func draftAndCancellation() throws {
        let store = try KinStore(inMemory: true)
        let friend = fixture(); try store.saveFriend(friend)
        let before = store.friends
        var selection = PartnerChildSelection(friend: friend, partnerID: friend.partners[0].id)
        #expect(selection.selectedIDs == [friend.children[0].id])
        #expect(selection.options.map(\.name) == ["Ari Vale", "Finch Ash", "Kit Ash", "Wren Vale"])
        #expect(selection.options.first { $0.id == friend.children[1].id }?.association == "Currently linked to Jules Ash")
        #expect(selection.options.first { $0.id == friend.children[1].id }?.reassigns == true)
        #expect(selection.options.first { $0.id == friend.children[2].id }?.association == "No partner linked")
        selection.toggle(friend.children[0].id)
        selection.toggle(friend.children[1].id)
        selection.toggle(friend.children[2].id)
        selection.toggle(UUID())
        #expect(selection.selectedIDs == [friend.children[1].id, friend.children[2].id])
        try store.reload()
        #expect(store.friends == before)
        selection = PartnerChildSelection(friend: try store.friend(friend.id), partnerID: friend.partners[0].id)
        #expect(selection.selectedIDs == [friend.children[0].id])
    }
    @Test("Save selects several, deselects, reassigns and preserves unrelated links and grouping")
    func atomicSelection() throws {
        let store = try KinStore(inMemory: true)
        let friend = fixture(); try store.saveFriend(friend)
        let unrelated = fixture(); try store.saveFriend(unrelated)
        let unrelatedBefore = try store.friend(unrelated.id)
        var partner = friend.partners[0]; partner.firstName = "Mira Edited"
        let selected: Set<UUID> = [friend.children[1].id, friend.children[2].id]
        try store.savePartner(partner, friendID: friend.id, selectedChildIDs: selected)
        let saved = try store.friend(friend.id)
        #expect(saved.partners.contains(partner))
        #expect(saved.notes == friend.notes)
        for original in friend.children {
            var expected = original
            if selected.contains(original.id) { expected.partnerID = partner.id }
            else if original.partnerID == partner.id { expected.partnerID = nil }
            #expect(saved.children.first { $0.id == original.id } == expected)
        }
        #expect(try store.friend(unrelated.id) == unrelatedBefore)
        let grouped = FamilyLayout(friend: saved).groups.flatMap(\.children)
        #expect(grouped.count == friend.children.count)
        #expect(Set(grouped.map(\.id)) == Set(friend.children.map(\.id)))
        try store.savePartner(partner, friendID: friend.id, selectedChildIDs: [])
        #expect(try store.friend(friend.id).children.filter { $0.partnerID == partner.id }.isEmpty)
        #expect(try store.entityCount("ChildRecord") == 8)
    }
    @Test("Foreign children and removed partners are rejected without changing either family")
    func familyScoping() throws {
        let store = try KinStore(inMemory: true)
        let friend = fixture(); let unrelated = fixture()
        try store.saveFriend(friend); try store.saveFriend(unrelated)
        let before = store.friends
        #expect(throws: KinError.invalidChildSelection) {
            try store.savePartner(friend.partners[0], friendID: friend.id, selectedChildIDs: [unrelated.children[0].id])
        }
        #expect(throws: KinError.invalidChildSelection) {
            try store.savePartner(unrelated.partners[0], friendID: friend.id, selectedChildIDs: [])
        }
        try store.reload(); #expect(store.friends == before)
        let selection = PartnerChildSelection(friend: friend, partnerID: friend.partners[0].id)
        #expect(Set(selection.options.map(\.id)) == Set(friend.children.map(\.id)))
    }
    @Test("Current-partner confirmation delays both edits and selections")
    func replacementConfirmation() throws {
        let store = try KinStore(inMemory: true)
        let friend = fixture(); try store.saveFriend(friend)
        var partner = friend.partners[1]; partner.isCurrent = true
        let before = store.friends
        #expect(throws: KinError.replacementRequired(friend.partners[0].fullName)) {
            try store.savePartner(partner, friendID: friend.id, selectedChildIDs: [friend.children[0].id])
        }
        #expect(store.friends == before)
        try store.savePartner(partner, friendID: friend.id, replaceCurrent: true, selectedChildIDs: [friend.children[0].id])
        #expect(try store.friend(friend.id).currentPartner?.id == partner.id)
        #expect(try store.friend(friend.id).children.first { $0.id == friend.children[0].id }?.partnerID == partner.id)
    }
    @Test("Real save failure rolls back partner edits and all associations, then retry succeeds")
    func failedSaveRollback() throws {
        let failure = ChildSelectionFailure()
        let store = try KinStore(inMemory: true, saveContext: { context in
            if failure.enabled {
                context.insertedObjects.first { $0.entity.name == "ChildRecord" }?.setValue(nil, forKey: "payload")
            }
            try context.save()
        })
        let friend = fixture(); try store.saveFriend(friend)
        let before = store.friends
        var partner = friend.partners[0]; partner.lastName = "Updated"
        failure.enabled = true
        var failedInCoreData = false
        do { try store.savePartner(partner, friendID: friend.id, selectedChildIDs: [friend.children[1].id, friend.children[2].id]) }
        catch { failedInCoreData = (error as NSError).domain == NSCocoaErrorDomain }
        #expect(failedInCoreData)
        #expect(store.friends == before)
        try store.reload(); #expect(store.friends == before)
        #expect(try store.entityCount("ChildRecord") == 4)
        failure.enabled = false
        try store.savePartner(partner, friendID: friend.id, selectedChildIDs: [friend.children[1].id, friend.children[2].id])
        #expect(try store.friend(friend.id).children.filter { $0.partnerID == partner.id }.count == 2)
    }
    @Test("Partner edits and multiple selections survive SQLite close and reopen")
    func persistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("children.sqlite")
        let store = try KinStore(storeURL: url)
        defer { try? store.close() }
        let friend = fixture(); try store.saveFriend(friend)
        var partner = friend.partners[0]; partner.photo = Data("synthetic photo".utf8)
        try store.savePartner(partner, friendID: friend.id, selectedChildIDs: [friend.children[1].id, friend.children[2].id])
        let expected = store.friends
        try store.close()
        let reopened = try KinStore(storeURL: url)
        defer { try? reopened.close() }
        #expect(reopened.friends == expected)
        #expect(try reopened.entityCount("ChildRecord") == 4)
    }
}
