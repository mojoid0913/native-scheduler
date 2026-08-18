// NativeScheduler/Sources/NativeScheduler/Features/Todo/TodoListView.swift
@preconcurrency import AppKit
import ObjectiveC
import SwiftUI
import UniformTypeIdentifiers

enum TodoListDensity: Equatable {
    case normal
    case condensed

    var showsMoveHandles: Bool {
        true
    }

    var activeColumnFraction: CGFloat {
        self == .condensed ? 0.6 : 0.5
    }
}

enum TodoColumnIdentity: Hashable {
    case active
    case completed

    var isCompletedColumn: Bool {
        self == .completed
    }
}

enum TodoSectionMetrics {
    static let itemCountFontSize: CGFloat = 10
    static let actionGlyphFontSize: CGFloat = 10
}

enum TodoFolderActionVisibility {
    static func isVisible(isHovered: Bool, isDragActive: Bool) -> Bool {
        isHovered && !isDragActive
    }
}

struct TodoListView: View {
    @ObservedObject var vm: TodoViewModel
    var density: TodoListDensity = .normal
    @State private var draggingItemID: UUID?
    @State private var draggingSectionID: UUID?
    @State private var dropIntent: TodoDropIntent = .none
    @State private var lastDropY: CGFloat = 0
    @State private var dropIndex: Int?
    @State private var taskDropZones: [TodoTaskDropZone: CGRect] = [:]
    @State private var sectionDropZones: [TodoSectionDropZone] = []
    @State private var activeContentMinY: CGFloat = 0
    @State private var dragResetTask: Task<Void, Never>?
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var autoScrollDirection: TodoAutoScrollDirection?
    @State private var autoScrollIndex: Int?
    @State private var autoScrollVelocity: CGFloat = 0
    @State private var activeScrollView: NSScrollView?
    @State private var editingSectionID: UUID?
    @State private var editingSectionTitle = ""
    @State private var draftSectionColumn: Bool?
    @State private var draftSectionTitle = ""
    @State private var isAddFieldFocused = false

    private var activeItems: [TodoEntity] {
        vm.items.filter { !$0.isCompleted }
    }

    private var completedItems: [TodoEntity] {
        vm.items.filter(\.isCompleted)
    }

    private var activeSections: [TodoSectionEntity] {
        vm.sections.filter { !$0.isCompletedSection }
    }

