import Foundation
import CoreData
import SQLite3
import Testing
#if os(iOS)
import UIKit
#endif
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

    @Test("Compatibility inspection preserves committed identities and links still in the WAL")
    func committedWAL() throws {
        let url = try temporaryURL(), directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try KinStore(storeURL: url)
        defer { try? source.close() }
        let parent = Person(firstName: "Synthetic parent"), child = Person(firstName: "Synthetic child")
        try source.savePerson(parent)
        try source.savePerson(child, relationship: .child(of: parent.id, parentage: .adoptive))
        let expectedPeople = source.people, expectedLinks = source.parentLinks
        let wal = URL(fileURLWithPath: url.path + "-wal")
        #expect(try Data(contentsOf: wal).count > 32)
        // immutable deliberately ignores WAL: prove the committed people cannot
        // be recovered by inspecting the main file alone.
        var database: OpaquePointer?
        let uri = "file:" + url.path + "?immutable=1"
        try #require(sqlite3_open_v2(uri, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK)
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM ZPERSONRECORD", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        if prepared == SQLITE_OK {
            try #require(sqlite3_step(statement) == SQLITE_ROW)
            #expect(sqlite3_column_int64(statement, 0) == 0)
        } else {
            #expect(prepared == SQLITE_ERROR)
            #expect(String(cString: sqlite3_errmsg(database)).contains("no such table"))
        }
        // Copy source bytes while its writer remains open, retaining WAL-only commits.
        let copyDirectory = directory.appendingPathComponent("copy")
        try NotebookProtection.prepare(directory: copyDirectory)
        let copy = copyDirectory.appendingPathComponent("test.sqlite")
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            if FileManager.default.fileExists(atPath: file.path) {
                let target = URL(fileURLWithPath: copy.path + suffix)
                #if os(iOS)
                try Data(contentsOf: file).write(to: target, options: [.atomic, .completeFileProtection])
                #else
                try Data(contentsOf: file).write(to: target, options: .atomic)
                #endif
            }
        }
        let before = try ["", "-wal", "-shm"].map { try Data(contentsOf: URL(fileURLWithPath: url.path + $0)) }
        let reopened = try KinStore(storeURL: copy)
        defer { try? reopened.close() }
        #expect(reopened.people == expectedPeople && reopened.parentLinks == expectedLinks)
        #expect(try ["", "-wal", "-shm"].map { try Data(contentsOf: URL(fileURLWithPath: url.path + $0)) } == before)
    }

    #if os(iOS) && !targetEnvironment(simulator)
    @Test("Sampled transient compatibility files have Complete Protection")
    func inspectionCreationProtection() throws {
        try #require(UIApplication.shared.isProtectedDataAvailable)
        let url = try temporaryURL(), directory = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = try KinStore(storeURL:url,protectedDataAvailable:{ UIApplication.shared.isProtectedDataAvailable })
        defer { try? store.close() }
        var person = Person(firstName:"Synthetic",birthday:.exact(CivilDate(year:1980,month:1,day:1)),photo:Data(repeating:17,count:2_000_000))
        try store.savePerson(person); person = try store.person(person.id)
        let observer = InspectionCreationObserver(); observer.start()
        defer { observer.stop() }
        for _ in 0..<8 {
            store.suspend(); try store.resume()
            #expect(store.people == [person])
        }
        observer.stop()
        let samples = observer.samples()
        // A missed race is inconclusive, not a passing protection result.
        #expect(samples.contains { $0["file"] == "." })
        #expect(samples.contains { $0["file"] == "inspection.sqlite" })
        for sample in samples { #expect(sample["complete"] == "true", "Transient inspection file protection: \(sample)") }
    }
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

#if os(iOS) && !targetEnvironment(simulator)
// Poll independent creation-time attributes without changing production code.
private final class InspectionCreationObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var running = false
    private var rows: [String:[String:String]] = [:]
    private let finished = DispatchSemaphore(value:0)
    func start() {
        lock.lock(); running = true; lock.unlock()
        DispatchQueue.global(qos:.userInitiated).async { [self] in
            defer { finished.signal() }
            while isRunning() {
                let root = FileManager.default.temporaryDirectory
                for directory in (try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? [] {
                    let database = directory.appendingPathComponent("inspection.sqlite")
                    guard FileManager.default.fileExists(atPath:database.path) else { continue }
                    for file in [directory] + ((try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)) ?? []) {
                        guard let attributes = try? FileManager.default.attributesOfItem(atPath:file.path), let protection = attributes[.protectionKey] as? FileProtectionType else { continue }
                        let name = file == directory ? "." : file.lastPathComponent
                        let key = directory.lastPathComponent + "/" + name + "/" + protection.rawValue
                        let row = ["directory":directory.lastPathComponent,"file":name,"complete":String(protection == .complete),"actual":protection.rawValue]
                        lock.lock(); rows[key] = row; lock.unlock()
                    }
                }
                Thread.sleep(forTimeInterval:0.001)
            }
        }
    }
    private func isRunning() -> Bool { lock.lock(); defer { lock.unlock() }; return running }
    func stop() {
        lock.lock(); let wasRunning = running; running = false; lock.unlock()
        if wasRunning { _ = finished.wait(timeout:.now() + 2) }
    }
    func samples() -> [[String:String]] { lock.lock(); defer { lock.unlock() }; return Array(rows.values) }
}

#endif
