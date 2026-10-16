import Foundation
import CoreData
import Observation

enum NewRelationship: Equatable {
    case parent(of: UUID, parentage: Parentage)
    case child(of: UUID, parentage: Parentage)
    case partner(of: UUID, status: PartnerStatus)
}

/// Main-actor transactions; editors hold value drafts until an explicit save.
@MainActor @Observable final class KinStore {
    private(set) var people: [Person] = []
    private(set) var parentLinks: [ParentLink] = []
    private(set) var partnerLinks: [PartnerLink] = []
    private(set) var isReady = false
    private(set) var recoveryError: String?
    @ObservationIgnored private let inMemory: Bool
    @ObservationIgnored private let storeURL: URL?
    @ObservationIgnored private let protectedDataAvailable: @MainActor () -> Bool
    @ObservationIgnored private let context: NSManagedObjectContext
    @ObservationIgnored private let saveContext: @MainActor (NSManagedObjectContext) throws -> Void
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()
    private static let model: NSManagedObjectModel = {
        let model = NSManagedObjectModel()
        func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
            let a = NSAttributeDescription(); a.name = name; a.attributeType = type; a.isOptional = optional; return a
        }
        func entity(_ name: String) -> NSEntityDescription {
            let e = NSEntityDescription(); e.name = name; e.managedObjectClassName = "NSManagedObject"
            e.properties = [attribute("id", .UUIDAttributeType), attribute("payload", .binaryDataAttributeType)]
            e.uniquenessConstraints = [["id"]]; return e
        }
        let person = entity("PersonRecord"), parent = entity("ParentLinkRecord"), partner = entity("PartnerLinkRecord"), state = entity("NotebookState")
        let photo = attribute("photo", .binaryDataAttributeType, optional: true); photo.allowsExternalBinaryDataStorage = true
        person.properties.append(photo)
        func endpoint(_ link: NSEntityDescription, _ name: String, _ inverseName: String) {
            let one = NSRelationshipDescription(); one.name = name; one.destinationEntity = person
            one.minCount = 1; one.maxCount = 1; one.isOptional = false; one.deleteRule = .nullifyDeleteRule
            let many = NSRelationshipDescription(); many.name = inverseName; many.destinationEntity = link
            many.minCount = 0; many.maxCount = 0; many.isOptional = true; many.deleteRule = .cascadeDeleteRule
            one.inverseRelationship = many; many.inverseRelationship = one
            link.properties.append(one); person.properties.append(many)
        }
        endpoint(parent, "parent", "childLinks"); endpoint(parent, "child", "parentLinks")
        endpoint(partner, "first", "firstPartnerLinks"); endpoint(partner, "second", "secondPartnerLinks")
        model.entities = [person, parent, partner, state]; model.versionIdentifiers = ["KinPersonV1"]
        return model
    }()
    /// A supplied SQLite URL must live in a directory dedicated to this notebook.
    init(inMemory: Bool = false, storeURL: URL? = nil,
         protectedDataAvailable: @escaping @MainActor () -> Bool = { true },
         saveContext: @escaping @MainActor (NSManagedObjectContext) throws -> Void = { try $0.save() }) throws {
        self.inMemory = inMemory
        self.saveContext = saveContext
        self.protectedDataAvailable = protectedDataAvailable
        // Resolving the location does not create or read protected files.
        self.storeURL = inMemory ? nil : try storeURL ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("Kin", isDirectory: true).appendingPathComponent("Kin.sqlite")
        context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: Self.model)
        context.undoManager = nil
        if protectedDataAvailable() { try resume() }
    }

    /// Keep value snapshots (and SwiftUI editor identity), but release database handles.
    /// There are no unsaved context changes: editors own drafts until explicit Save.
    func suspend() {
        isReady = false
        do { try detach() }
        catch { recoveryError = "Your notebook couldn’t close. Unlock your iPhone and try again." }
    }

    func resume() throws {
        guard protectedDataAvailable() else { throw NotebookAccessError.locked }
        guard !isReady else { return }
        do {
            // Retry any incomplete detach before opening the same files again.
            try detach()
            if let storeURL, FileManager.default.fileExists(atPath: storeURL.path) {
                try inspectStoreWithoutChangingSource(storeURL)
            }
            if let storeURL {
                let directory = storeURL.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: storeURL.path), FileManager.default.fileExists(atPath: directory.path),
                   try !FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty {
                    // An orphaned WAL or external-photo directory is evidence of an
                    // existing notebook, not permission to create an empty replacement.
                    throw KinError.invalidData
                }
                try NotebookProtection.prepare(directory: directory)
            }
            var options: [AnyHashable: Any] = [NSMigratePersistentStoresAutomaticallyOption: false,
                                             NSInferMappingModelAutomaticallyOption: false]
            #if os(iOS)
            options[NSPersistentStoreFileProtectionKey] = FileProtectionType.complete
            #endif
            try context.persistentStoreCoordinator!.addPersistentStore(
                ofType: inMemory ? NSInMemoryStoreType : NSSQLiteStoreType,
                configurationName: nil, at: storeURL, options: options)
            try protectFiles()
            isReady = true
            try reload()
            recoveryError = nil
        } catch {
            suspend()
            recoveryError = protectedDataAvailable() ? "Your notebook couldn’t reopen. Your data has not been reset. Try again." : nil
            throw protectedDataAvailable() ? error : NotebookAccessError.locked
        }
    }

    /// Core Data may create/change sidecars even for metadata-only read-only opens.
    /// Inspect a protected disposable copy, never the original notebook.
    private func inspectStoreWithoutChangingSource(_ url: URL) throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try NotebookProtection.prepare(directory: scratch)
        let copy = scratch.appendingPathComponent("inspection.sqlite")
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let bytes = try Data(contentsOf: source)
            let target = URL(fileURLWithPath: copy.path + suffix)
            #if os(iOS)
            try bytes.write(to: target, options: [.atomic, .completeFileProtection])
            #else
            try bytes.write(to: target, options: .atomic)
            #endif
        }
        var inspectionOptions: [AnyHashable: Any] = [
            NSReadOnlyPersistentStoreOption: true,
            NSMigratePersistentStoresAutomaticallyOption: false,
            NSInferMappingModelAutomaticallyOption: false,
            // This disposable copy has one connection. Request exclusive locking
            // so SQLite can use an in-memory WAL index without a shared-memory file.
            NSSQLitePragmasOption: ["locking_mode": "EXCLUSIVE"]
        ]
        #if os(iOS)
        inspectionOptions[NSPersistentStoreFileProtectionKey] = FileProtectionType.complete
        #endif
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: Self.model)
        let inspectionContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        inspectionContext.persistentStoreCoordinator = coordinator
        let inspectionStore: NSPersistentStore
        do {
            // Adding the read-only store checks model compatibility itself. A
            // separate metadata-only open can create sidecars with default protection.
            inspectionStore = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: copy,
                options: inspectionOptions)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSPersistentStoreIncompatibleVersionHashError {
            throw KinError.incompatibleStore
        }
        defer { inspectionContext.reset(); try? coordinator.remove(inspectionStore) }
        guard Self.model.isConfiguration(withName: nil, compatibleWithStoreMetadata: coordinator.metadata(for: inspectionStore)) else {
            throw KinError.incompatibleStore
        }
        try NotebookProtection.prepare(directory: scratch)
        // Validate payloads and graph before touching the real store. External
        // photo bytes stay in their original protected support directory and
        // are not needed for structural compatibility inspection.
        _ = try readSnapshot(from: inspectionContext, includePhotos: false)
    }

    private func detach() throws {
        context.reset()
        if let coordinator = context.persistentStoreCoordinator {
            for store in coordinator.persistentStores { try coordinator.remove(store) }
        }
    }

    private func requireAccess() throws {
        guard protectedDataAvailable() else { suspend(); throw NotebookAccessError.locked }
        guard isReady else { throw NotebookAccessError.reopenRequired }
    }

    private func protectFiles() throws {
        if let storeURL { try NotebookProtection.prepare(directory: storeURL.deletingLastPathComponent()) }
    }

    private func recoverAfterFailure(_ error: Error) -> Error {
        context.rollback()
        if inMemory && protectedDataAvailable() { return error }
        // A save can commit before a later read fails. Never replay it automatically.
        // Reopen and reload the committed state before the user chooses to retry.
        suspend()
        recoveryError = protectedDataAvailable() ? "Kin couldn’t finish that change. Open your notebook again to check what was saved, then try again." : nil
        return protectedDataAvailable() ? error : NotebookAccessError.locked
    }

    var isClosed: Bool { context.persistentStoreCoordinator?.persistentStores.isEmpty ?? true }
    /// Explicit teardown for temporary SQLite stores; callers remove files only afterward.
    func close() throws {
        isReady = false
        try detach()
        people = []; parentLinks = []; partnerLinks = []
    }

    func reload() throws {
        try requireAccess()
        let snapshot = try readSnapshot(from: context)
        people = snapshot.people; parentLinks = snapshot.parents; partnerLinks = snapshot.partners
    }
    private func readSnapshot(from readContext: NSManagedObjectContext, includePhotos: Bool = true) throws
        -> (people: [Person], parents: [ParentLink], partners: [PartnerLink]) {
        func records(_ entity: String) throws -> [NSManagedObject] {
            try readContext.fetch(NSFetchRequest<NSManagedObject>(entityName: entity))
        }
        let personRecords = try records("PersonRecord")
        let decoded = try personRecords.map { object -> Person in
            var person: Person = try decode(object)
            guard object.value(forKey: "id") as? UUID == person.id, person.reference > 0, person.revision > 0, person.revision < Int.max,
                  ["Person", "Parent", "Child", "Partner"].contains(person.unnamedRole), person.birthday.isStructurallyValid else { throw KinError.invalidData }
            person.photo = includePhotos ? object.value(forKey: "photo") as? Data : nil
            return person
        }
        let parents: [ParentLink] = try records("ParentLinkRecord").map { object in
            let link: ParentLink = try decode(object)
            guard object.value(forKey: "id") as? UUID == link.id, endpointID(object, "parent") == link.parentID, endpointID(object, "child") == link.childID else { throw KinError.invalidData }
            return link
        }
        let partners: [PartnerLink] = try records("PartnerLinkRecord").map { object in
            let link: PartnerLink = try decode(object)
            guard object.value(forKey: "id") as? UUID == link.id, endpointID(object, "first") == link.firstID, endpointID(object, "second") == link.secondID else { throw KinError.invalidData }
            return link
        }
        let states = try records("NotebookState")
        guard states.count <= 1, decoded.isEmpty || states.count == 1 else { throw KinError.invalidData }
        if let state = states.first {
            let next: Int = try decode(state)
            guard state.value(forKey: "id") as? UUID == Self.stateID,
                  next > (decoded.map(\.reference).max() ?? 0), next < Int.max else { throw KinError.invalidData }
        }
        let ids = Set(decoded.map(\.id))
        guard ids.count == decoded.count, Set(decoded.map(\.reference)).count == decoded.count else { throw KinError.invalidData }
        for link in parents {
            guard ids.contains(link.parentID), ids.contains(link.childID) else { throw KinError.invalidData }
            try validateParent(link, against: parents.filter { $0.id != link.id })
        }
        for link in partners {
            guard ids.contains(link.firstID), ids.contains(link.secondID) else { throw KinError.invalidData }
            try validatePartner(link, against: partners.filter { $0.id != link.id })
        }
        return (decoded, parents, partners)
    }
    func person(_ id: UUID) throws -> Person {
        try requireAccess()
        guard let value = people.first(where: { $0.id == id }) else { throw KinError.missingPerson }
        return value
    }
    /// Creation and optional linking commit together, preventing inaccessible partial records.
    func savePerson(_ draft: Person, today: Date = Date(), calendar: Calendar = .current,
                    confirmPhotoRemoval: Bool = false, relationship: NewRelationship? = nil) throws {
        try requireAccess()
        var value = draft
        let old = people.first { $0.id == draft.id }
        guard old != nil || draft.revision == 0 else { throw KinError.missingPerson }
        if let old {
            if old.revision != draft.revision {
                var retry = draft
                retry.revision = old.revision; retry.reference = old.reference; retry.unnamedRole = old.unnamedRole
                // An explicit retry after a post-commit failure is idempotent.
                // Different newer edits are never overwritten by an old draft.
                guard retry == old else { throw KinError.staleEdit }
                if let relationship {
                    switch relationship {
                    case .parent(let id, let kind):
                        guard parentLinks.contains(where: { $0.parentID == draft.id && $0.childID == id && $0.parentage == kind }) else { throw KinError.staleEdit }
                    case .child(let id, let kind):
                        guard parentLinks.contains(where: { $0.parentID == id && $0.childID == draft.id && $0.parentage == kind }) else { throw KinError.staleEdit }
                    case .partner(let id, let status):
                        guard partnerLinks.contains(where: { Set([$0.firstID, $0.secondID]) == Set([id, draft.id]) && $0.status == status }) else { throw KinError.staleEdit }
                    }
                }
                return
            }
            value.reference = old.reference; value.unnamedRole = old.unnamedRole
        }
        func clean(_ text: String?) throws -> String? {
            let text = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard text.count <= 200 else { throw KinError.invalidName }
            return text.isEmpty ? nil : text
        }
        value.firstName = try clean(value.firstName); value.lastName = try clean(value.lastName)
        let rules = AgeRules(calendar: calendar)
        try rules.validate(value.birthday, on: today)
        if !rules.allowsPhoto(value.birthday, on: today) {
            if old?.photo != nil && old?.birthday != value.birthday {
                guard confirmPhotoRemoval else { throw KinError.photoRemovalRequired }
                value.photo = nil
            }
            guard value.photo == nil else { throw KinError.photoNotAllowed }
        }
        var parent: ParentLink?, partner: PartnerLink?
        if let relationship {
            switch relationship {
            case .parent(let id, let kind):
                _ = try person(id); parent = ParentLink(parentID: value.id, childID: id, parentage: kind)
                try validateParent(parent!, against: parentLinks)
            case .child(let id, let kind):
                _ = try person(id); parent = ParentLink(parentID: id, childID: value.id, parentage: kind)
                try validateParent(parent!, against: parentLinks)
            case .partner(let id, let status):
                _ = try person(id); partner = PartnerLink(firstID: id, secondID: value.id, status: status)
                try validatePartner(partner!, against: partnerLinks)
            }
        }
        try transaction {
            if old == nil {
                let state = try records("NotebookState").first ?? NSEntityDescription.insertNewObject(forEntityName: "NotebookState", into: context)
                let next: Int = state.isInserted ? 1 : try decode(state)
                value.reference = next
                value.unnamedRole = if case .parent = relationship { "Parent" } else if case .child = relationship { "Child" } else if case .partner = relationship { "Partner" } else { "Person" }
                try encode(next + 1, id: Self.stateID, into: state)
            }
            value.revision += 1
            let object = try record(value.id, "PersonRecord") ?? NSEntityDescription.insertNewObject(forEntityName: "PersonRecord", into: context)
            var header = value; header.photo = nil
            try encode(header, id: value.id, into: object); object.setValue(value.photo, forKey: "photo")
            if let parent { try writeParent(parent) }
            if let partner { try writePartner(partner) }
        }
    }
    private static let stateID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    func saveParentLink(_ link: ParentLink) throws {
        _ = try person(link.parentID); _ = try person(link.childID)
        try validateParent(link, against: parentLinks.filter { $0.id != link.id })
        try transaction { try writeParent(link) }
    }
    func savePartnerLink(_ link: PartnerLink) throws {
        _ = try person(link.firstID); _ = try person(link.secondID)
        try validatePartner(link, against: partnerLinks.filter { $0.id != link.id })
        try transaction { try writePartner(link) }
    }
    private func validateParent(_ link: ParentLink, against links: [ParentLink]) throws {
        guard link.parentID != link.childID, !links.contains(where: { $0.parentID == link.parentID && $0.childID == link.childID }) else { throw KinError.invalidLink }
        var pending = [link.childID], visited: Set<UUID> = []
        while let id = pending.popLast() {
            if id == link.parentID { throw KinError.cycle }
            if visited.insert(id).inserted { pending += links.filter { $0.parentID == id }.map(\.childID) }
        }
    }
    private func validatePartner(_ link: PartnerLink, against links: [PartnerLink]) throws {
        guard link.firstID != link.secondID, !links.contains(where: { Set([$0.firstID, $0.secondID]) == Set([link.firstID, link.secondID]) }) else { throw KinError.invalidLink }
    }
    func unlinkParent(_ id: UUID) throws { try deleteRecord(id, "ParentLinkRecord") }
    func unlinkPartner(_ id: UUID) throws { try deleteRecord(id, "PartnerLinkRecord") }
    func deletePerson(_ id: UUID) throws { try deleteRecord(id, "PersonRecord") }
    private func deleteRecord(_ id: UUID, _ entity: String) throws {
        guard let object = try record(id, entity) else { throw KinError.missingPerson }
        try transaction { context.delete(object) }
    }
    func entityCount(_ entity: String) throws -> Int {
        try requireAccess(); return try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: entity))
    }
    private func transaction(_ changes: () throws -> Void) throws {
        try requireAccess()
        do { try changes(); try requireAccess(); try saveContext(context); try protectFiles(); try reload() }
        catch { throw recoverAfterFailure(error) }
    }
    private func writeParent(_ link: ParentLink) throws {
        let object = try record(link.id, "ParentLinkRecord") ?? NSEntityDescription.insertNewObject(forEntityName: "ParentLinkRecord", into: context)
        try encode(link, id: link.id, into: object)
        object.setValue(try record(link.parentID, "PersonRecord"), forKey: "parent")
        object.setValue(try record(link.childID, "PersonRecord"), forKey: "child")
    }
    private func writePartner(_ link: PartnerLink) throws {
        let object = try record(link.id, "PartnerLinkRecord") ?? NSEntityDescription.insertNewObject(forEntityName: "PartnerLinkRecord", into: context)
        try encode(link, id: link.id, into: object)
        object.setValue(try record(link.firstID, "PersonRecord"), forKey: "first")
        object.setValue(try record(link.secondID, "PersonRecord"), forKey: "second")
    }
    private func endpointID(_ object: NSManagedObject, _ key: String) -> UUID? { (object.value(forKey: key) as? NSManagedObject)?.value(forKey: "id") as? UUID }
    private func records(_ entity: String) throws -> [NSManagedObject] { try context.fetch(NSFetchRequest<NSManagedObject>(entityName: entity)) }
    private func record(_ id: UUID, _ entity: String) throws -> NSManagedObject? {
        try requireAccess()
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID); request.fetchLimit = 1
        return try context.fetch(request).first
    }
    private func encode<T: Encodable>(_ value: T, id: UUID, into object: NSManagedObject) throws {
        object.setValue(id, forKey: "id"); object.setValue(try encoder.encode(value), forKey: "payload")
    }
    private func decode<T: Decodable>(_ object: NSManagedObject) throws -> T {
        guard let data = object.value(forKey: "payload") as? Data else { throw KinError.invalidData }
        return try decoder.decode(T.self, from: data)
    }
}
