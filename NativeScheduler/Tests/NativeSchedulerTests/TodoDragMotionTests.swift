import AppKit
import CoreData
import SwiftUI
import XCTest
@testable import NativeScheduler

final class TodoDragMotionTests: XCTestCase {
    func testAutoScrollUsesImmediateSixtyFrameCadence() {
        XCTAssertEqual(TodoDragMotion.frameInterval, .milliseconds(16))
    }

    func testAutoScrollPreservesSpeedAcrossFrameCadence() {
        XCTAssertEqual(TodoDragMotion.scrollDelta(depth: 0), 0.69, accuracy: 0.001)
        XCTAssertEqual(TodoDragMotion.scrollDelta(depth: 1), 3.45, accuracy: 0.001)
    }

    func testFullyNestedColumnKeepsVisibleRootDropTargetDuringItemDrag() {
        XCTAssertFalse(TodoDragMotion.isRootDropTargetVisible(draggingItemID: nil))
        XCTAssertTrue(TodoDragMotion.isRootDropTargetVisible(draggingItemID: UUID()))
        XCTAssertGreaterThanOrEqual(
            TodoDragMotion.rootDropTargetMinimumHeight,
            SchedulerControl.minimumTarget
        )
    }

    func testTaskDragResolverUsesStableGeometryForRootFolderAndReorder() {
        let sourceID = UUID()
        let targetID = UUID()
        let sectionID = UUID()
        let zones: [TodoTaskDropZone: CGRect] = [
            .root: CGRect(x: 0, y: 100, width: 200, height: 24),
            .folder(sectionID): CGRect(x: 0, y: 0, width: 200, height: 30),
            .item(id: targetID, sectionID: sectionID):
                CGRect(x: 0, y: 40, width: 200, height: 24),
            .item(id: sourceID, sectionID: sectionID):
                CGRect(x: 0, y: 70, width: 200, height: 24)
        ]

        XCTAssertEqual(
            TodoTaskDragResolver.destination(
                at: CGPoint(x: 100, y: 112),
                sourceID: sourceID,
                zones: zones
            ),
            .root
        )
        XCTAssertEqual(
            TodoTaskDragResolver.destination(
                at: CGPoint(x: 100, y: 15),
                sourceID: sourceID,
                zones: zones
            ),
            .folder(sectionID)
        )
        XCTAssertEqual(
            TodoTaskDragResolver.destination(
                at: CGPoint(x: 100, y: 52),
                sourceID: sourceID,
                zones: zones
            ),
            .before(itemID: targetID, sectionID: sectionID)
        )
        XCTAssertEqual(
            TodoTaskDragResolver.destination(
                at: CGPoint(x: 100, y: 82),
                sourceID: sourceID,
                zones: zones
            ),
            .none
        )
        XCTAssertEqual(
            TodoTaskDragResolver.destination(
                at: CGPoint(x: 300, y: 300),
                sourceID: sourceID,
                zones: zones
            ),
            .none
        )
    }

    func testFolderDragKeepsSourceVisibleAndCancelsOutsideDestinations() {
        let sourceID = UUID()
        let targetID = UUID()
        let ids = [sourceID, targetID]
        let zones = [
            TodoSectionDropZone(
                id: sourceID,
                frame: CGRect(x: 0, y: 0, width: 200, height: 40)
            ),
            TodoSectionDropZone(
                id: targetID,
                frame: CGRect(x: 0, y: 48, width: 200, height: 40)
            )
        ]

        XCTAssertEqual(
            TodoSectionDragResolver.visibleSectionIDs(ids, draggingSectionID: sourceID),
            ids
        )
        XCTAssertNil(
            TodoSectionDragResolver.destination(
                at: CGPoint(x: 300, y: 300),
                sourceID: sourceID,
                zones: zones
            )
        )
        XCTAssertEqual(
            TodoSectionDragResolver.destination(
                at: CGPoint(x: 100, y: 52),
                sourceID: sourceID,
                zones: zones
            ),
            .before(targetID)
        )
        XCTAssertEqual(
            TodoSectionDragResolver.destination(
                at: CGPoint(x: 100, y: 84),
                sourceID: sourceID,
                zones: zones
            ),
            .before(nil)
        )
    }

