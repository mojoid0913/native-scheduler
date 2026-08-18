// NativeScheduler/Sources/NativeScheduler/Models/ManagedObjects.swift
import CoreData
import Foundation

// MARK: - CategoryEntity

@objc(CategoryEntity)
public class CategoryEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var colorHex: String
    @NSManaged public var createdAt: Date
    @NSManaged public var sortOrder: Int32
    @NSManaged public var sessions: NSSet?
    @NSManaged public var todos: NSSet?

    static func create(name: String, colorHex: String, sortOrder: Int32, in ctx: NSManagedObjectContext) -> CategoryEntity {
        let e = CategoryEntity(context: ctx)
        e.id = UUID()
        e.name = name
        e.colorHex = colorHex
        e.createdAt = Date()
        e.sortOrder = sortOrder
        return e
    }

    static func fetchAll(in ctx: NSManagedObjectContext) -> [CategoryEntity] {
        let req = NSFetchRequest<CategoryEntity>(entityName: "CategoryEntity")
        req.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        return (try? ctx.fetch(req)) ?? []
    }
}

// MARK: - SessionEntity

@objc(SessionEntity)
public class SessionEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var startTime: Date
    @NSManaged public var endTime: Date?
    @NSManaged public var timerMode: String   // "duration" | "endTime" | "countUp"
    @NSManaged public var category: CategoryEntity?

    var isRunning: Bool { endTime == nil }

    static func create(startTime: Date, mode: TimerMode, category: CategoryEntity?, in ctx: NSManagedObjectContext) -> SessionEntity {
        let e = SessionEntity(context: ctx)
        e.id = UUID()
        e.startTime = startTime
        e.timerMode = mode.rawValue
        e.category = category
        return e
    }

    /// All sessions whose time range overlaps the given heatmap slot.
    static func sessions(forSlot slot: HeatmapSlot, in ctx: NSManagedObjectContext) -> [SessionEntity] {
        let req = NSFetchRequest<SessionEntity>(entityName: "SessionEntity")
        let (start, end) = slot.dateRange
        req.predicate = NSPredicate(
            format: "startTime < %@ AND (endTime == nil OR endTime > %@)",
            end as NSDate, start as NSDate
        )
        return (try? ctx.fetch(req)) ?? []
    }
}

// MARK: - TodoEntity

@objc(TodoEntity)
public class TodoEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var isCompleted: Bool
    @NSManaged public var priority: Int32
    @NSManaged public var createdAt: Date
    @NSManaged public var completedAt: Date?
    @NSManaged public var category: CategoryEntity?
    @NSManaged public var section: TodoSectionEntity?

    static func create(
        title: String,
        priority: Int32,
        section: TodoSectionEntity? = nil,
        isCompleted: Bool = false,
        in ctx: NSManagedObjectContext
    ) -> TodoEntity {
        let e = TodoEntity(context: ctx)
        e.id = UUID()
        e.title = title
        e.isCompleted = isCompleted
        e.priority = priority
        e.createdAt = Date()
        e.completedAt = isCompleted ? Date() : nil
        e.section = section
        return e
    }

    static func fetchAll(in ctx: NSManagedObjectContext) -> [TodoEntity] {
        let req = NSFetchRequest<TodoEntity>(entityName: "TodoEntity")
        req.sortDescriptors = [
            NSSortDescriptor(key: "isCompleted", ascending: true),
            NSSortDescriptor(key: "priority", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true),
            NSSortDescriptor(key: "id", ascending: true)
        ]
        return (try? ctx.fetch(req)) ?? []
    }
}

// MARK: - TodoSectionEntity

@objc(TodoSectionEntity)
public class TodoSectionEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var isCompletedSection: Bool
    @NSManaged public var isExpanded: Bool
    @NSManaged public var sortOrder: Int32
    @NSManaged public var createdAt: Date
    @NSManaged public var todos: NSSet?

    static func create(title: String, isCompletedSection: Bool, sortOrder: Int32, in ctx: NSManagedObjectContext) -> TodoSectionEntity {
        let e = TodoSectionEntity(context: ctx)
        e.id = UUID()
        e.title = title
        e.isCompletedSection = isCompletedSection
        e.isExpanded = true
        e.sortOrder = sortOrder
        e.createdAt = Date()
        return e
    }

    static func fetchAll(in ctx: NSManagedObjectContext) -> [TodoSectionEntity] {
        let req = NSFetchRequest<TodoSectionEntity>(entityName: "TodoSectionEntity")
        req.sortDescriptors = [
            NSSortDescriptor(key: "isCompletedSection", ascending: true),
            NSSortDescriptor(key: "sortOrder", ascending: true)
        ]
        return (try? ctx.fetch(req)) ?? []
    }
}

// MARK: - Supporting types

enum TimerMode: String, CaseIterable {
    case duration = "duration"
    case endTime  = "endTime"
    case countUp  = "countUp"

    var label: String {
        switch self {
        case .duration: return "Duration"
        case .endTime:  return "End Time"
        case .countUp:  return "Count Up"
        }
    }
}

struct HeatmapSlot: Hashable {
    let hour: Int   // 0–23
    let row:  Int   // 0–3  (row * 15 = minute offset)

    static let rowsPerHour = 4
    static let minutesPerSlot = 15

    var index: Int { hour * Self.rowsPerHour + row }
    var minuteOffset: Int { row * Self.minutesPerSlot }

    var dateRange: (Date, Date) {
        dateRange(on: Date(), calendar: .current)
    }

    func dateRange(on date: Date, calendar: Calendar) -> (Date, Date) {
        let startOfDay = calendar.startOfDay(for: date)
        let startMinutes = (hour * 60) + minuteOffset

        guard
            let start = calendar.date(byAdding: .minute, value: startMinutes, to: startOfDay),
            let end = calendar.date(byAdding: .minute, value: Self.minutesPerSlot, to: start)
        else {
            preconditionFailure("Unable to resolve heatmap slot date range for hour \(hour), row \(row)")
        }

        return (start, end)
    }

    static let all: [HeatmapSlot] = (0..<24).flatMap { hour in
        (0..<rowsPerHour).map { row in HeatmapSlot(hour: hour, row: row) }
    }
}
