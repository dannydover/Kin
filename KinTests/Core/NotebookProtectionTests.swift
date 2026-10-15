import Foundation
import CoreData
import Testing
@testable import Kin

@MainActor private final class Availability {
    var available = true
    var interruptSave = false
}

@Suite("Notebook protected-data recovery") @MainActor struct NotebookProtectionTests {
    private func temporaryURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("test.sqlite")
    }

    @Test("Locked launch never opens or creates a database; unlock opens it")
    func lockedLaunch() throws {
        let url = try temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let availability = Availability(); availability.available = false
        let store = try KinStore(storeURL: url, protectedDataAvailable: { availability.available })
        defer { try? store.close() }
        #expect(store.isClosed && !store.isReady)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(throws: NotebookAccessError.self) { try store.savePerson(Person(firstName: "Rowan", lastName: "Vale", birthday: .exact(CivilDate(year: 1980, month: 1, day: 1)))) }
        #expect(throws: NotebookAccessError.self) { try store.resume() }
        availability.available = true
        try store.resume()
        #expect(store.isReady)
        #expect(store.people.isEmpty)
    }

    @Test("Repeated lock/unlock preserves saved families and an independent editor draft")
    func repeatedLocks() throws {
        let url = try temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let availability = Availability()
        let store = try KinStore(storeURL: url, protectedDataAvailable: { availability.available })
        defer { try? store.close() }
        var friend = Person(firstName: "Rowan", lastName: "Vale", birthday: .exact(CivilDate(year: 1980, month: 1, day: 1)))
        try store.savePerson(friend)
        friend = try store.person(friend.id)
        var draft = friend; draft.notes = "Unsaved fictional note"
        for _ in 0..<3 {
            // The warning arrives before UIApplication necessarily reports false.
            store.suspend()
            #expect(throws: NotebookAccessError.self) { try store.savePerson(draft) }
            availability.available = false
            #expect(store.isClosed && !store.isReady)
            #expect(store.people.first?.notes == "")
            #expect(throws: NotebookAccessError.self) { try store.reload() }
            #expect(throws: NotebookAccessError.self) { try store.deletePerson(friend.id) }
            #expect(throws: NotebookAccessError.self) { try store.entityCount("PersonRecord") }
            availability.available = true
            try store.resume()
            try store.resume() // duplicate availability/foreground events are harmless
            #expect(store.people.first?.id == friend.id)
        }
        try store.savePerson(draft)
        draft = try store.person(draft.id)
        #expect(store.people.first?.notes == draft.notes)
        #expect(store.people.first?.id == friend.id)
    }

    @Test("Lock during save can be retried without loss or duplicate records", arguments: [false, true])
    func interruptedSave(committed: Bool) throws {
        let url = try temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let availability = Availability()
        let store = try KinStore(storeURL: url, protectedDataAvailable: { availability.available }, saveContext: { context in
            if availability.interruptSave {
                if committed { try context.save() }
                availability.available = false
                throw CocoaError(.fileReadNoPermission)
            }
            try context.save()
        })
        defer { try? store.close() }
        var draft = Person(firstName: "Rowan", lastName: "Vale", birthday: .exact(CivilDate(year: 1980, month: 1, day: 1)))
        try store.savePerson(draft)
        draft = try store.person(draft.id)
        draft.notes = "Fictional revised note"
        availability.interruptSave = true
        #expect(throws: NotebookAccessError.self) { try store.savePerson(draft) }
        #expect(!store.isReady && store.isClosed)
        availability.available = true; availability.interruptSave = false
        try store.resume()
        #expect(store.people.first?.notes == (committed ? draft.notes : ""))
        try store.savePerson(draft)
        draft = try store.person(draft.id)
        #expect(try store.entityCount("PersonRecord") == 1)
        #expect(store.people.first == draft)
    }

    @Test("A failed reopen leaves the database intact and remains retryable")
    func failedReopen() throws {
        let url = try temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try KinStore(storeURL: url)
        defer { try? store.close() }
        var friend = Person(firstName: "Rowan", lastName: "Vale", birthday: .exact(CivilDate(year: 1980, month: 1, day: 1)))
        try store.savePerson(friend)
        friend = try store.person(friend.id)
        store.suspend()
        let holding = url.deletingLastPathComponent().appendingPathComponent("holding")
        try FileManager.default.moveItem(at: url, to: holding)
        // A directory at the store URL forces an open failure, without corrupting data.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try store.resume() }
        #expect(!store.isReady && store.recoveryError != nil)
        #expect(store.people == [friend])
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: holding, to: url)
        try store.resume()
        #expect(store.isReady && store.recoveryError == nil)
        #expect(store.people == [friend])
    }

    @Test("Large external payloads survive repeated saves and suspend/reopen")
    func externalPayloads() throws {
        let url = try temporaryURL()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try KinStore(storeURL: url)
        defer { try? store.close() }
        var friend = Person(firstName: "Rowan", lastName: "Vale", birthday: .exact(CivilDate(year: 1980, month: 1, day: 1)), photo: Data(repeating: 17, count: 2_000_000))
        try store.savePerson(friend)
        friend = try store.person(friend.id)
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)!.allObjects.compactMap { $0 as? URL }
        #expect(files.contains { $0.path.contains("_EXTERNAL_DATA/") })
        store.suspend(); try store.resume()
        #expect(store.people == [friend])
        friend.photo = Data(repeating: 42, count: 2_000_001)
        try store.savePerson(friend)
        friend = try store.person(friend.id)
        store.suspend(); try store.resume()
        #expect(store.people == [friend])
    }

    #if os(iOS) && !targetEnvironment(simulator)
    @Test("Protection upgrade covers existing sidecars and nested files without changing bytes")
    func existingCompanions() throws {
        let url = try temporaryURL()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = directory.appendingPathComponent(".test_SUPPORT/_EXTERNAL_DATA/payload")
        try FileManager.default.createDirectory(at: payload.deletingLastPathComponent(), withIntermediateDirectories: true)
        let files = [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm"), payload]
        let bytes = Data("Synthetic protection fixture, not a SQLite database".utf8)
        for file in files {
            try bytes.write(to: file)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
        }
        try NotebookProtection.prepare(directory: directory)
        for file in files {
            #expect(try Data(contentsOf: file) == bytes)
            #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.protectionKey] as? FileProtectionType == .complete)
        }
    }

    @Test("Existing and later SQLite companions and external payloads have Complete Protection")
    func fileProtectionUpgrade() throws {
        let url = try temporaryURL()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        func allFiles() throws -> [URL] {
            let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey])!
            return [directory] + enumerator.allObjects.compactMap { $0 as? URL }
        }
        func expectComplete() throws {
            for file in try allFiles() {
                #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.protectionKey] as? FileProtectionType == .complete)
            }
        }
        var friend = Person(firstName: "Rowan", lastName: "Vale", birthday: .exact(CivilDate(year: 1980, month: 1, day: 1)), photo: Data(repeating: 17, count: 2_000_000))
        let old = try KinStore(storeURL: url)
        try old.savePerson(friend)
        friend = try old.person(friend.id)
        try old.close()
        for file in try allFiles() {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
        }
        let upgraded = try KinStore(storeURL: url)
        defer { try? upgraded.close() }
        #expect(upgraded.people == [friend])
        try expectComplete()
        #expect(FileManager.default.fileExists(atPath: url.path + "-wal"))
        #expect(FileManager.default.fileExists(atPath: url.path + "-shm"))
        let payloads = try allFiles().filter { $0.path.contains("_EXTERNAL_DATA/") }
        #expect(!payloads.isEmpty)
        // Verify inheritance independently of the post-save protection sweep.
        let probe = directory.appendingPathComponent("inheritance-probe")
        try Data("synthetic".utf8).write(to: probe)
        try expectComplete()
        friend.photo = Data(repeating: 42, count: 2_000_001)
        try upgraded.savePerson(friend)
        friend = try upgraded.person(friend.id)
        let laterPayloads = try allFiles().filter { $0.path.contains("_EXTERNAL_DATA/") }
        #expect(!Set(laterPayloads).subtracting(payloads).isEmpty)
        try expectComplete()
        upgraded.suspend(); try upgraded.resume()
        #expect(upgraded.people == [friend])
        try expectComplete()
    }
    #endif
}