    func testTaskDropPreviewDoesNotDisplaceResolverGeometry() {
        XCTAssertEqual(TodoDropPreviewMetrics.layoutHeight, 0)
        XCTAssertGreaterThan(TodoDropPreviewMetrics.indicatorHeight, 0)
    }

    func testCondensedDensityGivesActiveTitlesMoreHorizontalSpace() {
        XCTAssertEqual(TodoListDensity.normal.activeColumnFraction, 0.5)
        XCTAssertEqual(TodoListDensity.condensed.activeColumnFraction, 0.6)
    }

    func testCompactControlsAndMetadataMeetAccessibilityMetrics() {
        XCTAssertEqual(NotchGeometry.shellMenuButtonSize, 24)
        XCTAssertEqual(Color.nsTextTertiary.hexString, "#858585")
        XCTAssertGreaterThanOrEqual(TimerAccessibilityMetrics.compactWarningFontSize, 10)
        XCTAssertGreaterThanOrEqual(TimerAccessibilityMetrics.compactWarningScaleFactor, 1)
        XCTAssertGreaterThanOrEqual(TodoSectionMetrics.itemCountFontSize, 10)
        XCTAssertGreaterThanOrEqual(TodoSectionMetrics.actionGlyphFontSize, 10)
    }

    func testTodoColumnsUseDistinctStableViewIdentities() {
        XCTAssertNotEqual(TodoColumnIdentity.active, TodoColumnIdentity.completed)
        XCTAssertEqual(TodoColumnIdentity.active.isCompletedColumn, false)
        XCTAssertEqual(TodoColumnIdentity.completed.isCompletedColumn, true)
    }

    @MainActor
    func testNestedTodoKeepsDragHandleInRootTrailingColumn() throws {
        let container = NSPersistentContainer(
            name: "NestedTodoTrailingColumn",
            managedObjectModel: CoreDataStack.model
        )
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        let rootItem = TodoEntity.create(
            title: "Root",
            priority: 0,
            in: container.viewContext
        )
        let nestedItem = TodoEntity.create(
            title: "Nested",
            priority: 1,
            in: container.viewContext
        )
        let root = VStack(alignment: .leading, spacing: 0) {
            TodoRowView(
                item: rootItem,
                onDragChanged: { _ in },
                onDragEnded: { _ in },
                onToggle: {},
                onDelete: {}
            )
            TodoRowView(
                item: nestedItem,
                isNested: true,
                onDragChanged: { _ in },
                onDragEnded: { _ in },
                onToggle: {},
                onDelete: {}
            )
            .padding(.leading, 16)
        }
        .frame(width: 320)
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 64)
        host.layoutSubtreeIfNeeded()

        let rootHandle = try XCTUnwrap(
            descendant(
                withAccessibilityIdentifier: "todo.task.drag.\(rootItem.id.uuidString)",
                in: host
            )
        )
        let nestedHandle = try XCTUnwrap(
            descendant(
                withAccessibilityIdentifier: "todo.task.drag.\(nestedItem.id.uuidString)",
                in: host
            )
        )
        let rootFrame = host.convert(rootHandle.bounds, from: rootHandle)
        let nestedFrame = host.convert(nestedHandle.bounds, from: nestedHandle)

        XCTAssertEqual(rootFrame.maxX, nestedFrame.maxX, accuracy: 0.5)
    }

    @MainActor
    private func descendant(
        withAccessibilityIdentifier identifier: String,
        in view: NSView
    ) -> NSView? {
        if view.accessibilityIdentifier() == identifier {
            return view
        }
        return view.subviews.lazy.compactMap {
            self.descendant(withAccessibilityIdentifier: identifier, in: $0)
        }.first
    }
}

