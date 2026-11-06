import Foundation
import Testing
@testable import Kin

@Suite("Filter state and notebook persistence") @MainActor
struct FilterStoreSequenceTests {
    @Test("Search and category reset preserve a cancelled category draft across reopen")
    func resetAndCancelledEditAcrossReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try KinStore(storeURL: directory.appendingPathComponent("test.sqlite"))
        defer { try? store.close() }
        var friend = Person(firstName: "Synthetic Friend", connections: [.friend]); friend.isListed = true
        var unlabeled = Person(firstName: "Synthetic Unlabeled"); unlabeled.isListed = true
        var hidden = Person(firstName: "Synthetic Hidden", connections: [.friend]); hidden.isListed = false
        try store.savePerson(friend); try store.savePerson(unlabeled); try store.savePerson(hidden)
        let saved = store.people
        let originalFriend = try store.person(friend.id)
        var state = PeopleFilterState(scope: .yours, query: "Unlabeled", searching: true, category: .friend)
        #expect(state.results(store.people).isEmpty)
        for _ in 0..<2 {
            state.clearSearchAndFilters()
            #expect(state == PeopleFilterState())
            #expect(Set(state.results(store.people).map(\.id)) == Set([friend.id, unlabeled.id]))
            #expect(store.people == saved)
        }
        var cancelled = originalFriend
        cancelled.connections = [.colleague]
        #expect(cancelled.connections != originalFriend.connections)
        try store.close(); try store.resume()
        #expect(try store.person(friend.id) == originalFriend)
        #expect(store.people == saved)
        #expect(Set(state.results(store.people).map(\.id)) == Set([friend.id, unlabeled.id]))
        state.scope = .all; state.category = .friend
        #expect(Set(state.results(store.people).map(\.id)) == Set([friend.id, hidden.id]))
        #expect(try store.person(friend.id).connections.contains(.friend))
    }

    @Test("Preview-shaped and persisted filter fixtures agree through repeated clear")
    func fixtureShapesAgreeAcrossStorage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = try KinStore(storeURL: directory.appendingPathComponent("test.sqlite"))
        let memory = try KinStore(inMemory: true)
        defer { try? disk.close(); try? memory.close() }
        for store in [disk, memory] {
            for (name, connections): (String, Set<Connection>) in [
                ("Alex Morgan", []), ("Jamie Patel", [.friend]), ("Robin Chen", [.family])
            ] {
                var person = Person(firstName: name, connections: connections); person.isListed = true
                try store.savePerson(person)
            }
        }
        var state = PeopleFilterState()
        for _ in 0..<2 {
            state.category = .friend; state.query = "Alex Morgan"; state.searching = true
            #expect(state.results(disk.people).isEmpty && state.results(memory.people).isEmpty)
            state.clearSearchAndFilters()
            let diskNames = state.results(disk.people).compactMap(\.firstName).sorted()
            let memoryNames = state.results(memory.people).compactMap(\.firstName).sorted()
            #expect(diskNames == ["Alex Morgan", "Jamie Patel", "Robin Chen"])
            #expect(memoryNames == diskNames && state == PeopleFilterState())
        }
        for store in [disk, memory] {
            let friend = try #require(store.people.first { $0.firstName == "Jamie Patel" })
            #expect(friend.connections == [.friend] && friend.isListed)
        }
        try disk.close(); try disk.resume()
        #expect(Set(state.results(disk.people).compactMap(\.firstName)) == Set(["Alex Morgan", "Jamie Patel", "Robin Chen"]))
        let friend = try #require(disk.people.first { $0.firstName == "Jamie Patel" })
        #expect(friend.connections == [.friend])
    }
}
