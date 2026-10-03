import Foundation
import CoreData
import Observation

/// Owns one Core Data context. Value snapshots keep managed objects out of views.
@MainActor @Observable final class KinStore {
    private(set) var friends: [Friend] = []
    @ObservationIgnored private let context: NSManagedObjectContext
    @ObservationIgnored private let saveContext: @MainActor (NSManagedObjectContext) throws -> Void
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    // Model metadata is immutable after construction, shared only on the main actor.
    private static let model: NSManagedObjectModel = {
        let model = NSManagedObjectModel()
        func entity(_ name: String) -> NSEntityDescription {
            let entity = NSEntityDescription()
            entity.name = name
            entity.managedObjectClassName = "NSManagedObject"
            let id = NSAttributeDescription()
            id.name = "id"; id.attributeType = .UUIDAttributeType; id.isOptional = false
            let payload = NSAttributeDescription()
            payload.name = "payload"; payload.attributeType = .binaryDataAttributeType; payload.isOptional = false
            payload.allowsExternalBinaryDataStorage = true
            entity.properties = [id, payload]
            entity.uniquenessConstraints = [["id"]]
            return entity
        }
        let friend = entity("FriendRecord")
        let partner = entity("PartnerRecord")
        let child = entity("ChildRecord")
        func relation(_ source: NSEntityDescription, _ name: String, _ destination: NSEntityDescription,
                      _ inverseName: String, deleteRule: NSDeleteRule) {
            let many = NSRelationshipDescription()
            many.name = name; many.destinationEntity = destination; many.minCount = 0; many.maxCount = 0
            many.isOptional = true; many.deleteRule = deleteRule
            let one = NSRelationshipDescription()
            one.name = inverseName; one.destinationEntity = source; one.minCount = 0; one.maxCount = 1
            one.isOptional = true; one.deleteRule = .nullifyDeleteRule
            many.inverseRelationship = one; one.inverseRelationship = many
            source.properties.append(many); destination.properties.append(one)
        }
        relation(friend, "partners", partner, "friend", deleteRule: .cascadeDeleteRule)
        relation(friend, "children", child, "friend", deleteRule: .cascadeDeleteRule)
        relation(partner, "children", child, "partner", deleteRule: .nullifyDeleteRule)
        model.entities = [friend, partner, child]
        model.versionIdentifiers = ["KinV1"]
        return model
    }()

    init(inMemory: Bool = false, storeURL: URL? = nil, saveContext: @escaping @MainActor (NSManagedObjectContext) throws -> Void = { try $0.save() }) throws {
        self.saveContext = saveContext
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: Self.model)
        var url = storeURL
        if !inMemory && url == nil {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true).appendingPathComponent("Kin", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            url = directory.appendingPathComponent("Kin.sqlite")
        }
        var options: [AnyHashable: Any] = [NSMigratePersistentStoresAutomaticallyOption: true,
                                         NSInferMappingModelAutomaticallyOption: true]
        #if os(iOS)
        options[NSPersistentStoreFileProtectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try coordinator.addPersistentStore(ofType: inMemory ? NSInMemoryStoreType : NSSQLiteStoreType,
                                           configurationName: nil, at: inMemory ? nil : url, options: options)
        context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.undoManager = nil
        try reload()
    }

    var isClosed: Bool { context.persistentStoreCoordinator?.persistentStores.isEmpty ?? true }
    /// Explicit teardown for temporary SQLite stores; callers remove files only afterward.
    func close() throws {
        context.reset()
        if let coordinator = context.persistentStoreCoordinator {
            for store in coordinator.persistentStores { try coordinator.remove(store) }
        }
        friends = []
    }

