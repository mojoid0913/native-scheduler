// NativeScheduler/Sources/NativeScheduler/Features/Todo/TodoViewModel.swift
import Foundation
import CoreData
import Combine

@MainActor
protocol TodoPersistence: AnyObject {
    var viewContext: NSManagedObjectContext { get }
    func makeTodoContext() -> NSManagedObjectContext
    func save(context: NSManagedObjectContext?) -> Result<Void, Error>
}

extension TodoPersistence {
    func makeTodoContext() -> NSManagedObjectContext { viewContext }
}

extension CoreDataStack: TodoPersistence {}

enum TodoPersistenceError: Error, Equatable {
    case saveFailed(String)
}

@MainActor
final class TodoViewModel: ObservableObject {
    @Published private(set) var items: [TodoEntity] = []
    @Published private(set) var sections: [TodoSectionEntity] = []
    @Published var newTitle: String = ""
    @Published private(set) var persistenceError: TodoPersistenceError?
    @Published private(set) var committedRevision: UInt64 = 0

    private let persistence: any TodoPersistence
    private let context: NSManagedObjectContext

    init() {
        let persistence = CoreDataStack.shared
        self.persistence = persistence
        context = persistence.makeTodoContext()
        reload()
    }

    init(persistence: any TodoPersistence) {
        self.persistence = persistence
        context = persistence.makeTodoContext()
        reload()
    }

    func reload() {
        items = TodoEntity.fetchAll(in: context)
        sections = TodoSectionEntity.fetchAll(in: context)
    }

    func add() {
        _ = submit(title: newTitle)
    }

    @discardableResult
    func submit(title: String) -> Result<Void, TodoPersistenceError> {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return .success(()) }

