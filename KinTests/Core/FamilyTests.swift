import Foundation
import Testing
@testable import Kin

@Suite("Family presentation") struct FamilyTests {
    @Test("Search prioritizes friends and labels relatives") func searchPrioritizesFriendsAndLabelsRelatives() {
        let child = Child(firstName: "Ari", lastName: "Vale", birthday: .exact(civil(2020, 1, 1)))
        let family = Friend(firstName: "Rowan", lastName: "Vale", partners: [Partner(firstName: "Mira", lastName: "Vale", isCurrent: false)], children: [child])
        let direct = Friend(firstName: "Ari", lastName: "Willow")
        let hits = FamilySearch.results(in: [family, direct], query: "ari")
        #expect(hits.map(\.friendID) == [direct.id, family.id])
        #expect(hits.last?.subtitle == "Ari Vale · Child of Rowan Vale")
        #expect(FamilySearch.results(in: [family], query: "mira").first?.subtitle == "Mira Vale · Former partner of Rowan Vale")
    }
    @Test("Search folds accents and empty query sorts names") func searchFoldsAccentsAndEmptyQuerySortsNames() {
        let first = Friend(firstName: "Éloise", lastName: "Vale")
        let second = Friend(firstName: "Ari", lastName: "Willow")
        #expect(FamilySearch.results(in: [first], query: " eloise ").count == 1)
        #expect(FamilySearch.results(in: [first, second], query: "").map(\.friendID) == [second.id, first.id])
    }
    @Test("Former partners with children occur in one group") func formerPartnersWithChildrenOccurInOneGroup() {
        let former = Partner(firstName: "Mira", lastName: "Vale", isCurrent: false)
        let current = Partner(firstName: "Jules", lastName: "Ash", isCurrent: true)
        let compact = Partner(firstName: "Quinn", lastName: "Birch", isCurrent: false)
        let child = Child(firstName: "Ari", lastName: "Vale", birthday: .exact(civil(2020, 1, 1)), partnerID: former.id)
        let other = Child(firstName: "Wren", lastName: "Ash", birthday: .estimated(age: 3, referenceDate: civil(2026, 1, 1)))
        let friend = Friend(firstName: "Rowan", lastName: "Vale", partners: [former, current, compact], children: [child, other])
        let layout = FamilyLayout(friend: friend)
        #expect(layout.grouped)
        #expect(layout.groups.flatMap(\.children).map(\.id).count == 2)
        #expect(Set(layout.groups.flatMap(\.children).map(\.id)).count == 2)
        #expect(layout.compactFormerPartners.map(\.id) == [compact.id])
        #expect(layout.groups.last?.partner?.id == former.id)
        #expect(child.displayName(friendLastName: "Vale") == "Ari")
        #expect(other.displayName(friendLastName: "Vale") == "Wren Ash")
    }
    @Test("One current partner without links uses simple layout") func oneCurrentPartnerWithoutLinksUsesSimpleLayout() {
        let partner = Partner(firstName: "Mira", lastName: "Vale")
        let friend = Friend(firstName: "Rowan", lastName: "Vale", partners: [partner])
        #expect(!FamilyLayout(friend: friend).grouped)
    }
}

