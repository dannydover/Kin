/// Shared by test targets only. Callers supply the identifiers and operations;
/// this primitive has no Contacts access and never discovers unrelated items.
public enum SyntheticContactsCleanupError: Error, Equatable {
    case invalidIdentifiers
    case remainingOwnedContacts
    case cleanupFailed
    case creationUncertain
}

public func verifyOwnedFixtureCleanup<Item>(
    _ items: [Item], identifier: (Item) -> String,
    remove: ([Item]) throws -> Void,
    remainingIdentifiers: ([String]) throws -> [String], creationUncertain: Bool = false
) throws {
    if items.isEmpty {
        if creationUncertain { throw SyntheticContactsCleanupError.creationUncertain }
        return
    }
    let ids = items.map(identifier)
    guard ids.allSatisfy({ !$0.isEmpty }), Set(ids).count == ids.count else {
        throw SyntheticContactsCleanupError.invalidIdentifiers
    }
    try remove(items)
    // The adapter must query only the identifiers owned by this test.
    guard try remainingIdentifiers(ids).isEmpty else {
        throw SyntheticContactsCleanupError.remainingOwnedContacts
    }
    if creationUncertain { throw SyntheticContactsCleanupError.creationUncertain }
}