        let result = add(title: trimmedTitle, section: nil, isCompleted: false)
        switch result {
        case .success:
            if newTitle == title {
                newTitle = ""
            }
        case .failure:
            if newTitle.isEmpty || newTitle == title {
                newTitle = title
            }
        }
        return result
    }

    @discardableResult
    func add(
        title: String,
        section: TodoSectionEntity?,
        isCompleted: Bool
    ) -> Result<Void, TodoPersistenceError> {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return .success(()) }
        let nextPriority = nextPriority(isCompleted: isCompleted)
        _ = TodoEntity.create(
            title: trimmedTitle,
            priority: nextPriority,
            section: section,
            isCompleted: isCompleted,
            in: context
        )
        return persistChanges()
    }

    @discardableResult
    func toggle(_ item: TodoEntity) -> Result<Void, TodoPersistenceError> {
        let sourceCompletionState = item.isCompleted
        item.isCompleted = !item.isCompleted
        item.completedAt = item.isCompleted ? Date() : nil
        if item.section?.isCompletedSection != item.isCompleted {
            item.section = nil
        }
        compactPriorities(isCompleted: sourceCompletionState)
        item.priority = nextPriority(isCompleted: item.isCompleted, excluding: item.id)
        return persistChanges()
    }

    @discardableResult
    func delete(_ item: TodoEntity) -> Result<Void, TodoPersistenceError> {
        let completionState = item.isCompleted
        context.delete(item)
        compactPriorities(isCompleted: completionState)
        return persistChanges()
    }

    @discardableResult
    func addSection(
        title: String,
        isCompletedSection: Bool
    ) -> Result<TodoSectionEntity?, TodoPersistenceError> {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return .success(nil) }

        let nextOrder = Int32(sections.filter { $0.isCompletedSection == isCompletedSection }.count)
        let section = TodoSectionEntity.create(
            title: trimmedTitle,
            isCompletedSection: isCompletedSection,
            sortOrder: nextOrder,
            in: context
        )
        return persistChanges().map { section }
    }

    @discardableResult
    func deleteSection(_ section: TodoSectionEntity) -> Result<Void, TodoPersistenceError> {
        for item in items where item.section?.objectID == section.objectID {
            item.section = nil
        }
        context.delete(section)
        let remainingSections = sections.filter {
            $0.objectID != section.objectID &&
                $0.isCompletedSection == section.isCompletedSection
        }
        for (index, remainingSection) in remainingSections.enumerated() {
            remainingSection.sortOrder = Int32(index)
        }
        return persistChanges()
    }

    @discardableResult
    func renameSection(
        _ section: TodoSectionEntity,
        title: String
    ) -> Result<Void, TodoPersistenceError> {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return .success(()) }
        section.title = trimmedTitle
        return persistChanges()
    }

    @discardableResult
    func toggleSectionExpansion(_ section: TodoSectionEntity) -> Result<Void, TodoPersistenceError> {
        section.isExpanded.toggle()
        return persistChanges()
    }

    @discardableResult
    func moveSection(
        id: UUID,
        before targetID: UUID?,
        isCompletedSection: Bool
    ) -> Result<Void, TodoPersistenceError> {
        var columnSections = sections.filter { $0.isCompletedSection == isCompletedSection }
        guard targetID != id,
              let fromIndex = columnSections.firstIndex(where: { $0.id == id }) else {
            return .success(())
        }
        let originalOrder = columnSections.map(\.id)

        let section = columnSections.remove(at: fromIndex)
        let targetIndex = targetID.flatMap { id in
            columnSections.firstIndex(where: { $0.id == id })
        } ?? columnSections.count

        columnSections.insert(section, at: targetIndex)
        guard columnSections.map(\.id) != originalOrder else { return .success(()) }
        for (index, section) in columnSections.enumerated() {
            section.sortOrder = Int32(index)
        }
        return persistChanges()
    }

    @discardableResult
    func move(from source: IndexSet, to dest: Int) -> Result<Void, TodoPersistenceError> {
        var active = items.filter { !$0.isCompleted }
        // Guard: source indices and dest must be within active's bounds.
        // vm.items includes completed items at the tail, so onMove can hand us
        // indices or a dest that exceed active.count — applying them directly
        // to the filtered array would trigger Array.move's precondition failure.
        let safeSource = IndexSet(source.filter { $0 < active.count })
        let safeDest = min(dest, active.count)
        guard !safeSource.isEmpty else { return .success(()) }
        let originalOrder = active.map(\.id)
        active.move(fromOffsets: safeSource, toOffset: safeDest)
        guard active.map(\.id) != originalOrder else { return .success(()) }
        for (index, item) in active.enumerated() {
            item.priority = Int32(index)
        }
        return persistChanges()
    }

    @discardableResult
    func moveActiveItem(
        id: UUID,
        before targetID: UUID?,
        in section: TodoSectionEntity? = nil
    ) -> Result<Void, TodoPersistenceError> {
        var active = items.filter { !$0.isCompleted }
        guard targetID != id,
              let fromIndex = active.firstIndex(where: { $0.id == id }) else {
            return .success(())
        }
        let originalOrder = active.map(\.id)

        let item = active.remove(at: fromIndex)
        let targetItem = targetID.flatMap { id in
            active.first(where: { $0.id == id })
        }
        let targetIndex = targetItem.flatMap { target in
            active.firstIndex(where: { $0.id == target.id })
        } ?? active.count

        let destinationSection = section ?? targetItem?.section
        active.insert(item, at: targetIndex)
        guard active.map(\.id) != originalOrder ||
                item.section?.objectID != destinationSection?.objectID else {
            return .success(())
        }
        item.section = destinationSection
        for (index, item) in active.enumerated() {
            item.priority = Int32(index)
        }
        return persistChanges()
    }

    private func nextPriority(
        isCompleted: Bool,
        excluding excludedID: UUID? = nil
    ) -> Int32 {
        let maximum = items
            .filter {
                !$0.isDeleted &&
                    $0.isCompleted == isCompleted &&
                    $0.id != excludedID
            }
            .map(\.priority)
            .max() ?? -1
        return maximum + 1
    }

    private func compactPriorities(isCompleted: Bool) {
        let orderedItems = items
            .filter { !$0.isDeleted && $0.isCompleted == isCompleted }
            .sorted {
                if $0.priority != $1.priority {
                    return $0.priority < $1.priority
                }
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt < $1.createdAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
        for (index, item) in orderedItems.enumerated() {
            item.priority = Int32(index)
        }
    }

    private func persistChanges() -> Result<Void, TodoPersistenceError> {
        guard context.hasChanges else { return .success(()) }
        switch persistence.save(context: context) {
        case .success:
            persistenceError = nil
            committedRevision += 1
            reload()
            return .success(())
        case .failure(let error):
            context.rollback()
            reload()
            let persistenceError = TodoPersistenceError.saveFailed(error.localizedDescription)
            self.persistenceError = persistenceError
            return .failure(persistenceError)
        }
    }
}
