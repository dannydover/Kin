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
        #expect(throws: NotebookAccessError.self) { try store.saveFriend(Friend(firstName: "Rowan", lastName: "Vale")) }
        #expect(throws: NotebookAccessError.self) { try store.resume() }
        availability.available = true
        try store.resume()
        #expect(store.isReady)
        #expect(store.friends.isEmpty)
    }

    @Test("Repeated lock/unlock preserves saved families and an independent editor draft")
    func repeatedLocks() throws {
        let url = try temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let availability = Availability()
        let store = try KinStore(storeURL: url, protectedDataAvailable: { availability.available })
        defer { try? store.close() }
        let friend = Friend(firstName: "Rowan", lastName: "Vale")
        try store.saveFriend(friend)
        let partner = Partner(firstName: "Mira", lastName: "Vale")
        try store.savePartner(partner, friendID: friend.id)
        var draft = friend; draft.notes = "Unsaved fictional note"
        for _ in 0..<3 {
            // The warning arrives before UIApplication necessarily reports false.
            store.suspend()
            #expect(throws: NotebookAccessError.self) { try store.saveFriend(draft) }
            availability.available = false
            #expect(store.isClosed && !store.isReady)
            #expect(store.friends.first?.notes == "")
            #expect(throws: NotebookAccessError.self) { try store.reload() }
            #expect(throws: NotebookAccessError.self) { try store.deleteFriend(friend.id) }
            #expect(throws: NotebookAccessError.self) { try store.entityCount("FriendRecord") }
            availability.available = true
            try store.resume()
            try store.resume() // duplicate availability/foreground events are harmless
            #expect(store.friends.first?.partners == [partner])
        }
        try store.saveFriend(draft)
        #expect(store.friends.first?.notes == draft.notes)
        #expect(store.friends.first?.partners == [partner])
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
        var draft = Friend(firstName: "Rowan", lastName: "Vale")
        try store.saveFriend(draft)
        draft.notes = "Fictional revised note"
        availability.interruptSave = true
        #expect(throws: NotebookAccessError.self) { try store.saveFriend(draft) }
        #expect(!store.isReady && store.isClosed)
        availability.available = true; availability.interruptSave = false
        try store.resume()
        #expect(store.friends.first?.notes == (committed ? draft.notes : ""))
        try store.saveFriend(draft)
        #expect(try store.entityCount("FriendRecord") == 1)
        #expect(store.friends.first == draft)
    }

    @Test("A failed reopen leaves the database intact and remains retryable")
    func failedReopen() throws {
        let url = try temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try KinStore(storeURL: url)
        defer { try? store.close() }
        let friend = Friend(firstName: "Rowan", lastName: "Vale")
        try store.saveFriend(friend)
        store.suspend()
        let holding = url.deletingLastPathComponent().appendingPathComponent("holding")
        try FileManager.default.moveItem(at: url, to: holding)
        // A directory at the store URL forces an open failure, without corrupting data.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try store.resume() }
        #expect(!store.isReady && store.recoveryError != nil)
        #expect(store.friends == [friend])
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: holding, to: url)
        try store.resume()
        #expect(store.isReady && store.recoveryError == nil)
        #expect(store.friends == [friend])
    }

    @Test("Large external payloads survive repeated saves and suspend/reopen")
    func externalPayloads() throws {
        let url = try temporaryURL()
        let directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try KinStore(storeURL: url)
        defer { try? store.close() }
        var friend = Friend(firstName: "Rowan", lastName: "Vale", photo: Data(repeating: 17, count: 2_000_000))
        try store.saveFriend(friend)
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)!.allObjects.compactMap { $0 as? URL }
        #expect(files.contains { $0.path.contains("_EXTERNAL_DATA/") })
        store.suspend(); try store.resume()
        #expect(store.friends == [friend])
        friend.photo = Data(repeating: 42, count: 2_000_001)
        try store.saveFriend(friend)
        store.suspend(); try store.resume()
        #expect(store.friends == [friend])
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
        var friend = Friend(firstName: "Rowan", lastName: "Vale", photo: Data(repeating: 17, count: 2_000_000))
        let old = try KinStore(storeURL: url)
        try old.saveFriend(friend)
        try old.close()
        for file in try allFiles() {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
        }
        let upgraded = try KinStore(storeURL: url)
        defer { try? upgraded.close() }
        #expect(upgraded.friends == [friend])
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
        try upgraded.saveFriend(friend)
        let laterPayloads = try allFiles().filter { $0.path.contains("_EXTERNAL_DATA/") }
        #expect(!Set(laterPayloads).subtracting(payloads).isEmpty)
        try expectComplete()
        upgraded.suspend(); try upgraded.resume()
        #expect(upgraded.friends == [friend])
        try expectComplete()
    }
    #endif
}