final class TodoRealtimeTests: XCTestCase {
    @MainActor
    func testReturnSubmissionDoesNotClearTextEnteredBeforeDeferredCommit() async throws {
        let harness = try TodoPersistenceHarness(shouldFail: false)
        let vm = TodoViewModel(persistence: harness)
        vm.newTitle = "A"
        var submittedTitles: [String] = []
        let submitted = expectation(description: "Deferred submit completed")
        let coordinator = TodoTaskInputField.Coordinator(
            text: Binding(
                get: { vm.newTitle },
                set: { vm.newTitle = $0 }
            ),
            isFocused: .constant(true),
            onSubmit: { title in
                submittedTitles.append(title)
                vm.submit(title: title)
                submitted.fulfill()
            }
        )
        let field = NSTextField()
        field.stringValue = "A"

        coordinator.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: field)
        )
        XCTAssertTrue(coordinator.control(
            field,
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))

        field.stringValue = "B"
        coordinator.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: field)
        )

        await fulfillment(of: [submitted], timeout: 1)

        XCTAssertEqual(submittedTitles, ["A"])
        XCTAssertEqual(vm.items.map(\.title), ["A"])
        XCTAssertEqual(vm.newTitle, "B")
        XCTAssertEqual(field.stringValue, "B")
    }

    @MainActor
    func testSuccessfulTodoSaveDoesNotPersistUnrelatedUnsavedObjectsInAnotherContext() throws {
        let harness = try TodoPersistenceHarness(shouldFail: false, usesDedicatedTodoContext: true)
        let unrelatedContext = harness.viewContext
        _ = CategoryEntity.create(name: "Unsaved settings", colorHex: "#123456", sortOrder: 0, in: unrelatedContext)
        let vm = TodoViewModel(persistence: harness)

        XCTAssertNoThrow(try vm.add(title: "Durable Todo", section: nil, isCompleted: false).get())

        XCTAssertTrue(unrelatedContext.hasChanges)
        XCTAssertEqual(try harness.persistedCount(entityName: "TodoEntity"), 1)
        XCTAssertEqual(try harness.persistedCount(entityName: "CategoryEntity"), 0)
    }

    @MainActor
    func testFailedTodoSaveDoesNotRollbackUnrelatedUnsavedObjectsInAnotherContext() throws {
        let harness = try TodoPersistenceHarness(shouldFail: true, usesDedicatedTodoContext: true)
        let unrelatedContext = harness.viewContext
        let category = CategoryEntity.create(name: "Unsaved settings", colorHex: "#123456", sortOrder: 0, in: unrelatedContext)
        let vm = TodoViewModel(persistence: harness)

        assertSaveFailure(vm.add(title: "Rejected Todo", section: nil, isCompleted: false))

        XCTAssertTrue(unrelatedContext.hasChanges)
        XCTAssertFalse(category.isDeleted)
        XCTAssertEqual(category.name, "Unsaved settings")
        XCTAssertEqual(try harness.persistedCount(entityName: "CategoryEntity"), 0)
    }

    @MainActor
    func testCommittedRevisionCountsSuccessfulTodoMutationsAndNeverFailures() throws {
        let harness = try TodoPersistenceHarness(shouldFail: false)
        let vm = TodoViewModel(persistence: harness)
        XCTAssertEqual(vm.committedRevision, 0)

        try vm.add(title: "Task", section: nil, isCompleted: false).get()
        let item = try XCTUnwrap(vm.items.first)
        XCTAssertEqual(vm.committedRevision, 1)
        try vm.toggle(item).get()
        XCTAssertEqual(vm.committedRevision, 2)
        try vm.toggle(try XCTUnwrap(vm.items.first)).get()
        XCTAssertEqual(vm.committedRevision, 3)
        try vm.delete(try XCTUnwrap(vm.items.first)).get()
        XCTAssertEqual(vm.committedRevision, 4)

        harness.shouldFail = true
        assertSaveFailure(vm.add(title: "Failure", section: nil, isCompleted: false))
        XCTAssertEqual(vm.committedRevision, 4)
    }

    @MainActor
    func testSectionMutationsAndFailureHaveExactRevisions() throws {
        let harness = try TodoPersistenceHarness(shouldFail: false)
        let vm = TodoViewModel(persistence: harness)
        let first = try XCTUnwrap(try vm.addSection(title: "First", isCompletedSection: false).get())
        let second = try XCTUnwrap(try vm.addSection(title: "Second", isCompletedSection: false).get())
        XCTAssertEqual(vm.committedRevision, 2)

        try vm.add(title: "Member", section: first, isCompleted: false).get()
        XCTAssertEqual(vm.committedRevision, 3)
        try vm.renameSection(first, title: "Renamed").get()
        XCTAssertEqual(vm.committedRevision, 4)
        try vm.toggleSectionExpansion(first).get()
        XCTAssertEqual(vm.committedRevision, 5)
        try vm.moveSection(id: second.id, before: first.id, isCompletedSection: false).get()
        XCTAssertEqual(vm.committedRevision, 6)
        XCTAssertEqual(vm.sections.map(\.title), ["Second", "Renamed"])
        XCTAssertEqual(vm.sections.map(\.sortOrder), [0, 1])
        try vm.deleteSection(try XCTUnwrap(vm.sections.first(where: { $0.id == first.id }))).get()
        XCTAssertEqual(vm.committedRevision, 7)
        XCTAssertNil(vm.items.first?.section)

        harness.shouldFail = true
        let remaining = try XCTUnwrap(vm.sections.first)
        assertSaveFailure(vm.renameSection(remaining, title: "Rejected"))
        XCTAssertEqual(vm.committedRevision, 7)
        XCTAssertEqual(vm.sections.first?.title, "Second")
    }

    @MainActor
    func testDeletingFolderPromotesEveryMemberAndCompactsRemainingFolderOrder() throws {
        let harness = try TodoPersistenceHarness(shouldFail: false)
        let vm = TodoViewModel(persistence: harness)
        let first = try XCTUnwrap(try vm.addSection(title: "First", isCompletedSection: false).get())
        _ = try XCTUnwrap(try vm.addSection(title: "Second", isCompletedSection: false).get())
        try vm.add(title: "A", section: first, isCompleted: false).get()
        try vm.add(title: "B", section: first, isCompleted: false).get()

        try vm.deleteSection(first).get()

        XCTAssertEqual(vm.sections.map(\.title), ["Second"])
        XCTAssertEqual(vm.sections.map(\.sortOrder), [0])
        XCTAssertTrue(vm.items.allSatisfy { $0.section == nil })

        _ = try XCTUnwrap(try vm.addSection(title: "Third", isCompletedSection: false).get())
        XCTAssertEqual(vm.sections.map(\.title), ["Second", "Third"])
        XCTAssertEqual(vm.sections.map(\.sortOrder), [0, 1])
    }

    @MainActor
    func testEveryFailedSectionMutationRollsBackWithoutAdvancingRevision() throws {
        let harness = try TodoPersistenceHarness(shouldFail: false)
        let first = TodoSectionEntity.create(title: "First", isCompletedSection: false, sortOrder: 0, in: harness.viewContext)
        let second = TodoSectionEntity.create(title: "Second", isCompletedSection: false, sortOrder: 1, in: harness.viewContext)
        let item = TodoEntity.create(title: "Member", priority: 0, section: first, in: harness.viewContext)
        try harness.viewContext.save()
        let firstID = first.id
        let secondID = second.id
        let itemID = item.id
        harness.shouldFail = true
        let vm = TodoViewModel(persistence: harness)

        switch vm.addSection(title: "Rejected", isCompletedSection: false) {
        case .success: XCTFail("Expected section creation failure")
        case .failure(let error): XCTAssertEqual(error, .saveFailed("forced save failure"))
        }
        XCTAssertEqual(vm.committedRevision, 0)

        assertSaveFailure(vm.renameSection(try section(firstID, in: vm), title: "Rejected"))
        XCTAssertEqual(vm.sections.first(where: { $0.id == firstID })?.title, "First")
        XCTAssertEqual(vm.committedRevision, 0)

        assertSaveFailure(vm.toggleSectionExpansion(try section(firstID, in: vm)))
        XCTAssertEqual(vm.sections.first(where: { $0.id == firstID })?.isExpanded, true)
        XCTAssertEqual(vm.committedRevision, 0)

        assertSaveFailure(vm.moveSection(id: secondID, before: firstID, isCompletedSection: false))
        XCTAssertEqual(vm.sections.map(\.id), [firstID, secondID])
        XCTAssertEqual(vm.committedRevision, 0)

        assertSaveFailure(vm.deleteSection(try section(firstID, in: vm)))
        XCTAssertEqual(vm.sections.map(\.id), [firstID, secondID])
        XCTAssertEqual(vm.items.first(where: { $0.id == itemID })?.section?.id, firstID)
        XCTAssertEqual(vm.committedRevision, 0)
    }

    @MainActor
    func testCrossFolderAndUnsectionedMovesPreserveStableOrdering() throws {
        let harness = try TodoPersistenceHarness(shouldFail: false)
        let vm = TodoViewModel(persistence: harness)
        let alpha = try XCTUnwrap(try vm.addSection(title: "Alpha", isCompletedSection: false).get())
        let beta = try XCTUnwrap(try vm.addSection(title: "Beta", isCompletedSection: false).get())
        try vm.add(title: "A", section: alpha, isCompleted: false).get()
        try vm.add(title: "B", section: alpha, isCompleted: false).get()
        try vm.add(title: "C", section: beta, isCompleted: false).get()
        try vm.add(title: "D", section: nil, isCompleted: false).get()

        let a = try XCTUnwrap(vm.items.first(where: { $0.title == "A" }))
        let c = try XCTUnwrap(vm.items.first(where: { $0.title == "C" }))
        let d = try XCTUnwrap(vm.items.first(where: { $0.title == "D" }))
        try vm.moveActiveItem(id: a.id, before: c.id, in: beta).get()
        try vm.moveActiveItem(id: c.id, before: d.id, in: nil).get()

        XCTAssertEqual(vm.items.map(\.title), ["B", "A", "C", "D"])
        XCTAssertEqual(vm.items.map(\.priority), [0, 1, 2, 3])
        XCTAssertEqual(vm.items.first(where: { $0.title == "A" })?.section?.title, "Beta")
        XCTAssertNil(vm.items.first(where: { $0.title == "C" })?.section)
        XCTAssertEqual(vm.committedRevision, 8)
    }

    @MainActor
    func testFailedCrossFolderMoveRestoresMembershipAndOrderingWithoutRevision() throws {
        let harness = try TodoPersistenceHarness(shouldFail: false)
        let alpha = TodoSectionEntity.create(title: "Alpha", isCompletedSection: false, sortOrder: 0, in: harness.viewContext)
        let beta = TodoSectionEntity.create(title: "Beta", isCompletedSection: false, sortOrder: 1, in: harness.viewContext)
        let first = TodoEntity.create(title: "First", priority: 0, section: alpha, in: harness.viewContext)
        let second = TodoEntity.create(title: "Second", priority: 1, section: beta, in: harness.viewContext)
        try harness.viewContext.save()
        let firstID = first.id
        let secondID = second.id
        harness.shouldFail = true
        let vm = TodoViewModel(persistence: harness)

        assertSaveFailure(vm.moveActiveItem(id: firstID, before: secondID, in: try section(beta.id, in: vm)))

        XCTAssertEqual(vm.items.map(\.id), [firstID, secondID])
        XCTAssertEqual(vm.items.map(\.priority), [0, 1])
        XCTAssertEqual(vm.items.first(where: { $0.id == firstID })?.section?.id, alpha.id)
        XCTAssertEqual(vm.committedRevision, 0)
    }

    @MainActor
    func testNoOpMutationDoesNotAdvanceCommittedRevision() throws {
        let harness = try TodoPersistenceHarness(shouldFail: false)
        let vm = TodoViewModel(persistence: harness)
        try vm.add(title: "Only", section: nil, isCompleted: false).get()
        let revision = vm.committedRevision
        let item = try XCTUnwrap(vm.items.first)

        try vm.moveActiveItem(id: item.id, before: item.id).get()

        XCTAssertEqual(vm.committedRevision, revision)
    }

    @MainActor
    func testSQLiteRelaunchPersistsTodoSectionMembershipExpansionAndOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Todo.sqlite")

        do {
            let harness = try TodoPersistenceHarness(shouldFail: false, storeURL: storeURL)
            let vm = TodoViewModel(persistence: harness)
            let alpha = try XCTUnwrap(try vm.addSection(title: "Alpha", isCompletedSection: false).get())
            let beta = try XCTUnwrap(try vm.addSection(title: "Beta", isCompletedSection: false).get())
            try vm.toggleSectionExpansion(alpha).get()
            try vm.moveSection(id: beta.id, before: alpha.id, isCompletedSection: false).get()
            try vm.add(title: "Open", section: alpha, isCompleted: false).get()
            try vm.add(title: "Done", section: nil, isCompleted: false).get()
            try vm.toggle(try XCTUnwrap(vm.items.first(where: { $0.title == "Done" }))).get()
        }

        let relaunched = try TodoPersistenceHarness(shouldFail: false, storeURL: storeURL)
        let vm = TodoViewModel(persistence: relaunched)
        XCTAssertEqual(vm.sections.map(\.title), ["Beta", "Alpha"])
        XCTAssertEqual(vm.sections.map(\.sortOrder), [0, 1])
        XCTAssertEqual(vm.sections.first(where: { $0.title == "Alpha" })?.isExpanded, false)
        XCTAssertEqual(vm.items.map(\.title), ["Open", "Done"])
        XCTAssertEqual(vm.items.map(\.isCompleted), [false, true])
        XCTAssertEqual(vm.items.first(where: { $0.title == "Open" })?.section?.title, "Alpha")
    }

    @MainActor
    func testAddRollsBackAndPublishesSaveFailure() throws {
        let harness = try TodoPersistenceHarness()
        let vm = TodoViewModel(persistence: harness)

        let result = vm.add(title: "Unsaved", section: nil, isCompleted: false)

        assertSaveFailure(result)
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertEqual(vm.persistenceError, .saveFailed("forced save failure"))
    }

    @MainActor
    func testDeleteThenAddKeepsActivePrioritiesUniqueAndContiguous() throws {
        let harness = try TodoPersistenceHarness(shouldFail: false)
        _ = TodoEntity.create(title: "A", priority: 0, in: harness.viewContext)
        _ = TodoEntity.create(title: "B", priority: 1, in: harness.viewContext)
        _ = TodoEntity.create(title: "C", priority: 2, in: harness.viewContext)
        try harness.viewContext.save()
        let vm = TodoViewModel(persistence: harness)

        _ = vm.delete(try XCTUnwrap(vm.items.first(where: { $0.title == "B" })))
        _ = vm.add(title: "D", section: nil, isCompleted: false)
        vm.reload()

        XCTAssertEqual(vm.items.filter { !$0.isCompleted }.map(\.title), ["A", "C", "D"])
        XCTAssertEqual(vm.items.filter { !$0.isCompleted }.map(\.priority), [0, 1, 2])
    }

    @MainActor
    func testToggleAppendsToTargetCompletionGroupWithoutPriorityCollision() throws {
        let harness = try TodoPersistenceHarness(shouldFail: false)
        _ = TodoEntity.create(title: "Active A", priority: 0, in: harness.viewContext)
        _ = TodoEntity.create(title: "Active B", priority: 1, in: harness.viewContext)
        let completedA = TodoEntity.create(title: "Done A", priority: 0, in: harness.viewContext)
        completedA.isCompleted = true
        let completedB = TodoEntity.create(title: "Done B", priority: 1, in: harness.viewContext)
        completedB.isCompleted = true
        try harness.viewContext.save()
        let vm = TodoViewModel(persistence: harness)

        _ = vm.toggle(try XCTUnwrap(vm.items.first(where: { $0.title == "Active B" })))
        vm.reload()

        let completed = vm.items.filter(\.isCompleted)
        XCTAssertEqual(completed.map(\.title), ["Done A", "Done B", "Active B"])
        XCTAssertEqual(completed.map(\.priority), [0, 1, 2])
    }

    @MainActor
    func testSettingsRollbackCannotDiscardUnrelatedViewContextChanges() throws {
        let harness = try TodoPersistenceHarness(shouldFail: false)
        let unsavedTask = TodoEntity.create(
            title: "Keep unsaved",
            priority: 0,
            in: harness.viewContext
        )
        let coordinator = try XCTUnwrap(harness.viewContext.persistentStoreCoordinator)
        let settingsContext = CoreDataStack.makeIsolatedMainContext(
            persistentStoreCoordinator: coordinator,
            name: "NativeScheduler.settings"
        )
        _ = CategoryEntity.create(
            name: "Discard category",
            colorHex: "#4FAFFF",
            sortOrder: 0,
            in: settingsContext
        )

        settingsContext.rollback()

        XCTAssertTrue(harness.viewContext.hasChanges)
        XCTAssertFalse(unsavedTask.isDeleted)
        XCTAssertEqual(unsavedTask.title, "Keep unsaved")
        XCTAssertFalse(settingsContext.hasChanges)
        XCTAssertEqual(settingsContext.name, "NativeScheduler.settings")
    }

    @MainActor
    func testToggleRollsBackAndPublishesSaveFailure() throws {
        let harness = try TodoPersistenceHarness()
        let item = TodoEntity.create(title: "Existing", priority: 0, in: harness.viewContext)
        try harness.viewContext.save()
        let id = item.id
        let vm = TodoViewModel(persistence: harness)

        let result = vm.toggle(try XCTUnwrap(vm.items.first))

        assertSaveFailure(result)
        let reloaded = try XCTUnwrap(vm.items.first(where: { $0.id == id }))
        XCTAssertFalse(reloaded.isCompleted)
        XCTAssertNil(reloaded.completedAt)
        XCTAssertEqual(vm.persistenceError, .saveFailed("forced save failure"))
    }

    @MainActor
    func testDeleteRollsBackAndPublishesSaveFailure() throws {
        let harness = try TodoPersistenceHarness()
        let item = TodoEntity.create(title: "Existing", priority: 0, in: harness.viewContext)
        try harness.viewContext.save()
        let id = item.id
        let vm = TodoViewModel(persistence: harness)

        let result = vm.delete(try XCTUnwrap(vm.items.first))

        assertSaveFailure(result)
        XCTAssertEqual(vm.items.map(\.id), [id])
        XCTAssertEqual(vm.persistenceError, .saveFailed("forced save failure"))
    }

    @MainActor
    func testOrderingMutationRollsBackAndPublishesSaveFailure() throws {
        let harness = try TodoPersistenceHarness()
        let first = TodoEntity.create(title: "First", priority: 0, in: harness.viewContext)
        let second = TodoEntity.create(title: "Second", priority: 1, in: harness.viewContext)
        try harness.viewContext.save()
        let originalOrder = [first.id, second.id]
        let vm = TodoViewModel(persistence: harness)

        let result = vm.moveActiveItem(id: second.id, before: first.id)

        assertSaveFailure(result)
        XCTAssertEqual(vm.items.map(\.id), originalOrder)
        XCTAssertEqual(vm.items.map(\.priority), [0, 1])
        XCTAssertEqual(vm.persistenceError, .saveFailed("forced save failure"))
    }

    @MainActor
    func testPersistenceFailureRendersAccessibleTaskInputStatus() throws {
        let vm = TodoViewModel(persistence: try TodoPersistenceHarness())
        assertSaveFailure(vm.add(title: "Unsaved", section: nil, isCompleted: false))
        NSApplication.shared.finishLaunching()
        let error = try XCTUnwrap(vm.persistenceError)
        let frame = NSRect(x: 0, y: 0, width: 20, height: 20)
        let host = NSHostingView(rootView: TodoPersistenceErrorIndicator(error: error))
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }

        host.frame = frame
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        XCTAssertGreaterThan(host.fittingSize.width, 0)
        XCTAssertGreaterThan(host.fittingSize.height, 0)
        XCTAssertFalse(TodoPersistenceErrorIndicator.accessibilityIdentifier.isEmpty)
        let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: image)
        XCTAssertNotNil(image.representation(using: .png, properties: [:]))
    }

    @MainActor
    func testFailedSubmissionRestoresOnlyWhenThereIsNoNewerDraft() throws {
        let emptyDraftVM = TodoViewModel(persistence: try TodoPersistenceHarness())
        assertSaveFailure(emptyDraftVM.submit(title: "A"))
        XCTAssertEqual(emptyDraftVM.newTitle, "A")

        let newerDraftVM = TodoViewModel(persistence: try TodoPersistenceHarness())
        newerDraftVM.newTitle = "B"
        assertSaveFailure(newerDraftVM.submit(title: "A"))
        XCTAssertEqual(newerDraftVM.newTitle, "B")
    }

    @MainActor
    private func section(
        _ id: UUID,
        in vm: TodoViewModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TodoSectionEntity {
        try XCTUnwrap(vm.sections.first(where: { $0.id == id }), file: file, line: line)
    }

    private func assertSaveFailure(
        _ result: Result<Void, TodoPersistenceError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .success:
            XCTFail("Expected save failure", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error, .saveFailed("forced save failure"), file: file, line: line)
        }
    }
}

