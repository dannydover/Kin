import Testing
#if SWIFT_PACKAGE
import SyntheticContactsTestSupport
#endif

@Suite("Owned synthetic fixture cleanup") struct SyntheticContactsCleanupCoreTests {
    enum Failure: Error, Equatable { case remove, query }

    @Test("Empty and partial fixtures touch only owned identifiers")
    func ownedIdentifiers() throws {
        var removed: [[String]] = [], queried: [[String]] = []
        func remove(_ ids: [String]) { removed.append(ids) }
        func remaining(_ ids: [String]) -> [String] { queried.append(ids); return [] }
        try verifyOwnedFixtureCleanup([], identifier: { $0 }, remove: remove, remainingIdentifiers: remaining)
        #expect(removed.isEmpty && queried.isEmpty)
        try verifyOwnedFixtureCleanup(["owned-a", "owned-b"], identifier: { $0 }, remove: remove, remainingIdentifiers: remaining)
        #expect(removed == [["owned-a", "owned-b"]])
        #expect(queried == [["owned-a", "owned-b"]])
    }

    @Test("Missing or duplicate identifiers fail before deletion or query", arguments: [[""], ["owned-a", "owned-a"]])
    func invalidIdentifiers(_ ids: [String]) {
        var removed = false, queried = false
        #expect(throws: SyntheticContactsCleanupError.invalidIdentifiers) {
            try verifyOwnedFixtureCleanup(ids, identifier: { $0 }, remove: { _ in removed = true },
                                          remainingIdentifiers: { _ in queried = true; return [] })
        }
        #expect(!removed && !queried)
    }

    @Test("Uncertain creation fails closed even after known owned items are verified", arguments: [false, true])
    func uncertainCreation(_ hasKnownItems: Bool) {
        let ids = hasKnownItems ? ["owned-a"] : []
        var removed: [String] = [], queried: [String] = []
        #expect(throws: SyntheticContactsCleanupError.creationUncertain) {
            try verifyOwnedFixtureCleanup(ids, identifier: { $0 }, remove: { removed = $0 },
                                          remainingIdentifiers: { queried = $0; return [] }, creationUncertain: true)
        }
        #expect(removed == ids && queried == ids)
    }

    @Test("Delete and verification errors propagate without asserting success")
    func operationFailures() {
        var queried = false
        #expect(throws: Failure.remove) {
            try verifyOwnedFixtureCleanup(["owned-a"], identifier: { $0 }, remove: { _ in throw Failure.remove },
                                          remainingIdentifiers: { _ in queried = true; return [] })
        }
        #expect(!queried)
        var removed: [String] = []
        #expect(throws: Failure.query) {
            try verifyOwnedFixtureCleanup(["owned-a"], identifier: { $0 }, remove: { removed = $0 },
                                          remainingIdentifiers: { _ in throw Failure.query })
        }
        #expect(removed == ["owned-a"])
    }

    @Test("A remaining owned fixture is a cleanup failure")
    func remainingFixture() {
        var query: [String] = []
        #expect(throws: SyntheticContactsCleanupError.remainingOwnedContacts) {
            try verifyOwnedFixtureCleanup(["owned-a", "owned-b"], identifier: { $0 }, remove: { _ in },
                                          remainingIdentifiers: { query = $0; return ["owned-b"] })
        }
        #expect(query == ["owned-a", "owned-b"])
    }
}