@Suite("Core Data family transactions") @MainActor struct StoreTests {
    let store: KinStore
    init() throws { store = try KinStore(inMemory: true) }
    func sample() throws -> Friend {
        let friend = Friend(firstName: "Rowan", lastName: "Vale", notes: "Fictional test family")
        try store.saveFriend(friend)
        return friend
    }
    @Test("Friend names trim and persist") func friendNamesTrimAndPersist() throws {
        var friend = Friend(firstName: " Rowan ", lastName: " Vale ")
        try store.saveFriend(friend)
        #expect(store.friends.first?.fullName == "Rowan Vale")
        friend.notes = "Updated"
        try store.saveFriend(friend)
        #expect(store.friends.count == 1)
        #expect(store.friends.first?.notes == "Updated")
        try store.reload()
        #expect(store.friends.first?.notes == "Updated")
    }
    @Test("Required names reject whitespace") func requiredNamesRejectWhitespace() {
        #expect(throws: (any Error).self) { try store.saveFriend(Friend(firstName: " ", lastName: "Vale")) }
        #expect(store.friends.isEmpty)
    }
    @Test("Current partner replacement requires confirmation and preserves links") func currentPartnerReplacementRequiresConfirmationAndPreservesLinks() throws {
        let friend = try sample()
        let old = Partner(firstName: "Mira", lastName: "Vale")
        try store.savePartner(old, friendID: friend.id)
        let child = Child(firstName: "Ari", lastName: "Vale", birthday: .exact(civil(2020, 1, 1)), partnerID: old.id)
        try store.saveChild(child, friendID: friend.id, today: day(2026, 10, 2), calendar: utcCalendar())
        let new = Partner(firstName: "Jules", lastName: "Ash")
        #expect(throws: (any Error).self) { try store.savePartner(new, friendID: friend.id) }
        #expect(store.friends.first?.partners.count == 1)
        try store.savePartner(new, friendID: friend.id, replaceCurrent: true)
        let saved = try #require(store.friends.first)
        #expect(saved.partners.filter(\.isCurrent).map(\.id) == [new.id])
        #expect(saved.children.first?.partnerID == old.id)
    }
    @Test("Deleting a partner unlinks children without deleting them") func deletingPartnerUnlinksChildrenWithoutDeletingThem() throws {
        let friend = try sample()
        let partner = Partner(firstName: "Mira", lastName: "Vale")
        try store.savePartner(partner, friendID: friend.id)
        try store.saveChild(Child(firstName: "Ari", lastName: "Vale", birthday: .exact(civil(2020, 1, 1)), partnerID: partner.id), friendID: friend.id, today: day(2026, 10, 2), calendar: utcCalendar())
        try store.deletePartner(partner.id, friendID: friend.id)
        #expect(store.friends.first?.children.count == 1)
        #expect(store.friends.first?.children.first?.partnerID == nil)
        #expect(store.friends.first?.partners.isEmpty == true)
    }
    @Test("Friend deletion cascades through stored entities") func friendDeletionCascadesThroughStoredEntities() throws {
        let friend = try sample()
        try store.savePartner(Partner(firstName: "Mira", lastName: "Vale"), friendID: friend.id)
        try store.saveChild(Child(firstName: "Ari", lastName: "Vale", birthday: .exact(civil(2020, 1, 1))), friendID: friend.id, today: day(2026, 10, 2), calendar: utcCalendar())
        #expect(try store.entityCount("ChildRecord") == 1)
        try store.deleteFriend(friend.id)
        #expect(store.friends.isEmpty)
        #expect(try store.entityCount("PartnerRecord") == 0)
        #expect(try store.entityCount("ChildRecord") == 0)
    }
    @Test("Cross-family partner links are rejected atomically") func crossFamilyPartnerLinksAreRejectedAtomically() throws {
        let friend = try sample()
        let child = Child(firstName: "Ari", lastName: "Vale", birthday: .exact(civil(2020, 1, 1)), partnerID: UUID())
        #expect(throws: (any Error).self) { try store.saveChild(child, friendID: friend.id, today: day(2026, 10, 2), calendar: utcCalendar()) }
        #expect(store.friends.first?.children.isEmpty == true)
    }
    @Test("Exact conversion and child deletion persist") func exactConversionAndChildDeletionPersist() throws {
        let friend = try sample()
        var child = Child(firstName: "Ari", lastName: "Vale", birthday: .estimated(age: 3, referenceDate: civil(2026, 1, 1)))
        try store.saveChild(child, friendID: friend.id, today: day(2026, 10, 2), calendar: utcCalendar())
        child.birthday = .exact(civil(2022, 12, 1))
        try store.saveChild(child, friendID: friend.id, today: day(2026, 10, 2), calendar: utcCalendar())
        #expect(store.friends.first?.children.first?.birthday == child.birthday)
        try store.deleteChild(child.id, friendID: friend.id)
        #expect(store.friends.first?.children.isEmpty == true)
    }
}