@MainActor
private final class TodoPersistenceHarness: TodoPersistence {
    let viewContext: NSManagedObjectContext
    private let container: NSPersistentContainer
    private let usesDedicatedTodoContext: Bool
    var shouldFail: Bool

    init(
        shouldFail: Bool = true,
        usesDedicatedTodoContext: Bool = false,
        storeURL: URL? = nil
    ) throws {
        self.shouldFail = shouldFail
        self.usesDedicatedTodoContext = usesDedicatedTodoContext
        container = NSPersistentContainer(
            name: "TodoRealtimeTests",
            managedObjectModel: CoreDataStack.model
        )
        let description = storeURL.map(NSPersistentStoreDescription.init(url:)) ?? NSPersistentStoreDescription()
        if storeURL == nil { description.type = NSInMemoryStoreType }
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        viewContext = container.viewContext
    }

    func makeTodoContext() -> NSManagedObjectContext {
        guard usesDedicatedTodoContext else { return viewContext }
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = container.persistentStoreCoordinator
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        return context
    }

    func save(context: NSManagedObjectContext?) -> Result<Void, Error> {
        guard !shouldFail else {
            return .failure(TodoTestError.forcedSaveFailure)
        }
        let context = context ?? viewContext
        return context.performAndWait { Result { try context.save() } }
    }

    func persistedCount(entityName: String) throws -> Int {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = container.persistentStoreCoordinator
        return try context.performAndWait {
            try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: entityName))
        }
    }
}

private enum TodoTestError: LocalizedError {
    case forcedSaveFailure

    var errorDescription: String? { "forced save failure" }
}
