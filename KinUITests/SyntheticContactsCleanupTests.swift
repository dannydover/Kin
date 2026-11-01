import Contacts
import XCTest

enum SyntheticContactsCleanupScope: String {
    case nativeFull = "native-full"
    case preservation = "preservation"
    case missingBirthday = "missing-birthday"
}

func cleanupOwnedSyntheticContacts(_ items: [CNMutableContact], store: CNContactStore,
                                    scope: SyntheticContactsCleanupScope, creationUncertain: Bool) throws {
    do {
        try verifyOwnedFixtureCleanup(items, identifier: { $0.identifier }, remove: { owned in
            let request = CNSaveRequest()
            for contact in owned { request.delete(contact) }
            try store.execute(request)
        }, remainingIdentifiers: { ids in
            let predicate = CNContact.predicateForContacts(withIdentifiers: ids)
            let remaining = try store.unifiedContacts(matching: predicate,
                keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
            return remaining.map(\.identifier)
        }, creationUncertain: creationUncertain)
        print("KIN_CI_CONTACT_CLEANUP \(scope.rawValue) \(items.isEmpty ? "empty" : "verified")")
    } catch {
        // XCTest can suppress a second teardown issue after an earlier test
        // failure. A fixed, redacted marker preserves the cleanup outcome in CI.
        print("KIN_CI_CONTACT_CLEANUP \(scope.rawValue) failed")
        throw SyntheticContactsCleanupError.cleanupFailed
    }
}

final class SyntheticContactsCleanupTests: XCTestCase {
    func testOwnedFixtureCleanupHandlesEmptyPartialAndFailures() throws {
        enum FakeError: Error { case delete, query }
        var deleted: [String] = []
        var queried: [String] = []
        func remove(_ items: [String]) throws { deleted = items }
        func remaining(_ ids: [String]) throws -> [String] { queried = ids; return [] }

        try verifyOwnedFixtureCleanup([], identifier: { $0 }, remove: remove,
                                      remainingIdentifiers: remaining)
        XCTAssertTrue(deleted.isEmpty)
        XCTAssertTrue(queried.isEmpty)
        // A partial creation list deletes and verifies only the owned items.
        try verifyOwnedFixtureCleanup(["owned-a", "owned-b"], identifier: { $0 }, remove: remove,
                                      remainingIdentifiers: remaining)
        XCTAssertEqual(deleted, ["owned-a", "owned-b"])
        XCTAssertEqual(queried, ["owned-a", "owned-b"])
        XCTAssertThrowsError(try verifyOwnedFixtureCleanup([], identifier: { $0 },
            remove: remove, remainingIdentifiers: remaining, creationUncertain: true))
        XCTAssertThrowsError(try verifyOwnedFixtureCleanup(["owned-a"], identifier: { $0 },
            remove: remove, remainingIdentifiers: remaining, creationUncertain: true))
        XCTAssertEqual(deleted, ["owned-a"])
        XCTAssertEqual(queried, ["owned-a"])
        XCTAssertThrowsError(try verifyOwnedFixtureCleanup(["owned-a", "owned-a"], identifier: { $0 },
            remove: remove, remainingIdentifiers: remaining))
        XCTAssertThrowsError(try verifyOwnedFixtureCleanup([""], identifier: { $0 },
            remove: remove, remainingIdentifiers: remaining))
        XCTAssertThrowsError(try verifyOwnedFixtureCleanup(["owned-a"], identifier: { $0 },
            remove: { _ in throw FakeError.delete }, remainingIdentifiers: remaining))
        XCTAssertThrowsError(try verifyOwnedFixtureCleanup(["owned-a"], identifier: { $0 },
            remove: remove, remainingIdentifiers: { _ in throw FakeError.query }))
        XCTAssertThrowsError(try verifyOwnedFixtureCleanup(["owned-a"], identifier: { $0 },
            remove: remove, remainingIdentifiers: { _ in ["owned-a"] }))
    }
}
