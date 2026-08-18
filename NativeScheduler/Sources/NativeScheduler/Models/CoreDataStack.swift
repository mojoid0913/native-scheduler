// NativeScheduler/Sources/NativeScheduler/Models/CoreDataStack.swift
@preconcurrency import CoreData
import Foundation

// MARK: - Stack

@MainActor
final class CoreDataStack {
    static let shared = CoreDataStack()

    lazy var container: NSPersistentContainer = {
        let c = NSPersistentContainer(name: "NativeScheduler", managedObjectModel: Self.model)
        let url = Self.storeURL
        let desc = NSPersistentStoreDescription(url: url)
        desc.shouldMigrateStoreAutomatically = true
        desc.shouldInferMappingModelAutomatically = true
        c.persistentStoreDescriptions = [desc]
        c.loadPersistentStores { _, error in
            if let error { fatalError("CoreData load failed: \(error)") }
        }
        c.viewContext.automaticallyMergesChangesFromParent = true
        c.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        return c
    }()

    var viewContext: NSManagedObjectContext { container.viewContext }

    func makeTodoContext() -> NSManagedObjectContext {
        Self.makeIsolatedMainContext(
            persistentStoreCoordinator: container.persistentStoreCoordinator,
            name: "TodoViewModel"
        )
    }

    func makeSettingsContext() -> NSManagedObjectContext {
        Self.makeIsolatedMainContext(
            persistentStoreCoordinator: container.persistentStoreCoordinator,
            name: "NativeScheduler.settings"
        )
    }

