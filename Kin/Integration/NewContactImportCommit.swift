import Foundation
import Observation

/// The review owns one stable person identity across failure, retry and repeated taps.
/// KinStore already commits a person, eligible photo and optional link atomically.
@MainActor @Observable final class NewContactImportCommit {
    private(set) var completedID: UUID?
    func save(_ draft: Person, store: KinStore, relationship: NewRelationship?, today: Date = Date()) throws {
        if let completedID {
            guard completedID == draft.id else { throw KinError.staleEdit }
            return
        }
        guard draft.revision == 0, draft.reference == 0 else { throw KinError.staleEdit }
        var value = draft
        value.isListed = relationship == nil ? true : draft.isListed
        // Match store normalization so an explicit retry after a post-commit error
        // compares equal even when the user reviewed whitespace around a name.
        value.firstName = value.firstName?.trimmingCharacters(in: .whitespacesAndNewlines)
        value.lastName = value.lastName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.firstName == "" { value.firstName = nil }
        if value.lastName == "" { value.lastName = nil }
        try store.savePerson(value, today: today, relationship: relationship)
        completedID = value.id
    }
}