    private var completedSections: [TodoSectionEntity] {
        vm.sections.filter(\.isCompletedSection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Tasks")
                    .font(SchedulerType.cardTitle)
                    .foregroundColor(.nsTextPrimary)
                    .lineLimit(1)

                Spacer()

                Text("\(activeItems.count) left")
                    .font(SchedulerType.monospacedMetadata)
                    .foregroundColor(.nsTextTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, SchedulerSpacing.cardInset)
            .padding(.top, SchedulerSpacing.cardInset)
            .padding(.bottom, SchedulerSpacing.sm)

            GeometryReader { geometry in
                let availableWidth = max(0, geometry.size.width - 9)
                let activeWidth = availableWidth * density.activeColumnFraction
                HStack(alignment: .top, spacing: 8) {
                    todoColumn(
                        title: "Left",
                        items: activeItems,
                        sections: activeSections,
                        isCompletedColumn: TodoColumnIdentity.active.isCompletedColumn,
                        showsMoveControls: true
                    )
                    .id(TodoColumnIdentity.active)
                    .frame(width: activeWidth)
                    .frame(maxHeight: .infinity, alignment: .top)

                    Divider()
                        .background(Color.nsBorder.opacity(0.72))
                        .padding(.vertical, SchedulerSpacing.xxs)

                    todoColumn(
                        title: "Done",
                        items: completedItems,
                        sections: completedSections,
                        isCompletedColumn: TodoColumnIdentity.completed.isCompletedColumn,
                        showsMoveControls: false
                    )
                    .id(TodoColumnIdentity.completed)
                    .frame(width: max(0, availableWidth - activeWidth))
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }

            Divider().background(Color.nsBorder.opacity(0.72))

            addTaskRow
        }
        .schedulerCardSurface()
        .onPreferenceChange(TodoTaskDropZonePreferenceKey.self) { zones in
            taskDropZones = zones
        }
        .onPreferenceChange(TodoSectionDropZonePreferenceKey.self) { zones in
            sectionDropZones = zones
        }
        .onDisappear {
            finishTaskDrag()
        }
    }

    private func todoColumn(
        title: String,
        items: [TodoEntity],
        sections: [TodoSectionEntity],
        isCompletedColumn: Bool,
        showsMoveControls: Bool
    ) -> some View {
        let visibleItems = items
        let visibleSectionIDs = TodoSectionDragResolver.visibleSectionIDs(
            sections.map(\.id),
            draggingSectionID: draggingSectionID
        )
        let visibleSections = sections.filter { visibleSectionIDs.contains($0.id) }
        let visibleUnsectionedItems = visibleItems.filter { $0.section == nil }

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(SchedulerType.metadata)
                    .foregroundColor(.nsTextTertiary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Button {
                    beginDraftSection(isCompletedColumn: isCompletedColumn)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.nsTextSecondary)
                        .frame(
                            width: SchedulerControl.minimumTarget,
                            height: SchedulerControl.minimumTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(title) folder")
            }
            .padding(.horizontal, SchedulerSpacing.sm)

            ScrollViewReader { _ in
                GeometryReader { scrollGeometry in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            VStack(alignment: .leading, spacing: 2) {
                                if draftSectionColumn == isCompletedColumn {
                                    TodoDraftSectionRow(
                                        title: $draftSectionTitle,
                                        onCommit: commitDraftSection,
                                        onCancel: cancelDraftSection
                                    )
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }

                                ForEach(visibleSections, id: \.id) { section in
                                    let sectionVisibleItems = sectionItems(in: section, from: visibleItems)
                                    VStack(alignment: .leading, spacing: 2) {
                                        if showsMoveControls,
                                           draggingSectionID != nil,
                                           dropIntent.isSectionInsert(before: section.id) {
                                            TodoDropPlaceholder()
                                                .transition(.opacity)
                                        }

                                        TodoSectionHeaderView(
                                            section: section,
                                            itemCount: sectionItems(in: section, from: items).count,
                                            isEditing: editingSectionID == section.id,
                                            isDropTarget: draggingItemID != nil && dropIntent.isFolder(section.id),
                                            showsMoveHandle: showsMoveControls && density.showsMoveHandles,
                                            isDragActive: draggingItemID != nil || draggingSectionID != nil,
                                            editingTitle: $editingSectionTitle,
                                            showsItemCount: density == .normal,
                                            onDragChanged: showsMoveControls ? { location in
                                                if draggingSectionID == nil {
                                                    startDragging(section)
                                                }
                                                updateSectionDrag(at: location, source: section)
                                            } : nil,
                                            onDragEnded: showsMoveControls ? { location in
                                                finishSectionDrag(at: location, source: section)
                                            } : nil,
                                            onToggle: {
                                                withAnimation(.easeInOut(duration: 0.22)) {
                                                    _ = vm.toggleSectionExpansion(section)
                                                }
                                            },
                                            onCommitTitle: { commitSectionTitle(section) },
                                            onEdit: {
                                                editingSectionID = section.id
                                                editingSectionTitle = section.title
                                            },
                                            onDelete: { vm.deleteSection(section) }
                                        )
                                        .background(
                                            TodoTaskDropZoneReader(
                                                zone: showsMoveControls
                                                    ? .folder(section.id)
                                                    : nil
                                            )
                                        )
                                        .background(
                                            TodoSectionDropZoneReader(
                                                zone: showsMoveControls
                                                    ? TodoSectionDropZone(
                                                        id: section.id,
                                                        isCompletedSection: section.isCompletedSection
                                                    )
                                                    : nil
                                            )
                                        )
                                        .if(showsMoveControls && draggingSectionID == nil) { view in
                                            view.onDrop(
                                                of: [TodoDragPayload.type],
                                                delegate: TodoSectionHeaderDropDelegate(
                                                    section: section,
                                                    vm: vm,
                                                    draggingItemID: $draggingItemID,
                                                    dropIntent: $dropIntent,
                                                    dropIndex: $dropIndex,
                                                    dragResetTask: $dragResetTask,
                                                    autoScrollTask: $autoScrollTask,
                                                    autoScrollDirection: $autoScrollDirection,
                                                    autoScrollIndex: $autoScrollIndex,
                                                    autoScrollVelocity: $autoScrollVelocity
                                                )
                                            )
                                        }

                                        if section.isExpanded && draggingSectionID == nil {
                                            VStack(alignment: .leading, spacing: 2) {
                                                ForEach(sectionVisibleItems, id: \.id) { item in
                                                    if showsMoveControls,
                                                       draggingItemID != nil,
                                                       dropIntent.isInsert(before: item.id, in: section.id) {
                                                        TodoDropPlaceholder()
                                                            .padding(.leading, 16)
                                                            .transition(.opacity)
                                                    }

                                                    todoRow(
                                                        item: item,
                                                        showsMoveControls: showsMoveControls,
                                                        isNested: true
                                                    )
                                                    .padding(.leading, 16)
                                                }

                                                if showsMoveControls,
                                                   draggingItemID != nil,
                                                   dropIntent.isEnd(in: section.id) {
                                                    TodoDropPlaceholder()
                                                        .padding(.leading, 16)
                                                        .transition(.opacity)
                                                }
                                            }
                                            .clipped()
                                            .transition(.opacity)
                                            .if(showsMoveControls) { view in
                                                view.onDrop(
                                                    of: [TodoDragPayload.type],
                                                    delegate: TodoSectionDropDelegate(
                                                        section: section,
                                                        items: sectionVisibleItems,
                                                        vm: vm,
                                                        viewportHeight: scrollGeometry.size.height,
                                                        currentViewportY: {
                                                            currentActiveTodoViewportY()
                                                        },
                                                        isPointerInsideWindow: {
                                                            isPointerInsideActiveTodoWindow()
                                                        },
                                                        scrollBy: { deltaY in
                                                            scrollActiveTodoList(by: deltaY)
                                                        },
                                                        draggingItemID: $draggingItemID,
                                                        dropIntent: $dropIntent,
                                                        lastDropY: $lastDropY,
                                                        dropIndex: $dropIndex,
                                                        dragResetTask: $dragResetTask,
                                                        autoScrollTask: $autoScrollTask,
                                                        autoScrollDirection: $autoScrollDirection,
                                                        autoScrollIndex: $autoScrollIndex,
                                                        autoScrollVelocity: $autoScrollVelocity
                                                    )
                                                )
                                            }
                                        }
                                    }
                                    .padding(.bottom, 2)
                                    .animation(.easeInOut(duration: 0.22), value: section.isExpanded)
                                }

                                if showsMoveControls,
                                   draggingSectionID != nil,
                                   dropIntent.isSectionEnd {
                                    TodoDropPlaceholder()
                                        .transition(.opacity)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .if(showsMoveControls) { view in
                                view.onDrop(
                                    of: [TodoDragPayload.type],
                                    delegate: TodoSectionListDropDelegate(
                                        sections: visibleSections,
                                        isCompletedColumn: isCompletedColumn,
                                        vm: vm,
                                        draggingSectionID: $draggingSectionID,
                                        dropIntent: $dropIntent,
                                        lastDropY: $lastDropY,
                                        dropIndex: $dropIndex,
                                        dragResetTask: $dragResetTask,
                                        autoScrollTask: $autoScrollTask,
                                        autoScrollDirection: $autoScrollDirection,
                                        autoScrollIndex: $autoScrollIndex,
                                        autoScrollVelocity: $autoScrollVelocity
                                    )
                                )
                            }

                            if showsMoveControls,
                               TodoDragMotion.isRootDropTargetVisible(draggingItemID: draggingItemID) {
                                TodoRootDropTarget(isTargeted: dropIntent.isRoot)
                                    .background(TodoTaskDropZoneReader(zone: .root))
                                    .onDrop(
                                        of: [TodoDragPayload.type],
                                        delegate: TodoRootDropDelegate(
                                            beforeID: visibleUnsectionedItems.first?.id,
                                            vm: vm,
                                            draggingItemID: $draggingItemID,
                                            dropIntent: $dropIntent,
                                            dropIndex: $dropIndex,
                                            dragResetTask: $dragResetTask,
                                            autoScrollTask: $autoScrollTask,
                                            autoScrollDirection: $autoScrollDirection,
                                            autoScrollIndex: $autoScrollIndex,
                                            autoScrollVelocity: $autoScrollVelocity
                                        )
                                    )
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(visibleUnsectionedItems, id: \.id) { item in
                                    if showsMoveControls,
                                       draggingItemID != nil,
                                       dropIntent.isInsert(before: item.id, in: nil) {
                                        TodoDropPlaceholder()
                                            .transition(.opacity.combined(with: .move(edge: .top)))
                                    }

                                    todoRow(
                                        item: item,
                                        showsMoveControls: showsMoveControls,
                                        isNested: false
                                    )
                                }

                                if showsMoveControls, draggingItemID != nil, dropIntent.isEnd(in: nil) {
                                    TodoDropPlaceholder()
                                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }
                            }
                            .if(showsMoveControls) { view in
                                view.onDrop(
                                    of: [TodoDragPayload.type],
                                    delegate: TodoColumnDropDelegate(
                                        items: visibleUnsectionedItems,
                                        vm: vm,
                                        viewportHeight: scrollGeometry.size.height,
                                        currentViewportY: {
                                            currentActiveTodoViewportY()
                                        },
                                        isPointerInsideWindow: {
                                            isPointerInsideActiveTodoWindow()
                                        },
                                        localToViewportY: { localY in
                                            localY + activeContentMinY
                                        },
                                        scrollBy: { deltaY in
                                            scrollActiveTodoList(by: deltaY)
                                        },
                                        draggingItemID: $draggingItemID,
                                        dropIntent: $dropIntent,
                                        lastDropY: $lastDropY,
                                        dropIndex: $dropIndex,
                                        dragResetTask: $dragResetTask,
                                        autoScrollTask: $autoScrollTask,
                                        autoScrollDirection: $autoScrollDirection,
                                        autoScrollIndex: $autoScrollIndex,
                                        autoScrollVelocity: $autoScrollVelocity
                                    )
                                )
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(TodoScrollTarget.bottom)
                        }
                        .background {
                            if showsMoveControls {
                                TodoScrollViewResolver { scrollView in
                                    activeScrollView = scrollView
                                }
                            }
                        }
                        .background(
                            GeometryReader { contentGeometry in
                                Color.clear.preference(
                                    key: TodoContentMinYPreferenceKey.self,
                                    value: contentGeometry.frame(in: .named(TodoScrollSpace.active)).minY
                                )
                            }
                        )
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                        .animation(.easeInOut(duration: 0.16), value: dropIntent)
                    }
                    .coordinateSpace(name: TodoScrollSpace.active)
                    .onPreferenceChange(TodoContentMinYPreferenceKey.self) { value in
                        if showsMoveControls {
                            activeContentMinY = value
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionItems(in section: TodoSectionEntity, from items: [TodoEntity]) -> [TodoEntity] {
        items.filter { $0.section?.objectID == section.objectID }
    }

    private func orderedItems(sections: [TodoSectionEntity], items: [TodoEntity]) -> [TodoEntity] {
        let sectioned = sections.flatMap { sectionItems(in: $0, from: items) }
        return sectioned + items.filter { $0.section == nil }
    }

    private func commitSectionTitle(_ section: TodoSectionEntity) {
        vm.renameSection(section, title: editingSectionTitle)
        editingSectionID = nil
        editingSectionTitle = ""
    }

    private func beginDraftSection(isCompletedColumn: Bool) {
        draftSectionColumn = isCompletedColumn
        draftSectionTitle = ""
        editingSectionID = nil
        editingSectionTitle = ""
    }

    private func commitDraftSection() {
        guard let isCompletedColumn = draftSectionColumn else { return }
        let title = draftSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        draftSectionColumn = nil
        draftSectionTitle = ""
        guard !title.isEmpty else { return }
        _ = vm.addSection(title: title, isCompletedSection: isCompletedColumn)
    }

    private func cancelDraftSection() {
        draftSectionColumn = nil
        draftSectionTitle = ""
    }

    private func todoRow(item: TodoEntity, showsMoveControls: Bool, isNested: Bool) -> some View {
        TodoRowView(
            item: item,
            showsMoveHandle: showsMoveControls && density.showsMoveHandles,
            isNested: isNested,
            isDragActive: draggingItemID != nil,
            showsDeleteControl: density == .normal,
            onDragChanged: showsMoveControls ? { location in
                updateTaskDrag(item, at: location)
            } : nil,
            onDragEnded: showsMoveControls ? { location in
                endTaskDrag(item, at: location)
            } : nil,
            onToggle: { vm.toggle(item) },
            onDelete: { vm.delete(item) }
        )
        .background(
            TodoTaskDropZoneReader(
                zone: showsMoveControls
                    ? .item(id: item.id, sectionID: item.section?.id)
                    : nil
            )
        )
        .opacity(draggingItemID == item.id ? 0.18 : 1)
        .id(TodoScrollTarget.item(item.id))
        .contentShape(Rectangle())
        .contextMenu {
            Button("Delete", role: .destructive) {
                vm.delete(item)
            }
        }
    }

    private func startDragging(_ item: TodoEntity) {
        draggingItemID = item.id
        draggingSectionID = nil
        dropIntent = .none
        dropIndex = nil
        dragResetTask?.cancel()
        dragResetTask = nil
    }

    private func updateTaskDrag(_ item: TodoEntity, at location: CGPoint) {
        if draggingItemID != item.id {
            startDragging(item)
        }

        let destination = TodoTaskDragResolver.destination(
            at: location,
            sourceID: item.id,
            zones: taskDropZones
        )
        dropIntent = todoDropIntent(for: destination)
        updateTaskDragAutoScroll()
    }

    private func endTaskDrag(_ item: TodoEntity, at location: CGPoint) {
        let latestDestination = TodoTaskDragResolver.destination(
            at: location,
            sourceID: item.id,
            zones: taskDropZones
        )
        defer { finishTaskDrag() }

        switch latestDestination {
        case .none:
            return
        case .root:
            let firstRootID = activeItems.first {
                $0.id != item.id && $0.section == nil
            }?.id
            _ = vm.moveActiveItem(id: item.id, before: firstRootID)
        case .folder(let sectionID):
            guard let section = activeSections.first(where: { $0.id == sectionID }) else {
                return
            }
            _ = vm.moveActiveItem(id: item.id, before: nil, in: section)
        case .before(let targetID, let sectionID):
            let section = sectionID.flatMap { id in
                activeSections.first(where: { $0.id == id })
            }
            _ = vm.moveActiveItem(id: item.id, before: targetID, in: section)
        }
    }

    private func todoDropIntent(for destination: TodoTaskDragDestination) -> TodoDropIntent {
        switch destination {
        case .none:
            return .none
        case .root:
            return .root
        case .folder(let sectionID):
            return .folder(sectionID)
        case .before(let itemID, let sectionID):
            return .insert(sectionID: sectionID, beforeID: itemID)
        }
    }

    private func updateTaskDragAutoScroll() {
        guard let viewportY = currentActiveTodoViewportY(),
              let trigger = TodoDragMetrics.autoScrollTrigger(
                for: viewportY,
                viewportHeight: activeScrollView?.contentView.bounds.height ?? 0
              ) else {
            return
        }

        let delta = TodoDragMotion.scrollDelta(depth: trigger.depth)
        _ = scrollActiveTodoList(
            by: trigger.direction == .up ? -delta : delta
        )
    }

    private func finishTaskDrag() {
        draggingItemID = nil
        dropIntent = .none
        dropIndex = nil
        stopAutoScroll()
    }

    private func startDragging(_ section: TodoSectionEntity) {
        draggingItemID = nil
        draggingSectionID = section.id
        dropIntent = .none
        dropIndex = nil
        dragResetTask?.cancel()
        dragResetTask = nil
    }

    private func updateSectionDrag(
        at location: CGPoint,
        source: TodoSectionEntity
    ) {
        guard draggingSectionID == source.id else { return }
        let destination = TodoSectionDragResolver.destination(
            at: location,
            sourceID: source.id,
            isCompletedSection: source.isCompletedSection,
            zones: sectionDropZones
        )
        if case .before(let targetID) = destination {
            dropIntent = .sectionInsert(beforeID: targetID)
        } else {
            dropIntent = .none
        }
    }

    private func finishSectionDrag(
        at location: CGPoint,
        source: TodoSectionEntity
    ) {
        defer {
            draggingSectionID = nil
            dropIntent = .none
            dropIndex = nil
            stopAutoScroll()
        }
        guard draggingSectionID == source.id,
              case .before(let destination) = TodoSectionDragResolver.destination(
                  at: location,
                  sourceID: source.id,
                  isCompletedSection: source.isCompletedSection,
                  zones: sectionDropZones
              ) else {
            return
        }
        _ = vm.moveSection(
            id: source.id,
            before: destination,
            isCompletedSection: source.isCompletedSection
        )
    }

    private func dragProvider(id: UUID) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = Data(id.uuidString.utf8)
        provider.registerDataRepresentation(
            forTypeIdentifier: TodoDragPayload.typeIdentifier,
            visibility: .ownProcess
        ) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    private func stopAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        autoScrollDirection = nil
        autoScrollIndex = nil
        autoScrollVelocity = 0
    }

    private func scrollActiveTodoList(by deltaY: CGFloat) -> CGFloat {
        guard let activeScrollView,
              let documentView = activeScrollView.documentView
        else { return 0 }

        let clipView = activeScrollView.contentView
        let maxY = max(0, documentView.bounds.height - clipView.bounds.height)
        let currentY = clipView.bounds.origin.y
        let nextY = min(max(0, currentY + deltaY), maxY)
        guard abs(nextY - currentY) > 0.1 else { return 0 }

        clipView.setBoundsOrigin(NSPoint(x: clipView.bounds.origin.x, y: nextY))
        activeScrollView.reflectScrolledClipView(clipView)
        return nextY - currentY
    }

    private func currentActiveTodoViewportY() -> CGFloat? {
        guard let activeScrollView,
              let window = activeScrollView.window
        else { return nil }

        let windowPoint = window.mouseLocationOutsideOfEventStream
        let clipView = activeScrollView.contentView
        let localPoint = clipView.convert(windowPoint, from: nil)
        let viewportY = localPoint.y - clipView.bounds.origin.y
        return clipView.isFlipped ? viewportY : clipView.bounds.height - viewportY
    }

    private func isPointerInsideActiveTodoWindow() -> Bool {
        guard let window = activeScrollView?.window else { return true }
        return window.frame.contains(NSEvent.mouseLocation)
    }

    private var addTaskRow: some View {
        HStack(spacing: 6) {
            if let persistenceError = vm.persistenceError {
                TodoPersistenceErrorIndicator(error: persistenceError)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 10))
                    .foregroundColor(.nsTextSecondary)
                    .frame(width: 10, height: 14)
                    .accessibilityHidden(true)
            }

            TodoTaskInputField(
                text: $vm.newTitle,
                isFocused: $isAddFieldFocused,
                onSubmit: submitNewTask(title:)
            )

            TodoSubmitButton(isEnabled: canSubmitNewTask, action: submitNewTask)
                .frame(
                    width: SchedulerControl.minimumTarget,
                    height: SchedulerControl.minimumTarget
                )
        }
        .padding(.horizontal, SchedulerSpacing.cardInset)
        .padding(.vertical, SchedulerSpacing.sm)
        .contentShape(Rectangle())
        .onTapGesture { isAddFieldFocused = true }
    }

    private var canSubmitNewTask: Bool {
        !vm.newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitNewTask() {
        submitNewTask(title: vm.newTitle)
    }

    private func submitNewTask(title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        vm.submit(title: title)
        DispatchQueue.main.async {
            isAddFieldFocused = true
        }
    }
}

struct TodoPersistenceErrorIndicator: View {
    static let accessibilityIdentifier = "todo.persistence.error"

    let error: TodoPersistenceError

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.daylineError)
            .frame(width: 10, height: 14)
            .contentShape(Rectangle())
            .help(accessibilityLabel)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier(Self.accessibilityIdentifier)
    }

    private var accessibilityLabel: String {
        switch error {
        case .saveFailed(let message):
            return "Task save failed: \(message)"
        }
    }
}

// MARK: - Native actions

class TodoPointingHandButton: NSButton {
    let cursorForInteraction = NSCursor.pointingHand

    override var intrinsicContentSize: NSSize {
        NSSize(width: SchedulerControl.minimumTarget, height: SchedulerControl.minimumTarget)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: cursorForInteraction)
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        if Thread.isMainThread {
            performClick(nil)
        } else {
            DispatchQueue.main.sync { [weak self] in
                self?.performClick(nil)
            }
        }
        return true
    }
}

struct TodoSubmitButton: NSViewRepresentable {
    let isEnabled: Bool
    let action: () -> Void

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func submit(_ sender: Any?) {
            action()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> TodoPointingHandButton {
        let button = TodoPointingHandButton()
        button.isBordered = false
        button.image = NSImage(
            systemSymbolName: "paperplane.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.submit(_:))
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel("Add task")
        button.setAccessibilityIdentifier("todo.submit")
        configure(button)
        return button
    }

    func updateNSView(_ button: TodoPointingHandButton, context: Context) {
        context.coordinator.action = action
        configure(button)
    }

    private func configure(_ button: TodoPointingHandButton) {
        button.isEnabled = isEnabled
        button.contentTintColor = NSColor(
            isEnabled ? Color.nsChevron : Color.nsTextSecondary.opacity(0.45)
        )
    }
}

final class TodoTaskTrashNativeButton: TodoPointingHandButton {
    private(set) var itemID: UUID
    private weak var monitorOwner: TodoRowHoverMonitorOwner?

    init(itemID: UUID) {
        self.itemID = itemID
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            monitorOwner?.unregisterTrashButton(self)
            monitorOwner = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        let owner = TodoRowHoverMonitorOwner.attached(to: window)
        monitorOwner = owner
        owner.registerTrashButton(self)
    }

    func updateItemID(_ itemID: UUID) {
        guard self.itemID != itemID else { return }
        monitorOwner?.unregisterTrashButton(self)
        self.itemID = itemID
        monitorOwner?.registerTrashButton(self)
    }

    func setInteractionVisible(_ isVisible: Bool) {
        alphaValue = isVisible ? 1 : 0
        isEnabled = isVisible
        setAccessibilityElement(isVisible)
        setAccessibilityEnabled(isVisible)
    }
}

@MainActor
final class TodoRowHoverState: ObservableObject {
    @Published var isHovered = false
}

@MainActor
final class TodoRowHoverMonitorOwner: NSObject {
    private final class WeakRow {
        weak var value: TodoRowHoverTracker.HoverView?

        init(_ value: TodoRowHoverTracker.HoverView) {
            self.value = value
        }
    }

    private final class WeakTrashButton {
        weak var value: TodoTaskTrashNativeButton?

        init(_ value: TodoTaskTrashNativeButton) {
            self.value = value
        }
    }

    private static var associationKey: UInt8 = 0

    private weak var window: NSWindow?
    private var rows: [ObjectIdentifier: WeakRow] = [:]
    private var trashButtons: [UUID: WeakTrashButton] = [:]
    private var localEventMonitor: Any?
    private var globalPointerObserver: NSObjectProtocol?

    var localMonitorTokenCount: Int { localEventMonitor == nil ? 0 : 1 }
    var globalPointerSubscriptionCount: Int { globalPointerObserver == nil ? 0 : 1 }

    var registeredRowCount: Int {
        pruneReleasedRegistrations()
        return rows.count
    }

    var registeredTrashCount: Int {
        pruneReleasedRegistrations()
        return trashButtons.count
    }

    static func attached(to window: NSWindow) -> TodoRowHoverMonitorOwner {
        if let owner = objc_getAssociatedObject(window, &associationKey) as? TodoRowHoverMonitorOwner {
            return owner
        }
        let owner = TodoRowHoverMonitorOwner(window: window)
        objc_setAssociatedObject(
            window,
            &associationKey,
            owner,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return owner
    }

    private init(window: NSWindow) {
        self.window = window
    }

    func registerRow(_ row: TodoRowHoverTracker.HoverView) {
        rows[ObjectIdentifier(row)] = WeakRow(row)
        installPointerObservationIfNeeded()
    }

    func unregisterRow(_ row: TodoRowHoverTracker.HoverView) {
        rows.removeValue(forKey: ObjectIdentifier(row))
        pruneReleasedRegistrations()
        if rows.isEmpty {
            removePointerObservation()
        }
    }

    func registerTrashButton(_ button: TodoTaskTrashNativeButton) {
        trashButtons[button.itemID] = WeakTrashButton(button)
    }

    func unregisterTrashButton(_ button: TodoTaskTrashNativeButton) {
        guard trashButtons[button.itemID]?.value === button else { return }
        trashButtons.removeValue(forKey: button.itemID)
    }

    func trashButton(for itemID: UUID) -> TodoTaskTrashNativeButton? {
        guard let button = trashButtons[itemID]?.value else {
            trashButtons.removeValue(forKey: itemID)
            return nil
        }
        return button
    }

    func handleLocalMonitorEvent(_ event: NSEvent) {
        guard let window else { return }
        let screenPoint = event.window === window
            ? window.convertPoint(toScreen: event.locationInWindow)
            : NSEvent.mouseLocation
        handleScreenPoint(screenPoint)
    }

    func handleScreenPoint(_ screenPoint: CGPoint) {
        pruneReleasedRegistrations()
        for row in rows.values.compactMap(\.value) {
            row.handleScreenPoint(screenPoint)
        }
        if rows.isEmpty {
            removePointerObservation()
        }
    }

    func setTrashVisibility(_ isVisible: Bool, for itemID: UUID) {
        trashButton(for: itemID)?.setInteractionVisible(isVisible)
    }

    private func installPointerObservationIfNeeded() {
        if localEventMonitor == nil {
            localEventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged]
            ) { [weak self] event in
                self?.handleLocalMonitorEvent(event)
                return event
            }
        }
        if globalPointerObserver == nil {
            globalPointerObserver = NotificationCenter.default.addObserver(
                forName: NotchGlobalPointerEvent.notificationName,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let event = notification.object as? NotchGlobalPointerEvent else { return }
                MainActor.assumeIsolated {
                    self?.handleScreenPoint(event.screenPoint)
                }
            }
        }
    }

    private func removePointerObservation() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalPointerObserver {
            NotificationCenter.default.removeObserver(globalPointerObserver)
            self.globalPointerObserver = nil
        }
    }

    private func pruneReleasedRegistrations() {
        rows = rows.filter { $0.value.value != nil }
        trashButtons = trashButtons.filter { $0.value.value != nil }
    }

}

struct TodoRowHoverTracker: NSViewRepresentable {
    let itemID: UUID
    let hoverState: TodoRowHoverState

    func makeNSView(context: Context) -> HoverView {
        let view = HoverView(itemID: itemID, hoverState: hoverState)
        configure(view)
        return view
    }

    func updateNSView(_ view: HoverView, context: Context) {
        view.hoverState = hoverState
        configure(view)
    }

    private func configure(_ view: HoverView) {
        view.setAccessibilityElement(false)
        view.setAccessibilityIdentifier("todo.task.hover.\(itemID.uuidString)")
    }

    final class HoverView: NSView {
        let itemID: UUID
        var hoverState: TodoRowHoverState
        private var hoverTrackingArea: NSTrackingArea?
        private(set) weak var monitorOwner: TodoRowHoverMonitorOwner?

        init(itemID: UUID, hoverState: TodoRowHoverState) {
            self.itemID = itemID
            self.hoverState = hoverState
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow !== window {
                transitionHover(to: false)
                monitorOwner?.unregisterRow(self)
                monitorOwner = nil
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            let owner = TodoRowHoverMonitorOwner.attached(to: window)
            monitorOwner = owner
            owner.registerRow(self)
        }

        override func updateTrackingAreas() {
            if let hoverTrackingArea {
                removeTrackingArea(hoverTrackingArea)
            }
            let trackingArea = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            hoverTrackingArea = trackingArea
            super.updateTrackingAreas()
        }

        override func mouseEntered(with event: NSEvent) {
            transitionHover(to: true)
        }

        override func mouseExited(with event: NSEvent) {
            transitionHover(to: false)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        func handleScreenPoint(_ screenPoint: CGPoint) {
            guard let window else { return }
            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            let localPoint = convert(windowPoint, from: nil)
            transitionHover(to: bounds.contains(localPoint))
        }

        private func transitionHover(to isHovered: Bool) {
            guard hoverState.isHovered != isHovered else { return }
            hoverState.isHovered = isHovered
            monitorOwner?.setTrashVisibility(isHovered, for: itemID)
        }
    }
}

struct TodoTaskTrashButton: NSViewRepresentable {
    let itemID: UUID
    let isVisible: Bool
    let action: () -> Void

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func deleteTask(_ sender: Any?) {
            action()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> TodoTaskTrashNativeButton {
        let button = TodoTaskTrashNativeButton(itemID: itemID)
        button.isBordered = false
        button.image = NSImage(
            systemSymbolName: "trash",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.focusRingType = .none
        button.contentTintColor = .systemRed
        button.target = context.coordinator
        button.action = #selector(Coordinator.deleteTask(_:))
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel("Delete task")
        button.setAccessibilityIdentifier("todo.task.delete.\(itemID.uuidString)")
        configure(button)
        return button
    }

    func updateNSView(_ button: TodoTaskTrashNativeButton, context: Context) {
        context.coordinator.action = action
        button.updateItemID(itemID)
        button.setAccessibilityIdentifier("todo.task.delete.\(itemID.uuidString)")
        configure(button)
    }

    private func configure(_ button: TodoTaskTrashNativeButton) {
        button.setInteractionVisible(isVisible)
    }
}

// MARK: - Row

private struct TodoDraftSectionRow: View {
    @Binding var title: String
    let onCommit: () -> Void
    let onCancel: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.nsTextSecondary.opacity(0.25))
                .frame(width: 22, height: 18)

            Text(">")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.nsTextSecondary.opacity(0.45))
                .frame(width: 12, height: 16)

            TextField("Folder name", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.nsTextPrimary)
                .focused($isFocused)
                .onSubmit(onCommit)
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        onCommit()
                    }
                }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(Color.nsChevron.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.nsChevron.opacity(0.28), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .background(
            TodoOutsideClickCommitter {
                onCommit()
            }
        )
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
        .onExitCommand(perform: onCancel)
        .accessibilityLabel("New folder name")
    }
}

private struct TodoOutsideClickCommitter: NSViewRepresentable {
    let onOutsideClick: () -> Void

    func makeNSView(context: Context) -> OutsideClickView {
        let view = OutsideClickView()
        view.onOutsideClick = onOutsideClick
        return view
    }

    func updateNSView(_ nsView: OutsideClickView, context: Context) {
        nsView.onOutsideClick = onOutsideClick
    }

    final class OutsideClickView: NSView {
        var onOutsideClick: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateMonitor()
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil {
                removeMonitor()
            }
            super.viewWillMove(toWindow: newWindow)
        }

        private func updateMonitor() {
            removeMonitor()

            guard window != nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else {
                    return event
                }

                let point = convert(event.locationInWindow, from: nil)
                if !bounds.contains(point) {
                    DispatchQueue.main.async { [weak self] in
                        self?.onOutsideClick?()
                    }
                }

                return event
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

struct TodoSectionHeaderView: View {
    let section: TodoSectionEntity
    let itemCount: Int
    let isEditing: Bool
    let isDropTarget: Bool
    let showsMoveHandle: Bool
    let isDragActive: Bool
    @Binding var editingTitle: String
    var showsItemCount: Bool = true
    var onDragProvider: (() -> NSItemProvider)? = nil
    var onDragChanged: ((CGPoint) -> Void)? = nil
    var onDragEnded: ((CGPoint) -> Void)? = nil
    let onToggle: () -> Void
    let onCommitTitle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @FocusState private var isTitleFocused: Bool
    @StateObject private var hoverState = TodoRowHoverState()

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggle) {
                Text(">")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.nsTextSecondary.opacity(0.82))
                    .frame(
                        width: SchedulerControl.minimumTarget,
                        height: SchedulerControl.minimumTarget
                    )
                    .contentShape(Rectangle())
                    .rotationEffect(.degrees(section.isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.16), value: section.isExpanded)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(section.title) folder")
            .accessibilityIdentifier("todo.folder.toggle.\(section.id.uuidString)")

            if isEditing {
                TextField("Folder name", text: $editingTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.nsTextPrimary)
                    .focused($isTitleFocused)
                    .onSubmit(onCommitTitle)
                    .onChange(of: isTitleFocused) { _, focused in
                        if !focused {
                            onCommitTitle()
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            isTitleFocused = true
                        }
                    }
            } else {
                Text(section.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.nsTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .accessibilityIdentifier("todo.folder.title.\(section.id.uuidString)")
            }

            Spacer(minLength: 4)

            HStack(spacing: 0) {
                if showsItemCount && !showsHoverState {
                    Text("\(itemCount)")
                        .font(
                            .system(
                                size: TodoSectionMetrics.itemCountFontSize,
                                weight: .medium,
                                design: .monospaced
                            )
                        )
                        .foregroundColor(.nsTextSecondary.opacity(0.7))
                        .frame(
                            width: SchedulerControl.minimumTarget,
                            height: SchedulerControl.minimumTarget,
                            alignment: .center
                        )
                        .accessibilityIdentifier("todo.folder.count.\(section.id.uuidString)")
                }

                if showsHoverState {
                    Button(action: onEdit) {
                        Image(systemName: "square.and.pencil")
                            .font(
                                .system(
                                    size: TodoSectionMetrics.actionGlyphFontSize,
                                    weight: .semibold
                                )
                            )
                            .foregroundColor(.white.opacity(0.82))
                            .frame(
                                width: SchedulerControl.minimumTarget,
                                height: SchedulerControl.minimumTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit folder")
                    .accessibilityIdentifier("todo.folder.edit.\(section.id.uuidString)")
                    .help("Edit folder")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(
                                .system(
                                    size: TodoSectionMetrics.actionGlyphFontSize,
                                    weight: .semibold
                                )
                            )
                            .foregroundColor(.white.opacity(0.85))
                            .frame(
                                width: SchedulerControl.minimumTarget,
                                height: SchedulerControl.minimumTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete folder")
                    .accessibilityIdentifier("todo.folder.delete.\(section.id.uuidString)")
                    .help("Delete folder")
                }

                if showsMoveHandle {
                    dragHandle
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(isDropTarget ? Color.nsChevron.opacity(0.18) : Color.nsBorder.opacity(0.34))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(isDropTarget ? Color.nsChevron.opacity(0.34) : Color.clear, lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .background {
            TodoRowHoverTracker(itemID: section.id, hoverState: hoverState)
        }
        .animation(.easeInOut(duration: 0.12), value: isDropTarget)
    }

    @ViewBuilder
    private var dragHandle: some View {
        let handle = Image(systemName: "line.3.horizontal")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.nsTextSecondary.opacity(showsHoverState ? 0.65 : 0.25))
            .frame(width: 22, height: 18)
            .contentShape(Rectangle())
            .accessibilityHidden(true)

        if let onDragChanged, let onDragEnded {
            handle.background(
                TodoTaskDragGestureSurface(
                    onChanged: onDragChanged,
                    onEnded: onDragEnded
                )
            )
        } else if let onDragProvider {
            handle.onDrag {
                onDragProvider()
            } preview: {
                TodoDragPreview(title: section.title)
            }
        } else {
            handle
        }
    }

    private var showsHoverState: Bool {
        TodoFolderActionVisibility.isVisible(
            isHovered: hoverState.isHovered,
            isDragActive: isDragActive
        )
    }
}

struct TodoRowView: View {
    let item: TodoEntity
    var showsMoveHandle: Bool = true
    var isNested: Bool = false
    var isDragActive: Bool = false
    var showsDeleteControl: Bool = true
    var onDragChanged: ((CGPoint) -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?
    let onToggle: () -> Void
    let onDelete: () -> Void
    @StateObject private var hoverState = TodoRowHoverState()

    var body: some View {
        HStack(spacing: 6) {
            // ── Checkbox ──────────────────────────────────────────────────
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .imageScale(.small)
                    .foregroundColor(item.isCompleted ? .nsTextSecondary : .nsChevron)
                    .frame(
                        width: SchedulerControl.minimumTarget,
                        height: SchedulerControl.minimumTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Mark incomplete" : "Mark complete")

            // ── Title ─────────────────────────────────────────────────────
            Text(item.title)
                .font(SchedulerType.body)
                .foregroundColor(item.isCompleted ? .nsTextSecondary : .nsTextPrimary)
                .strikethrough(item.isCompleted, color: .nsTextSecondary)
                .lineLimit(1)
                .accessibilityLabel(item.title)
                .accessibilityIdentifier("todo.task.title.\(item.id.uuidString)")

            Spacer()

            // ── Category dot ──────────────────────────────────────────────
            // 8pt (up from 6pt) — minimum size for reliable color recognition.
            // Tooltip provides the category name for users who can't distinguish
            // colors reliably.
            if let cat = item.category {
                Circle()
                    .fill(Color(hex: cat.colorHex))
                    .frame(width: 8, height: 8)
                    .help(cat.name)
                    .accessibilityLabel("Category: \(cat.name)")
            }

            if showsDeleteControl {
                TodoTaskTrashButton(
                    itemID: item.id,
                    isVisible: showsHoverState,
                    action: onDelete
                )
                .frame(
                    width: SchedulerControl.minimumTarget,
                    height: SchedulerControl.minimumTarget
                )
            }

            // Keep the activator in a stable trailing column, matching the
            // fixed completion/content/reorder grid used by the habit tracker.
            if showsMoveHandle {
                dragHandle
            }
        }
        .padding(.horizontal, SchedulerSpacing.xs)
        .padding(.vertical, 2)
        .background(showsHoverState ? Color.nsBorder.opacity(0.5) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: SchedulerRadius.row, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background {
            TodoRowHoverTracker(itemID: item.id, hoverState: hoverState)
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal:   .opacity
        ))
        .animation(.easeInOut(duration: 0.15), value: item.isCompleted)
    }

    private var showsHoverState: Bool {
        hoverState.isHovered && !isDragActive
    }

    @ViewBuilder
    private var dragHandle: some View {
        let handle = Image(systemName: "line.3.horizontal")
            .font(.system(size: 11))
            // foregroundStyle accepts ShapeStyle — Color.opacity() returns AnyShapeStyle (macOS 14+)
            .foregroundStyle(Color.nsTextSecondary.opacity(showsHoverState ? 0.65 : 0.25))
            .frame(
                width: SchedulerControl.minimumTarget,
                height: SchedulerControl.minimumTarget
            )
            .contentShape(Rectangle())
            .accessibilityHidden(true)  // drag is a pointer interaction; not VoiceOver-relevant

        if let onDragChanged, let onDragEnded {
            handle.overlay(
                TodoTaskDragGestureSurface(
                    accessibilityIdentifier: "todo.task.drag.\(item.id.uuidString)",
                    onChanged: onDragChanged,
                    onEnded: onDragEnded
                )
            )
        } else {
            handle
        }
    }
}

private struct TodoTaskDragGestureSurface: NSViewRepresentable {
    var accessibilityIdentifier: String? = nil
    let onChanged: (CGPoint) -> Void
    let onEnded: (CGPoint) -> Void

    func makeNSView(context: Context) -> TodoTaskDragTrackingView {
        let view = TodoTaskDragTrackingView(
            onChanged: onChanged,
            onEnded: onEnded
        )
        view.setAccessibilityIdentifier(accessibilityIdentifier)
        return view
    }

    func updateNSView(_ nsView: TodoTaskDragTrackingView, context: Context) {
        nsView.setAccessibilityIdentifier(accessibilityIdentifier)
        nsView.onChanged = onChanged
        nsView.onEnded = onEnded
    }
}

private final class TodoTaskDragTrackingView: NSView {
    var onChanged: (CGPoint) -> Void
    var onEnded: (CGPoint) -> Void

    private var mouseDownPoint: CGPoint?
    private var isDragging = false

    init(
        onChanged: @escaping (CGPoint) -> Void,
        onEnded: @escaping (CGPoint) -> Void
    ) {
        self.onChanged = onChanged
        self.onEnded = onEnded
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownPoint else { return }
        let deltaX = event.locationInWindow.x - mouseDownPoint.x
        let deltaY = event.locationInWindow.y - mouseDownPoint.y
        if !isDragging {
            guard hypot(deltaX, deltaY) >= 6 else { return }
            isDragging = true
        }
        onChanged(swiftUIGlobalLocation(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownPoint = nil
            isDragging = false
        }
        guard isDragging else { return }
        onEnded(swiftUIGlobalLocation(for: event))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isDragging ? .closedHand : .openHand)
    }

    private func swiftUIGlobalLocation(for event: NSEvent) -> CGPoint {
        guard let contentView = window?.contentView else {
            return event.locationInWindow
        }
        return CGPoint(
            x: event.locationInWindow.x,
            y: contentView.bounds.height - event.locationInWindow.y
        )
    }
}

private struct TodoDragPreview: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.nsTextPrimary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.nsBorder.opacity(0.62))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
            .opacity(0.72)
    }
}

enum TodoDropPreviewMetrics {
    static let layoutHeight: CGFloat = 0
    static let indicatorHeight: CGFloat = 2
}

private struct TodoDropPlaceholder: View {
    var body: some View {
        Capsule()
            .fill(Color.nsChevron.opacity(0.72))
            .frame(height: TodoDropPreviewMetrics.indicatorHeight)
            .frame(height: TodoDropPreviewMetrics.layoutHeight)
            .padding(.horizontal, 4)
    }
}

enum TodoTaskDropZone: Hashable {
    case root
    case folder(UUID)
    case item(id: UUID, sectionID: UUID?)
}

struct TodoSectionDropZone: Equatable {
    let id: UUID
    var isCompletedSection = false
    var frame: CGRect = .zero
}

enum TodoSectionDragDestination: Equatable {
    case before(UUID?)
}

enum TodoSectionDragResolver {
    static func visibleSectionIDs(
        _ sectionIDs: [UUID],
        draggingSectionID: UUID?
    ) -> [UUID] {
        _ = draggingSectionID
        return sectionIDs
    }

    static func destination(
        at location: CGPoint,
        sourceID: UUID,
        isCompletedSection: Bool = false,
        zones: [TodoSectionDropZone]
    ) -> TodoSectionDragDestination? {
        let columnZones = zones
            .filter { $0.isCompletedSection == isCompletedSection && $0.id != sourceID }
            .sorted {
                if abs($0.frame.minY - $1.frame.minY) > 0.5 {
                    return $0.frame.minY < $1.frame.minY
                }
                return $0.frame.minX < $1.frame.minX
            }
        guard let index = columnZones.firstIndex(where: {
            $0.frame.insetBy(dx: 0, dy: -1).contains(location)
        }) else {
            return nil
        }
        let zone = columnZones[index]
        if location.y < zone.frame.midY {
            return .before(zone.id)
        }
        let nextIndex = columnZones.index(after: index)
        let nextID = nextIndex < columnZones.endIndex ? columnZones[nextIndex].id : nil
        return .before(nextID)
    }
}

private struct TodoSectionDropZonePreferenceKey: PreferenceKey {
    static let defaultValue: [TodoSectionDropZone] = []

    static func reduce(
        value: inout [TodoSectionDropZone],
        nextValue: () -> [TodoSectionDropZone]
    ) {
        value.append(contentsOf: nextValue())
    }
}

private struct TodoSectionDropZoneReader: View {
    let zone: TodoSectionDropZone?

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: TodoSectionDropZonePreferenceKey.self,
                value: zone.map {
                    [
                        TodoSectionDropZone(
                            id: $0.id,
                            isCompletedSection: $0.isCompletedSection,
                            frame: proxy.frame(in: .global)
                        )
                    ]
                } ?? []
            )
        }
    }
}

enum TodoTaskDragDestination: Equatable {
    case none
    case root
    case folder(UUID)
    case before(itemID: UUID, sectionID: UUID?)
}

enum TodoTaskDragResolver {
    static func destination(
        at location: CGPoint,
        sourceID: UUID,
        zones: [TodoTaskDropZone: CGRect]
    ) -> TodoTaskDragDestination {
        if zones[.root]?.contains(location) == true {
            return .root
        }

        let itemMatches = zones.compactMap { zone, frame -> (UUID, UUID?, CGRect)? in
            guard case .item(let itemID, let sectionID) = zone,
                  itemID != sourceID,
                  frame.contains(location) else {
                return nil
            }
            return (itemID, sectionID, frame)
        }
        if let match = itemMatches.min(by: {
            if $0.2.minY == $1.2.minY {
                return $0.2.minX < $1.2.minX
            }
            return $0.2.minY < $1.2.minY
        }) {
            return .before(itemID: match.0, sectionID: match.1)
        }

        let folderMatches = zones.compactMap { zone, frame -> (UUID, CGRect)? in
            guard case .folder(let sectionID) = zone,
                  frame.contains(location) else {
                return nil
            }
            return (sectionID, frame)
        }
        if let match = folderMatches.min(by: {
            if $0.1.minY == $1.1.minY {
                return $0.0.uuidString < $1.0.uuidString
            }
            return $0.1.minY < $1.1.minY
        }) {
            return .folder(match.0)
        }

        return .none
    }
}

private struct TodoTaskDropZonePreferenceKey: PreferenceKey {
    static let defaultValue: [TodoTaskDropZone: CGRect] = [:]

    static func reduce(
        value: inout [TodoTaskDropZone: CGRect],
        nextValue: () -> [TodoTaskDropZone: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct TodoTaskDropZoneReader: View {
    let zone: TodoTaskDropZone?

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: TodoTaskDropZonePreferenceKey.self,
                value: zone.map { [$0: proxy.frame(in: .global)] } ?? [:]
            )
        }
    }
}

private struct TodoRootDropTarget: View {
    let isTargeted: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.up")
                .font(.system(size: 10, weight: .semibold))

            Text("Move outside folders")
                .font(SchedulerType.metadata)
        }
        .foregroundColor(isTargeted ? .nsTextPrimary : .nsTextTertiary)
        .frame(
            maxWidth: .infinity,
            minHeight: TodoDragMotion.rootDropTargetMinimumHeight,
            alignment: .center
        )
        .background(isTargeted ? Color.nsChevron.opacity(0.16) : Color.nsBorder.opacity(0.18))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(
                    isTargeted ? Color.nsChevron.opacity(0.5) : Color.nsBorder.opacity(0.55),
                    style: StrokeStyle(lineWidth: 0.8, dash: [4, 3])
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityLabel("Move outside folders")
        .accessibilityIdentifier("todo.root.drop")
    }
}

private enum TodoDropIntent: Equatable {
    case none
    case root
    case folder(UUID)
    case sectionInsert(beforeID: UUID?)
    case insert(sectionID: UUID?, beforeID: UUID?)

    var isRoot: Bool {
        self == .root
    }

    func isFolder(_ sectionID: UUID) -> Bool {
        if case .folder(let id) = self, id == sectionID { return true }
        return false
    }

    func isInsert(before itemID: UUID, in sectionID: UUID?) -> Bool {
        if case .insert(let id, let beforeID) = self, id == sectionID, beforeID == itemID {
            return true
        }
        return false
    }

    func isEnd(in sectionID: UUID?) -> Bool {
        if case .insert(let id, nil) = self, id == sectionID { return true }
        return false
    }

    func isSectionInsert(before sectionID: UUID) -> Bool {
        if case .sectionInsert(let beforeID) = self, beforeID == sectionID { return true }
        return false
    }

    var isSectionEnd: Bool {
        if case .sectionInsert(nil) = self { return true }
        return false
    }
}

@MainActor
private struct TodoRootDropDelegate: DropDelegate {
    let beforeID: UUID?
    let vm: TodoViewModel
    @Binding var draggingItemID: UUID?
    @Binding var dropIntent: TodoDropIntent
    @Binding var dropIndex: Int?
    @Binding var dragResetTask: Task<Void, Never>?
    @Binding var autoScrollTask: Task<Void, Never>?
    @Binding var autoScrollDirection: TodoAutoScrollDirection?
    @Binding var autoScrollIndex: Int?
    @Binding var autoScrollVelocity: CGFloat

    func dropEntered(info: DropInfo) {
        guard draggingItemID != nil else { return }
        dropIntent = .root
        dropIndex = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggingItemID != nil else { return nil }
        dropIntent = .root
        dropIndex = nil
        return DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggingItemID != nil
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceID = draggingItemID else { return false }
        performImmediateTodoDrop {
            vm.moveActiveItem(id: sourceID, before: beforeID)
            finishDrag()
        }
        return true
    }

    func dropExited(info: DropInfo) {
        guard dropIntent.isRoot else { return }
        dropIntent = .none
        dropIndex = nil
    }

    private func finishDrag() {
        draggingItemID = nil
        dropIntent = .none
        dropIndex = nil
        dragResetTask?.cancel()
        dragResetTask = nil
        autoScrollTask?.cancel()
        autoScrollTask = nil
        autoScrollDirection = nil
        autoScrollIndex = nil
        autoScrollVelocity = 0
    }
}

@MainActor
private struct TodoSectionHeaderDropDelegate: DropDelegate {
    let section: TodoSectionEntity
    let vm: TodoViewModel
    @Binding var draggingItemID: UUID?
    @Binding var dropIntent: TodoDropIntent
    @Binding var dropIndex: Int?
    @Binding var dragResetTask: Task<Void, Never>?
    @Binding var autoScrollTask: Task<Void, Never>?
    @Binding var autoScrollDirection: TodoAutoScrollDirection?
    @Binding var autoScrollIndex: Int?
    @Binding var autoScrollVelocity: CGFloat

    func dropEntered(info: DropInfo) {
        guard draggingItemID != nil else { return }
        dropIntent = .folder(section.id)
        dropIndex = nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggingItemID != nil else { return nil }
        dropIntent = .folder(section.id)
        dropIndex = nil
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceID = draggingItemID else { return false }
        performImmediateTodoDrop {
            vm.moveActiveItem(id: sourceID, before: nil, in: section)
            finishDrag()
        }
        return true
    }

    func dropExited(info: DropInfo) {
        if dropIntent.isFolder(section.id) {
            dropIntent = .none
            dropIndex = nil
        }
    }

    private func finishDrag() {
        draggingItemID = nil
        dropIntent = .none
        dropIndex = nil
        dragResetTask?.cancel()
        dragResetTask = nil
        autoScrollTask?.cancel()
        autoScrollTask = nil
        autoScrollDirection = nil
        autoScrollIndex = nil
        autoScrollVelocity = 0
    }
}

@MainActor
private struct TodoSectionDropDelegate: DropDelegate {
    let section: TodoSectionEntity
    let items: [TodoEntity]
    let vm: TodoViewModel
    let viewportHeight: CGFloat
    let currentViewportY: () -> CGFloat?
    let isPointerInsideWindow: () -> Bool
    let scrollBy: (CGFloat) -> CGFloat
    @Binding var draggingItemID: UUID?
    @Binding var dropIntent: TodoDropIntent
    @Binding var lastDropY: CGFloat
    @Binding var dropIndex: Int?
    @Binding var dragResetTask: Task<Void, Never>?
    @Binding var autoScrollTask: Task<Void, Never>?
    @Binding var autoScrollDirection: TodoAutoScrollDirection?
    @Binding var autoScrollIndex: Int?
    @Binding var autoScrollVelocity: CGFloat

    func dropEntered(info: DropInfo) {
        guard draggingItemID != nil else { return }
        updateDropState(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggingItemID != nil else { return nil }
        updateDropState(info: info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceID = draggingItemID else { return false }
        updateDropState(info: info)
        let targetID: UUID?
        switch dropIntent {
        case .insert(let sectionID, let beforeID) where sectionID == section.id:
            targetID = beforeID
        default:
            return false
        }

        performImmediateTodoDrop {
            vm.moveActiveItem(id: sourceID, before: targetID, in: section)
            finishDrag()
        }
        return true
    }

    func dropExited(info: DropInfo) {
        switch dropIntent {
        case .insert(let sectionID, _) where sectionID == section.id:
            dropIntent = .none
            dropIndex = nil
        default:
            break
        }
    }

    private func updateDropState(info: DropInfo) {
        updateDropState(forLocalY: info.location.y)
        if let viewportY = currentViewportY() {
            updateAutoScroll(forViewportY: viewportY)
        }
    }

    private func updateDropState(forLocalY localY: CGFloat) {
        lastDropY = localY
        let insertionIndex = insertionIndex(for: localY)
        dropIndex = insertionIndex
        dropIntent = .insert(
            sectionID: section.id,
            beforeID: targetID(forInsertionIndex: insertionIndex)
        )
    }

    private func insertionIndex(for localY: CGFloat) -> Int {
        guard !items.isEmpty else { return 0 }

        let rowY = max(0, localY)
        return min(
            items.count,
            max(0, Int((rowY / Self.rowPitch).rounded(.down)))
        )
    }

    private func targetID(forInsertionIndex insertionIndex: Int) -> UUID? {
        guard insertionIndex < items.count else { return nil }
        return items[insertionIndex].id
    }

    private func updateAutoScroll(forViewportY viewportY: CGFloat) {
        updateAutoScrollState(forViewportY: viewportY)
        startAutoScrollTracking()
    }

    private func updateAutoScrollState(forViewportY viewportY: CGFloat) {
        guard let trigger = TodoDragMetrics.autoScrollTrigger(for: viewportY, viewportHeight: viewportHeight) else {
            autoScrollDirection = nil
            autoScrollVelocity = 0
            return
        }

        autoScrollDirection = trigger.direction
        autoScrollVelocity = scrollVelocity(depth: trigger.depth)
    }

    private func startAutoScrollTracking() {
        guard autoScrollTask == nil else { return }
        autoScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                trackAutoScrollTick()
                try? await Task.sleep(for: TodoDragMotion.frameInterval)
            }
        }
    }

    private func trackAutoScrollTick() {
        guard draggingItemID != nil else {
            stopAutoScroll()
            return
        }

        guard isPointerInsideWindow() else {
            cancelDrag()
            return
        }

        guard let viewportY = currentViewportY(),
              let trigger = TodoDragMetrics.autoScrollTrigger(for: viewportY, viewportHeight: viewportHeight)
        else {
            autoScrollDirection = nil
            autoScrollVelocity = 0
            return
        }

        autoScrollDirection = trigger.direction
        autoScrollVelocity = scrollVelocity(depth: trigger.depth)
        scrollOneTick(trigger.direction)
    }

    private func scrollOneTick(_ direction: TodoAutoScrollDirection) {
        guard !items.isEmpty else { return }

        let deltaY: CGFloat
        switch direction {
        case .up:
            deltaY = -autoScrollVelocity
        case .down:
            deltaY = autoScrollVelocity
        }

        let appliedDelta = scrollBy(deltaY)
        guard abs(appliedDelta) > 0.1 else { return }

        lastDropY = max(0, lastDropY + appliedDelta)
        updateDropState(forLocalY: lastDropY)
    }

    private func stopAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        autoScrollDirection = nil
        autoScrollIndex = nil
        autoScrollVelocity = 0
    }

    private func scrollVelocity(depth: CGFloat) -> CGFloat {
        TodoDragMotion.scrollDelta(depth: depth)
    }

    private func finishDrag() {
        draggingItemID = nil
        dropIntent = .none
        dropIndex = nil
        dragResetTask?.cancel()
        dragResetTask = nil
        autoScrollTask?.cancel()
        autoScrollTask = nil
        autoScrollDirection = nil
        autoScrollIndex = nil
        autoScrollVelocity = 0
    }

    private func cancelDrag() {
        finishDrag()
    }

    private static let rowPitch: CGFloat = 31
}

@MainActor
private struct TodoSectionListDropDelegate: DropDelegate {
    let sections: [TodoSectionEntity]
    let isCompletedColumn: Bool
    let vm: TodoViewModel
    @Binding var draggingSectionID: UUID?
    @Binding var dropIntent: TodoDropIntent
    @Binding var lastDropY: CGFloat
    @Binding var dropIndex: Int?
    @Binding var dragResetTask: Task<Void, Never>?
    @Binding var autoScrollTask: Task<Void, Never>?
    @Binding var autoScrollDirection: TodoAutoScrollDirection?
    @Binding var autoScrollIndex: Int?
    @Binding var autoScrollVelocity: CGFloat

    func dropEntered(info: DropInfo) {
        guard draggingSectionID != nil else { return }
        updateDropState(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggingSectionID != nil else { return nil }
        updateDropState(info: info)
        return DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggingSectionID != nil
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceID = draggingSectionID else { return false }
        updateDropState(info: info)
        let resolvedTargetID: UUID?
        switch dropIntent {
        case .sectionInsert(let beforeID):
            resolvedTargetID = beforeID
        default:
            resolvedTargetID = targetID(forInsertionIndex: dropIndex ?? insertionIndex(for: lastDropY))
        }

        performImmediateTodoDrop {
            vm.moveSection(id: sourceID, before: resolvedTargetID, isCompletedSection: isCompletedColumn)
            finishDrag()
        }
        return true
    }

    func dropExited(info: DropInfo) {
        dropIntent = .none
        dropIndex = nil
    }

    private func updateDropState(info: DropInfo) {
        guard draggingSectionID != nil else { return }
        lastDropY = info.location.y
        let nextIndex = insertionIndex(for: info.location.y)
        dropIndex = nextIndex
        dropIntent = .sectionInsert(beforeID: targetID(forInsertionIndex: nextIndex))
    }

    private func insertionIndex(for localY: CGFloat) -> Int {
        guard !sections.isEmpty else { return 0 }
        let rowY = max(0, localY)
        return min(
            sections.count,
            max(0, Int((rowY / Self.rowPitch).rounded(.down)))
        )
    }

    private func targetID(forInsertionIndex insertionIndex: Int) -> UUID? {
        guard insertionIndex < sections.count else { return nil }
        return sections[insertionIndex].id
    }

    private func finishDrag() {
        draggingSectionID = nil
        dropIntent = .none
        dropIndex = nil
        dragResetTask?.cancel()
        dragResetTask = nil
        autoScrollTask?.cancel()
        autoScrollTask = nil
        autoScrollDirection = nil
        autoScrollIndex = nil
        autoScrollVelocity = 0
    }

    private static let rowPitch: CGFloat = 31
}

@MainActor
private struct TodoColumnDropDelegate: DropDelegate {
    let items: [TodoEntity]
    let vm: TodoViewModel
    let viewportHeight: CGFloat
    let currentViewportY: () -> CGFloat?
    let isPointerInsideWindow: () -> Bool
    let localToViewportY: (CGFloat) -> CGFloat
    let scrollBy: (CGFloat) -> CGFloat
    @Binding var draggingItemID: UUID?
    @Binding var dropIntent: TodoDropIntent
    @Binding var lastDropY: CGFloat
    @Binding var dropIndex: Int?
    @Binding var dragResetTask: Task<Void, Never>?
    @Binding var autoScrollTask: Task<Void, Never>?
    @Binding var autoScrollDirection: TodoAutoScrollDirection?
    @Binding var autoScrollIndex: Int?
    @Binding var autoScrollVelocity: CGFloat

    func dropEntered(info: DropInfo) {
        updateDropState(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggingItemID != nil else { return nil }
        updateDropState(info: info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceID = draggingItemID else { return false }
        // During auto-scroll the pointer can remain stationary while the
        // content moves underneath it. scrollOneTick keeps dropIndex synced to
        // that shifted content position, so the final drop must use dropIndex
        // instead of recalculating from DropInfo.location with possibly stale
        // geometry.
        let resolvedIndex = dropIndex ?? insertionIndex(for: lastDropY)
        let resolvedTargetID: UUID?
        switch dropIntent {
        case .insert(_, let beforeID):
            resolvedTargetID = beforeID
        case .none:
            resolvedTargetID = targetID(forInsertionIndex: resolvedIndex)
        case .root, .folder, .sectionInsert:
            return false
        }

        performImmediateTodoDrop {
            vm.moveActiveItem(id: sourceID, before: resolvedTargetID)
            finishDrag()
        }
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggingItemID != nil
    }

    private func updateDropState(info: DropInfo) {
        scheduleDropTargetUpdate(forLocalY: info.location.y)
        updateAutoScroll(forViewportY: currentViewportY() ?? localToViewportY(info.location.y))
    }

    private func scheduleDropTargetUpdate(forLocalY localY: CGFloat) {
        guard draggingItemID != nil else { return }
        let nextIndex = stabilizedInsertionIndex(for: localY)
        let nextTargetItem = targetItem(forInsertionIndex: nextIndex)
        let nextTargetID = nextTargetItem?.id
        let nextIntent = TodoDropIntent.insert(sectionID: nil, beforeID: nextTargetID)

        if dropIntent == nextIntent,
           dropIndex == nextIndex,
           abs(lastDropY - localY) < 4 {
            return
        }

        lastDropY = localY
        dropIndex = nextIndex
        dropIntent = nextIntent
    }

    private func stabilizedInsertionIndex(for contentY: CGFloat) -> Int {
        insertionIndex(for: contentY)
    }

    private func insertionIndex(for contentY: CGFloat) -> Int {
        guard !items.isEmpty else { return 0 }

        let clampedY = max(0, contentY)
        return min(
            items.count,
            max(0, Int((clampedY / Self.rowPitch).rounded(.down)))
        )
    }

    private func targetID(forInsertionIndex insertionIndex: Int) -> UUID? {
        targetItem(forInsertionIndex: insertionIndex)?.id
    }

    private func targetItem(forInsertionIndex insertionIndex: Int) -> TodoEntity? {
        guard insertionIndex < items.count else { return nil }
        return items[insertionIndex]
    }

    private func updateAutoScroll(forViewportY viewportY: CGFloat) {
        updateAutoScrollState(forViewportY: viewportY)
        startAutoScrollTracking()
    }

    private func updateAutoScrollState(forViewportY viewportY: CGFloat) {
        guard let trigger = TodoDragMetrics.autoScrollTrigger(for: viewportY, viewportHeight: viewportHeight) else {
            autoScrollDirection = nil
            autoScrollVelocity = 0
            return
        }

        autoScrollDirection = trigger.direction
        autoScrollVelocity = scrollVelocity(depth: trigger.depth)
        if autoScrollIndex == nil {
            autoScrollIndex = dropIndex ?? items.count
        }
    }

    private func startAutoScrollTracking() {
        guard autoScrollTask == nil else { return }
        autoScrollTask = Task { @MainActor in
            while !Task.isCancelled {
                trackAutoScrollTick()
                try? await Task.sleep(for: TodoDragMotion.frameInterval)
            }
        }
    }

    private func trackAutoScrollTick() {
        guard draggingItemID != nil else {
            stopAutoScroll()
            return
        }

        guard isPointerInsideWindow() else {
            cancelDrag()
            return
        }

        guard let viewportY = currentViewportY(),
              let trigger = TodoDragMetrics.autoScrollTrigger(for: viewportY, viewportHeight: viewportHeight)
        else {
            autoScrollDirection = nil
            autoScrollVelocity = 0
            return
        }

        autoScrollDirection = trigger.direction
        autoScrollVelocity = scrollVelocity(depth: trigger.depth)
        scrollOneTick(trigger.direction)
    }

    private func scrollOneTick(_ direction: TodoAutoScrollDirection) {
        guard !items.isEmpty else { return }

        let deltaY: CGFloat
        switch direction {
        case .up:
            deltaY = -autoScrollVelocity
        case .down:
            deltaY = autoScrollVelocity
        }

        let appliedDelta = scrollBy(deltaY)
        guard abs(appliedDelta) > 0.1 else { return }

        // Keep the insertion point tied to the stationary mouse position while
        // content scrolls underneath it. This avoids drift after repeated
        // up/down auto-scroll changes.
        lastDropY = max(0, lastDropY + appliedDelta)
        let pointerIndex = insertionIndex(for: lastDropY)
        autoScrollIndex = pointerIndex
        dropIndex = pointerIndex
        let targetItem = targetItem(forInsertionIndex: pointerIndex)
        dropIntent = .insert(
            sectionID: nil,
            beforeID: targetItem?.id
        )
    }

    private func stopAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        autoScrollDirection = nil
        autoScrollIndex = nil
        autoScrollVelocity = 0
    }

    private func finishDrag() {
        draggingItemID = nil
        dropIntent = .none
        dropIndex = nil
        dragResetTask?.cancel()
        dragResetTask = nil
        stopAutoScroll()
    }

    private func cancelDrag() {
        finishDrag()
    }

    private func scrollVelocity(depth: CGFloat) -> CGFloat {
        TodoDragMotion.scrollDelta(depth: depth)
    }

    private static let rowPitch: CGFloat = 31
}

private enum TodoAutoScrollDirection {
    case up
    case down

    var label: String {
        switch self {
        case .up:
            return "up"
        case .down:
            return "down"
        }
    }
}

enum TodoDragMotion {
    static let frameInterval: Duration = .milliseconds(16)
    static let rootDropTargetMinimumHeight = SchedulerControl.minimumTarget

    static func isRootDropTargetVisible(draggingItemID: UUID?) -> Bool {
        draggingItemID != nil
    }

    static func scrollDelta(depth: CGFloat) -> CGFloat {
        let normalizedDepth = max(0, min(1, depth))
        let baseDelta: CGFloat = 0.69
        return baseDelta * (1 + normalizedDepth * 4)
    }
}

private enum TodoDragPayload {
    static let type = UTType.text
    static let typeIdentifier = type.identifier
}

private enum TodoDragMetrics {
    static let autoScrollLineDistance: CGFloat = 50
    static let topAutoScrollTriggerLineY: CGFloat = autoScrollLineDistance
    static let bottomAutoScrollTriggerLineInset: CGFloat = autoScrollLineDistance

    static func autoScrollTrigger(
        for viewportY: CGFloat,
        viewportHeight: CGFloat
    ) -> (direction: TodoAutoScrollDirection, depth: CGFloat)? {
        let topTriggerLineY = topAutoScrollTriggerLineY
        let bottomTriggerLineY = max(topTriggerLineY, viewportHeight - bottomAutoScrollTriggerLineInset)

        if viewportY <= topTriggerLineY {
            return (.up, triggerDepth(from: viewportY, beyond: topTriggerLineY))
        }

        if viewportY >= bottomTriggerLineY {
            return (.down, triggerDepth(from: viewportY, beyond: bottomTriggerLineY))
        }

        return nil
    }

    static func triggerDepth(from viewportY: CGFloat, beyond triggerLineY: CGFloat) -> CGFloat {
        max(0, min(1, abs(viewportY - triggerLineY) / autoScrollLineDistance))
    }
}

@MainActor
private func performImmediateTodoDrop(_ action: () -> Void) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction) {
        action()
    }
}

private enum TodoScrollTarget: Hashable {
    case item(UUID)
    case bottom
}

private enum TodoScrollSpace {
    static let active = "TodoActiveScrollSpace"
}

private struct TodoContentMinYPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TodoScrollViewResolver: NSViewRepresentable {
    let onResolve: (NSScrollView?) -> Void

    func makeNSView(context: Context) -> ResolverView {
        ResolverView(onResolve: onResolve)
    }

    func updateNSView(_ nsView: ResolverView, context: Context) {
        nsView.onResolve = onResolve
        nsView.resolve()
    }

    final class ResolverView: NSView {
        var onResolve: (NSScrollView?) -> Void

        init(onResolve: @escaping (NSScrollView?) -> Void) {
            self.onResolve = onResolve
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            resolve()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            resolve()
        }

        func resolve() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.onResolve(self.findEnclosingScrollView())
            }
        }

        private func findEnclosingScrollView() -> NSScrollView? {
            var view: NSView? = self
            while let current = view {
                if let scrollView = current as? NSScrollView {
                    return scrollView
                }
                view = current.superview
            }
            return enclosingScrollView
        }
    }
}

private extension View {
    @ViewBuilder
    func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