    static func makeIsolatedMainContext(
        persistentStoreCoordinator: NSPersistentStoreCoordinator,
        name: String
    ) -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = persistentStoreCoordinator
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        context.name = name
        return context
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        return ctx
    }

    @discardableResult
    func save(context: NSManagedObjectContext? = nil) -> Result<Void, Error> {
        let ctx = context ?? viewContext
        return ctx.performAndWait {
            guard ctx.hasChanges else { return .success(()) }
            return Result { try ctx.save() }
        }
    }

    // MARK: - Store URL
    private static var storeURL: URL {
        guard let url = resolveStoreURL(
            environment: ProcessInfo.processInfo.environment,
            applicationSupportDirectory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!,
            fileExists: FileManager.default.fileExists(atPath:)
        ) else {
            fatalError("Invalid smoke store configuration")
        }
        if url.pathComponents.contains("NativeScheduler.sqlite") {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        return url
    }

    static func resolveStoreURL(
        environment: [String: String],
        applicationSupportDirectory: URL,
        fileExists: (String) -> Bool
    ) -> URL? {
        let storeName = "NativeScheduler.sqlite"
        guard environment["NATIVE_SCHEDULER_SMOKE_AUTOSTART"] == "1" else {
            return applicationSupportDirectory
                .appendingPathComponent("NativeScheduler", isDirectory: true)
                .appendingPathComponent(storeName)
        }

        guard let rootPath = environment["NATIVE_SCHEDULER_SMOKE_STORE_ROOT"],
              rootPath.hasPrefix("/"),
              rootPath != "/" else { return nil }
        let root = URL(fileURLWithPath: rootPath).standardizedFileURL
        guard root.path == rootPath,
              fileExists(root.appendingPathComponent(".native-scheduler-isolated-qa").path) else { return nil }
        return root.appendingPathComponent(storeName)
    }

    // MARK: - Model defined in code (no .xcdatamodeld needed)
    static let model: NSManagedObjectModel = {
        let model = NSManagedObjectModel()

        // ── Category ──────────────────────────────────────────────────────
        let categoryEntity = NSEntityDescription()
        categoryEntity.name = "CategoryEntity"
        categoryEntity.managedObjectClassName = "CategoryEntity"

        let catId       = attr("id",        .UUIDAttributeType)
        let catName     = attr("name",       .stringAttributeType)
        let catColorHex = attr("colorHex",   .stringAttributeType)
        let catCreated  = attr("createdAt",  .dateAttributeType)
        let catOrder    = attr("sortOrder",  .integer32AttributeType)
        categoryEntity.properties = [catId, catName, catColorHex, catCreated, catOrder]

        // ── Session ───────────────────────────────────────────────────────
        let sessionEntity = NSEntityDescription()
        sessionEntity.name = "SessionEntity"
        sessionEntity.managedObjectClassName = "SessionEntity"

        let sesId        = attr("id",          .UUIDAttributeType)
        let sesStart     = attr("startTime",   .dateAttributeType)
        let sesEnd       = attr("endTime",     .dateAttributeType,   optional: true)
        let sesMode      = attr("timerMode",   .stringAttributeType)
        sessionEntity.properties = [sesId, sesStart, sesEnd, sesMode]

        // ── TodoItem ──────────────────────────────────────────────────────
        let todoEntity = NSEntityDescription()
        todoEntity.name = "TodoEntity"
        todoEntity.managedObjectClassName = "TodoEntity"

        let todoId        = attr("id",           .UUIDAttributeType)
        let todoTitle     = attr("title",         .stringAttributeType)
        let todoCompleted = attr("isCompleted",   .booleanAttributeType)
        let todoPriority  = attr("priority",      .integer32AttributeType)
        let todoCreated   = attr("createdAt",     .dateAttributeType)
        let todoCompletedAt = attr("completedAt", .dateAttributeType, optional: true)
        todoEntity.properties = [todoId, todoTitle, todoCompleted, todoPriority, todoCreated, todoCompletedAt]

        // ── TodoSection ──────────────────────────────────────────────────
        let todoSectionEntity = NSEntityDescription()
        todoSectionEntity.name = "TodoSectionEntity"
        todoSectionEntity.managedObjectClassName = "TodoSectionEntity"

        let sectionId          = attr("id",                 .UUIDAttributeType)
        let sectionTitle       = attr("title",              .stringAttributeType)
        let sectionCompleted   = attr("isCompletedSection", .booleanAttributeType)
        let sectionExpanded    = attr("isExpanded",         .booleanAttributeType)
        let sectionOrder       = attr("sortOrder",          .integer32AttributeType)
        let sectionCreated     = attr("createdAt",          .dateAttributeType)
        todoSectionEntity.properties = [sectionId, sectionTitle, sectionCompleted, sectionExpanded, sectionOrder, sectionCreated]

        // ── Relationships: Category ↔ Session ────────────────────────────
        let catToSessions = NSRelationshipDescription()
        catToSessions.name = "sessions"
        catToSessions.destinationEntity = sessionEntity
        catToSessions.deleteRule = .nullifyDeleteRule
        catToSessions.isOptional = true
        catToSessions.minCount = 0
        catToSessions.maxCount = 0 // to-many

        let sessionToCategory = NSRelationshipDescription()
        sessionToCategory.name = "category"
        sessionToCategory.destinationEntity = categoryEntity
        sessionToCategory.deleteRule = .nullifyDeleteRule
        sessionToCategory.isOptional = true
        sessionToCategory.minCount = 0
        sessionToCategory.maxCount = 1 // to-one

        catToSessions.inverseRelationship = sessionToCategory
        sessionToCategory.inverseRelationship = catToSessions

        // ── Relationships: Category ↔ TodoItem ───────────────────────────
        let catToTodos = NSRelationshipDescription()
        catToTodos.name = "todos"
        catToTodos.destinationEntity = todoEntity
        catToTodos.deleteRule = .nullifyDeleteRule
        catToTodos.isOptional = true
        catToTodos.minCount = 0
        catToTodos.maxCount = 0

        let todoToCategory = NSRelationshipDescription()
        todoToCategory.name = "category"
        todoToCategory.destinationEntity = categoryEntity
        todoToCategory.deleteRule = .nullifyDeleteRule
        todoToCategory.isOptional = true
        todoToCategory.minCount = 0
        todoToCategory.maxCount = 1

        catToTodos.inverseRelationship = todoToCategory
        todoToCategory.inverseRelationship = catToTodos

        // ── Relationships: TodoSection ↔ TodoItem ───────────────────────
        let sectionToTodos = NSRelationshipDescription()
        sectionToTodos.name = "todos"
        sectionToTodos.destinationEntity = todoEntity
        sectionToTodos.deleteRule = .nullifyDeleteRule
        sectionToTodos.isOptional = true
        sectionToTodos.minCount = 0
        sectionToTodos.maxCount = 0

        let todoToSection = NSRelationshipDescription()
        todoToSection.name = "section"
        todoToSection.destinationEntity = todoSectionEntity
        todoToSection.deleteRule = .nullifyDeleteRule
        todoToSection.isOptional = true
        todoToSection.minCount = 0
        todoToSection.maxCount = 1

        sectionToTodos.inverseRelationship = todoToSection
        todoToSection.inverseRelationship = sectionToTodos

        categoryEntity.properties += [catToSessions, catToTodos]
        sessionEntity.properties  += [sessionToCategory]
        todoEntity.properties     += [todoToCategory, todoToSection]
        todoSectionEntity.properties += [sectionToTodos]

        model.entities = [categoryEntity, sessionEntity, todoEntity, todoSectionEntity]
        return model
    }()

    private static func attr(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool = false
    ) -> NSAttributeDescription {
        let d = NSAttributeDescription()
        d.name = name
        d.attributeType = type
        d.isOptional = optional
        return d
    }
}