    func reload() throws {
        let records = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "FriendRecord"))
        let decoded = try records.map { record -> Friend in
            var friend: Friend = try decode(record)
            friend.partners = try related(record, "partners").map { try decode($0) as Partner }
                .sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
            friend.children = try related(record, "children").map { object in
                var child: Child = try decode(object)
                child.partnerID = (object.value(forKey: "partner") as? NSManagedObject)?.value(forKey: "id") as? UUID
                return child
            }.sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
            return friend
        }
        friends = decoded.sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
    }
    func friend(_ id: UUID) throws -> Friend {
        guard let friend = friends.first(where: { $0.id == id }) else { throw KinError.missingFriend }
        return friend
    }
    func saveFriend(_ draft: Friend) throws {
        var value = friends.first(where: { $0.id == draft.id }) ?? draft
        value.firstName = draft.firstName; value.lastName = draft.lastName
        value.photo = draft.photo; value.notes = draft.notes
        try persist(value)
    }
    func savePartner(_ partner: Partner, friendID: UUID, replaceCurrent: Bool = false, selectedChildIDs: Set<UUID>? = nil) throws {
        var friend = try friend(friendID)
        if let selectedChildIDs {
            guard friend.partners.contains(where: { $0.id == partner.id }),
                  selectedChildIDs.isSubset(of: Set(friend.children.map(\.id))) else { throw KinError.invalidChildSelection }
            for index in friend.children.indices {
                if selectedChildIDs.contains(friend.children[index].id) {
                    friend.children[index].partnerID = partner.id
                } else if friend.children[index].partnerID == partner.id {
                    friend.children[index].partnerID = nil
                }
            }
        }
        if partner.isCurrent, let current = friend.currentPartner, current.id != partner.id {
            guard replaceCurrent else { throw KinError.replacementRequired(current.fullName) }
            for index in friend.partners.indices { friend.partners[index].isCurrent = false }
        }
        if let index = friend.partners.firstIndex(where: { $0.id == partner.id }) { friend.partners[index] = partner }
        else { friend.partners.append(partner) }
        try persist(friend)
    }
    func saveChild(_ child: Child, friendID: UUID, today: Date, calendar: Calendar) throws {
        try AgeRules(calendar: calendar).validate(child.birthday, on: today)
        var friend = try friend(friendID)
        guard child.partnerID == nil || friend.partners.contains(where: { $0.id == child.partnerID }) else { throw KinError.invalidPartner }
        if let index = friend.children.firstIndex(where: { $0.id == child.id }) { friend.children[index] = child }
        else { friend.children.append(child) }
        try persist(friend)
    }
    func deleteFriend(_ id: UUID) throws {
        guard let object = try record(id) else { throw KinError.missingFriend }
        do { context.delete(object); try saveContext(context); try reload() }
        catch { context.rollback(); throw error }
    }
    func deletePartner(_ id: UUID, friendID: UUID) throws {
        var friend = try friend(friendID)
        friend.partners.removeAll { $0.id == id }
        for index in friend.children.indices where friend.children[index].partnerID == id { friend.children[index].partnerID = nil }
        try persist(friend)
    }
    func deleteChild(_ id: UUID, friendID: UUID) throws {
        var friend = try friend(friendID)
        friend.children.removeAll { $0.id == id }
        try persist(friend)
    }
    func entityCount(_ entity: String) throws -> Int { try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: entity)) }

    private func persist(_ draft: Friend) throws {
        var friend = draft
        func clean(_ value: String) throws -> String {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 200 else { throw KinError.invalidName }
            return value
        }
        friend.firstName = try clean(friend.firstName); friend.lastName = try clean(friend.lastName)
        for index in friend.partners.indices {
            friend.partners[index].firstName = try clean(friend.partners[index].firstName)
            friend.partners[index].lastName = try clean(friend.partners[index].lastName)
        }
        for index in friend.children.indices {
            friend.children[index].firstName = try clean(friend.children[index].firstName)
            friend.children[index].lastName = try clean(friend.children[index].lastName)
            guard friend.children[index].partnerID == nil || friend.partners.contains(where: { $0.id == friend.children[index].partnerID }) else { throw KinError.invalidPartner }
        }
        guard friend.partners.filter(\.isCurrent).count <= 1 else { throw KinError.invalidData }
        do {
            let object = try record(friend.id) ?? NSEntityDescription.insertNewObject(forEntityName: "FriendRecord", into: context)
            // Rebuild only this aggregate inside one context save; failure rolls it all back.
            for child in related(object, "children") { context.delete(child) }
            for partner in related(object, "partners") { context.delete(partner) }
            var header = friend; header.partners = []; header.children = []
            try encode(header, id: friend.id, into: object)
            var partners: [UUID: NSManagedObject] = [:]
            for partner in friend.partners {
                let record = NSEntityDescription.insertNewObject(forEntityName: "PartnerRecord", into: context)
                try encode(partner, id: partner.id, into: record)
                record.setValue(object, forKey: "friend")
                partners[partner.id] = record
            }
            for child in friend.children {
                let record = NSEntityDescription.insertNewObject(forEntityName: "ChildRecord", into: context)
                try encode(child, id: child.id, into: record)
                record.setValue(object, forKey: "friend")
                if let id = child.partnerID { record.setValue(partners[id], forKey: "partner") }
            }
            try saveContext(context)
            try reload()
        } catch { context.rollback(); throw error }
    }
    private func related(_ object: NSManagedObject, _ key: String) -> [NSManagedObject] {
        Array(object.value(forKey: key) as? Set<NSManagedObject> ?? [])
    }
    private func record(_ id: UUID) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "FriendRecord")
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    private func encode<T: Encodable>(_ value: T, id: UUID, into object: NSManagedObject) throws {
        object.setValue(id, forKey: "id")
        object.setValue(try encoder.encode(value), forKey: "payload")
    }
    private func decode<T: Decodable>(_ object: NSManagedObject) throws -> T {
        guard let data = object.value(forKey: "payload") as? Data else { throw KinError.invalidData }
        return try decoder.decode(T.self, from: data)
    }
}
