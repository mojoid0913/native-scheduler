import XCTest
import AppKit
import ApplicationServices
import CoreData
import CryptoKit
import Combine
import os
import SwiftUI
@testable import NativeScheduler

final class NotchShellTests: XCTestCase {
    @MainActor
    private final class TestTimerEngineTicker: TimerEngineTicker {
        func cancel() {}
    }

    @MainActor
    private final class ManualNotchCompletionScheduler {
        final class Token: NotchScheduledAction {
            private let cancellation = OSAllocatedUnfairLock(initialState: false)

            var isCancelled: Bool {
                cancellation.withLock { $0 }
            }

            func cancel() {
                cancellation.withLock { $0 = true }
            }
        }

        struct Entry {
            let deadline: TimeInterval
            let token: Token
            let action: @MainActor () -> Void
        }

        private(set) var now: TimeInterval = 0
        private(set) var entries: [Entry] = []

        lazy var schedule: NotchTimerState.CompletionPhaseScheduler = { [weak self] delay, action in
            let token = Token()
            guard let self else {
                token.cancel()
                return token
            }
            entries.append(Entry(deadline: now + delay, token: token, action: action))
            return token
        }

        func advance(by interval: TimeInterval) {
            now += interval
            let due = entries.indices.filter {
                entries[$0].deadline <= now && !entries[$0].token.isCancelled
            }
            for index in due {
                entries[index].token.cancel()
                entries[index].action()
            }
        }

        func deliverIgnoringCancellation(at index: Int) {
            entries[index].action()
        }
    }

    private struct Task8RenderScenario {
        let name: String
        let now: Date
        let calendar: Calendar
        let notchHeight: CGFloat
        let categoryHexes: [String?]
        let startsTimer: Bool
        let timerCategoryHex: String?
        let reduceMotion: Bool
        let showsRecordingRetry: Bool
    }

    private struct ExternalProcessResult {
        let command: [String]
        let stdout: String
        let stderr: String
        let exitStatus: Int32
    }

    private struct NativeAXInvocation {
        let process: ExternalProcessResult
        let clientBinarySHA256: String
        let targetPID: pid_t
        let windowIdentifier: String
        let elementIdentifier: String

        func json(result: [String: Any]) -> [String: Any] {
            [
                "command": process.command,
                "clientBinarySHA256": clientBinarySHA256,
                "targetPID": Int(targetPID),
                "windowIdentifier": windowIdentifier,
                "elementIdentifier": elementIdentifier,
                "action": kAXPressAction as String,
                "stdout": process.stdout,
                "stderr": process.stderr,
                "exitStatus": Int(process.exitStatus),
                "deliveryValidated": true,
                "result": result
            ]
        }
    }

    private struct NativeAXNode {
        let traversalIndex: Int
        let role: String
        let label: String
        let identifier: String
        let isEnabled: Bool
        let frame: CGRect
        let actions: [String]
        let value: String

        private func jsonNumber(_ value: CGFloat) -> Any {
            value.isFinite ? value : NSNull()
        }

        var json: [String: Any] {
            [
                "traversalIndex": traversalIndex,
                "role": role,
                "label": label,
                "identifier": identifier,
                "isEnabled": isEnabled,
                "value": value,
                "frameIsFinite": frame.origin.x.isFinite
                    && frame.origin.y.isFinite
                    && frame.width.isFinite
                    && frame.height.isFinite,
                "frame": [
                    "x": jsonNumber(frame.origin.x),
                    "y": jsonNumber(frame.origin.y),
                    "width": jsonNumber(frame.width),
                    "height": jsonNumber(frame.height)
                ],
                "actions": actions
            ]
        }
    }

    private final class AXResultBox<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<Value, Error>?

        func store(_ result: Result<Value, Error>) {
            lock.lock()
            self.result = result
            lock.unlock()
        }

        func load() -> Result<Value, Error>? {
            lock.lock()
            defer { lock.unlock() }
            return result
        }
    }

    @MainActor
    private final class LayoutCapture {
        var probe: MainPanelLayoutProbe?
    }

    private struct CollapsedTimerFixture {
        let container: NSPersistentContainer
        let timerVM: TimerViewModel
        let host: NSHostingView<TimerView>
        let window: NSWindow
        let windowIdentifier: String
    }

    @MainActor
    func testNonHoveredFolderActionsStayHiddenThroughNativeAccessibility() async throws {
        NSApplication.shared.finishLaunching()
        XCTAssertTrue(AXIsProcessTrusted(), "Native AX testing requires pre-granted accessibility trust.")

        let container = NSPersistentContainer(name: "FolderActionsAX", managedObjectModel: CoreDataStack.model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        let section = TodoSectionEntity.create(
            title: "QA Folder",
            isCompletedSection: false,
            sortOrder: 0,
            in: container.viewContext
        )
        try container.viewContext.save()

        var toggleCount = 0
        let root = TodoSectionHeaderView(
            section: section,
            itemCount: 0,
            isEditing: false,
            isDropTarget: false,
            showsMoveHandle: true,
            isDragActive: false,
            editingTitle: .constant(""),
            onDragProvider: nil,
            onToggle: { toggleCount += 1 },
            onCommitTitle: {},
            onEdit: {},
            onDelete: {}
        )
        .frame(width: 320, height: 40)
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 40)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        let windowIdentifier = "todo.folder.actions.ax"
        window.title = windowIdentifier
        window.setAccessibilityIdentifier(windowIdentifier)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        let nodes = try runAXOperation {
            try Self.nativeAccessibilityNodes(
                processID: getpid(),
                windowIdentifier: windowIdentifier
            )
        }
        let toggle = try XCTUnwrap(
            nodes.first { $0.identifier == "todo.folder.toggle.\(section.id.uuidString)" }
        )
        XCTAssertEqual(toggle.label, "QA Folder folder")
        XCTAssertNil(nodes.first { $0.identifier == "todo.folder.edit.\(section.id.uuidString)" })
        XCTAssertNil(nodes.first { $0.identifier == "todo.folder.delete.\(section.id.uuidString)" })
        XCTAssertEqual(toggleCount, 0)

        let tracker = try XCTUnwrap(todoRowHoverTrackers(in: host).first)
        let entered = expectation(description: "native tracker entered folder row")
        let enteredObservation = tracker.hoverState.$isHovered
            .dropFirst()
            .filter { $0 }
            .sink { _ in entered.fulfill() }
        let trackerPoint = tracker.convert(
            CGPoint(x: tracker.bounds.midX, y: tracker.bounds.midY),
            to: nil
        )
        NotificationCenter.default.post(
            name: NotchGlobalPointerEvent.notificationName,
            object: NotchGlobalPointerEvent(screenPoint: window.convertPoint(toScreen: trackerPoint))
        )
        await fulfillment(of: [entered], timeout: 1)
        withExtendedLifetime(enteredObservation) {}
        await Task.yield()

        XCTAssertTrue(tracker.hoverState.isHovered)
        XCTAssertTrue(
            TodoFolderActionVisibility.isVisible(
                isHovered: tracker.hoverState.isHovered,
                isDragActive: false
            )
        )
        XCTAssertFalse(
            TodoFolderActionVisibility.isVisible(
                isHovered: tracker.hoverState.isHovered,
                isDragActive: true
            )
        )
    }

    @MainActor
    func testExpandedRunningCategorySelectorInvokesItsActionThroughNativeAccessibility() throws {
        NSApplication.shared.finishLaunching()
        let container = NSPersistentContainer(name: "LowerControls", managedObjectModel: CoreDataStack.model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        let study = CategoryEntity.create(
            name: "Study",
            colorHex: "#FFA94D",
            sortOrder: 0,
            in: container.viewContext
        )
        try container.viewContext.save()

        let engine = TimerEngine()
        engine.mode = .duration
        let timerVM = TimerViewModel(
            engine: engine,
            context: container.viewContext,
            now: Date.init,
            save: { context in
                if context.hasChanges { try context.save() }
            }
        )
        timerVM.start()

        let root = TimerView(vm: timerVM, isDaylineExpanded: true)
            .frame(width: 232, height: 96)
        let windowState = NotchWindowState()
        windowState.isExpanded = true
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(x: 0, y: 0, width: 232, height: 96)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        let windowIdentifier = "lower-controls.ax"
        window.title = windowIdentifier
        window.setAccessibilityIdentifier(windowIdentifier)
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()

        var interactionLocks: [Bool] = []
        let observer = NotificationCenter.default.addObserver(
            forName: .nativeSchedulerInteractionLockChanged,
            object: nil,
            queue: .main
        ) { notification in
            if let isLocked = notification.object as? Bool {
                interactionLocks.append(isLocked)
            }
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            timerVM.stop()
            window.orderOut(nil)
        }

        let clientDirectory = FileManager.default.temporaryDirectory
            .appending(path: "LowerControlsAXClient-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: clientDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: clientDirectory) }
        let client = try compileNativeAXClient(in: clientDirectory)
        let clientHash = try sha256(of: client)
        let categoryButton = try XCTUnwrap(nativeButton(
            withAccessibilityIdentifier: "timer.category",
            in: host
        ))
        let lockAcquired = expectation(
            forNotification: .nativeSchedulerInteractionLockChanged,
            object: nil
        ) { $0.object as? Bool == true }
        _ = try performExternalAXPress(
            client: client,
            clientSHA256: clientHash,
            windowIdentifier: windowIdentifier,
            elementIdentifier: "timer.category"
        )
        wait(for: [lockAcquired], timeout: 1)

        var popoverWindows = categoryPopoverWindows(excluding: window)
        XCTAssertEqual(popoverWindows.count, 1)
        XCTAssertEqual(popoverWindows[0].frame.size, CGSize(width: 246, height: 254))
        XCTAssertEqual(interactionLocks, [true], "Opening once must acquire exactly one interaction lock.")

        let firstStudy = try performExternalAXJSON(
            client: client,
            arguments: ["inspect", String(getpid()), "timer.category.popover", "timer.category.option.Study"]
        )
        let firstStudyFrame = try jsonFrame(firstStudy.json, key: "elementFrame")
        XCTAssertEqual(firstStudyFrame.width, 196, accuracy: 0.5)
        XCTAssertEqual(firstStudyFrame.height, TimerViewDensity.minimumActionTarget, accuracy: 0.5)

        XCTAssertTrue(categoryButton.accessibilityPerformPress())
        popoverWindows = categoryPopoverWindows(excluding: window)
        XCTAssertEqual(popoverWindows.count, 1)
        XCTAssertEqual(interactionLocks, [true], "Repeated activation must not duplicate the popover or acquire another lock.")

        windowState.collapseForPointerExit()
        XCTAssertTrue(windowState.isExpanded, "Pointer exit must not collapse while the category popover owns the lock.")
        popoverWindows = categoryPopoverWindows(excluding: window)
        XCTAssertEqual(popoverWindows.count, 1)
        XCTAssertEqual(interactionLocks, [true], "Pointer exit must not mutate the held lock.")

        let mode = try performExternalAXJSON(
            client: client,
            arguments: ["inspect", String(getpid()), windowIdentifier, "timer.mode"]
        )
        XCTAssertEqual(mode.json["enabled"] as? Bool, false)
        XCTAssertEqual(mode.json["help"] as? String, "Timer mode cannot be changed while the timer is active.")

        let lockReleased = expectation(
            forNotification: .nativeSchedulerInteractionLockChanged,
            object: nil
        ) { $0.object as? Bool == false }
        _ = try performExternalAXPress(
            client: client,
            clientSHA256: clientHash,
            windowIdentifier: "timer.category.popover",
            elementIdentifier: "timer.category.option.Study"
        )
        wait(for: [lockReleased], timeout: 1)
        XCTAssertEqual(timerVM.selectedCategory, study)
        popoverWindows = categoryPopoverWindows(excluding: window)
        XCTAssertEqual(popoverWindows.count, 0)
        XCTAssertEqual(interactionLocks, [true, false], "Selection must dismiss and release exactly one lock.")

        let selectedCategory = try performExternalAXJSON(
            client: client,
            arguments: ["inspect", String(getpid()), windowIdentifier, "timer.category"]
        )
        XCTAssertEqual(selectedCategory.json["label"] as? String, "Select category: Study")

        windowState.collapseForPointerExit()
        XCTAssertFalse(windowState.isExpanded, "Normal pointer-exit collapse must resume after dismissal.")
    }

    @MainActor
    func testCollapsedTimerPreservesNormalStartModeAndCategoryControls() throws {
        let fixture = try makeCollapsedTimerFixture(retryableFinalization: false)
        defer { fixture.window.orderOut(nil) }

        let nodes = try runAXOperation {
            try Self.nativeAccessibilityNodes(
                processID: getpid(),
                windowIdentifier: fixture.windowIdentifier
            )
        }

        let start = try XCTUnwrap(nodes.first { $0.label == "Start" })
        XCTAssertEqual(start.role, kAXButtonRole as String)
        XCTAssertTrue(start.actions.contains(kAXPressAction as String))
        XCTAssertTrue(start.isEnabled)
        XCTAssertNotNil(nodes.first { $0.identifier == "timer.category" })
        XCTAssertNotNil(nodes.first { $0.identifier == "timer.mode" })
    }

    @MainActor
    func testCollapsedTimerExposesRetryAndDisablesStartUntilFinalizationSucceeds() throws {
        let fixture = try makeCollapsedTimerFixture(retryableFinalization: true)
        defer { fixture.window.orderOut(nil) }
        let outputDirectory = ProcessInfo.processInfo.environment["COLLAPSED_TIMER_QA_OUTPUT"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        if let outputDirectory {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }
        let clientDirectory = FileManager.default.temporaryDirectory
            .appending(path: "CollapsedTimerAXClient-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: clientDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: clientDirectory) }
        let client = try compileNativeAXClient(in: clientDirectory)
        let clientHash = try sha256(of: client)

        let pendingNodes = try runAXOperation {
            try Self.nativeAccessibilityNodes(
                processID: getpid(),
                windowIdentifier: fixture.windowIdentifier
            )
        }
        let retry = try XCTUnwrap(
            pendingNodes.first { $0.identifier == "timer.recording.retry" },
            "Collapsed timer must expose the retryable recording failure."
        )
        XCTAssertEqual(retry.role, kAXButtonRole as String)
        XCTAssertTrue(retry.actions.contains(kAXPressAction as String))
        XCTAssertTrue(retry.isEnabled)
        XCTAssertFalse(
            try XCTUnwrap(pendingNodes.first { $0.label == "Start" }).isEnabled,
            "Start must stay disabled while finalization is pending."
        )
        if let outputDirectory {
            try writeViewSnapshot(fixture.host, to: outputDirectory.appending(path: "collapsed-pending-finalization.png"))
        }

        let retryRecovered = expectation(description: "Timer retry recovered")
        var retryObservation: AnyCancellable? = fixture.timerVM.$recordingError
            .dropFirst()
            .filter { $0 == nil }
            .sink { _ in retryRecovered.fulfill() }
        _ = try performExternalAXPress(
            client: client,
            clientSHA256: clientHash,
            windowIdentifier: fixture.windowIdentifier,
            elementIdentifier: "timer.recording.retry"
        )
        wait(for: [retryRecovered], timeout: 2)
        retryObservation?.cancel()
        retryObservation = nil
        fixture.host.rootView = TimerView(vm: fixture.timerVM, isDaylineExpanded: false)
        fixture.host.layoutSubtreeIfNeeded()
        fixture.host.displayIfNeeded()
        XCTAssertFalse(fixture.timerVM.canRetryFinalization)
        XCTAssertNil(fixture.timerVM.recordingError)

        let recoveredNodes = try runAXOperation {
            try Self.nativeAccessibilityNodes(
                processID: getpid(),
                windowIdentifier: fixture.windowIdentifier
            )
        }
        XCTAssertNil(recoveredNodes.first { $0.identifier == "timer.recording.retry" })
        XCTAssertTrue(try XCTUnwrap(recoveredNodes.first { $0.label == "Start" }).isEnabled)
        if let outputDirectory {
            try writeViewSnapshot(fixture.host, to: outputDirectory.appending(path: "collapsed-recovered.png"))
            try writeJSON([
                "pending": pendingNodes.map(\.json),
                "recovered": recoveredNodes.map(\.json),
                "retryRecovered": !fixture.timerVM.canRetryFinalization && fixture.timerVM.recordingError == nil
            ], to: outputDirectory.appending(path: "collapsed-retry-ax.json"))
        }
    }

    @MainActor
    func testSettingsLaunchFailureSectionExposesRollbackError() throws {
        NSApplication.shared.finishLaunching()
        NSApplication.shared.activate(ignoringOtherApps: true)
        let errorMessage = "Launch at login could not be updated and was restored."
        let host = NSHostingView(
            rootView: SettingsLaunchAtLoginSection(
                isEnabled: .constant(false),
                errorMessage: errorMessage,
                onChange: { _ in }
            )
            .frame(width: 336, height: 96)
        )
        host.frame = CGRect(x: 0, y: 0, width: 336, height: 96)
        let windowIdentifier = "settings-launch-failure.ax.\(UUID().uuidString)"
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.title = windowIdentifier
        window.setAccessibilityIdentifier(windowIdentifier)
        window.contentView = host
        window.orderFront(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        let nodes = try Self.nativeAccessibilityNodes(
            processID: getpid(),
            windowIdentifier: windowIdentifier
        )
        XCTAssertNotNil(nodes.first { $0.identifier == "settings.launchAtLogin.toggle" })
        XCTAssertNotNil(nodes.first { $0.identifier == "settings.launchAtLogin.error" })
        XCTAssertEqual(
            SettingsLaunchAtLoginSection.errorColor.hexString,
            Color.daylineError.hexString
        )

        if let output = ProcessInfo.processInfo.environment["SETTINGS_FAILURE_QA_OUTPUT"] {
            let outputDirectory = URL(filePath: output, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
            try writeViewSnapshot(
                host,
                to: outputDirectory.appending(path: "launch-at-login-failure.png")
            )
        }
    }

    @MainActor
    private func makeCollapsedTimerFixture(retryableFinalization: Bool) throws -> CollapsedTimerFixture {
        NSApplication.shared.finishLaunching()
        let container = NSPersistentContainer(
            name: "CollapsedTimerFixture",
            managedObjectModel: CoreDataStack.model
        )
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        let engine = TimerEngine()
        engine.mode = .duration
        var saveAttempt = 0
        let timerVM = TimerViewModel(
            engine: engine,
            context: container.viewContext,
            now: Date.init
        ) { context in
            saveAttempt += 1
            if retryableFinalization, saveAttempt == 2 {
                throw NSError(domain: "CollapsedTimerFixture", code: 1)
            }
            if context.hasChanges { try context.save() }
        }
        if retryableFinalization {
            timerVM.start()
            timerVM.stop()
            XCTAssertTrue(timerVM.canRetryFinalization)
        }

        let host = NSHostingView(rootView: TimerView(vm: timerVM, isDaylineExpanded: false))
        host.frame = CGRect(x: 0, y: 0, width: 232, height: 140)
        let windowIdentifier = "collapsed-timer.ax.\(UUID().uuidString)"
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.title = windowIdentifier
        window.setAccessibilityIdentifier(windowIdentifier)
        window.contentView = host
        let windowReady = expectation(
            forNotification: NSWindow.didUpdateNotification,
            object: window
        )
        window.orderFront(nil)
        wait(for: [windowReady], timeout: 2)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        return CollapsedTimerFixture(
            container: container,
            timerVM: timerVM,
            host: host,
            window: window,
            windowIdentifier: windowIdentifier
        )
    }

    @MainActor
    private func performExternalAXJSON(
        client: URL,
        arguments: [String]
    ) throws -> (process: ExternalProcessResult, json: [String: Any]) {
        let result = try runExternalProcess(executable: client, arguments: arguments, timeout: 4)
        guard result.exitStatus == 0, result.stderr.isEmpty else {
            throw NSError(domain: "NativeAXClient", code: Int(result.exitStatus), userInfo: [
                NSLocalizedDescriptionKey: "Native AX inspection failed: \(result.stderr)"
            ])
        }
        let data = Data(result.stdout.utf8)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "NativeAXClient", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Native AX inspection returned non-object JSON."
            ])
        }
        return (result, json)
    }

    private func jsonFrame(_ json: [String: Any], key: String) throws -> CGRect {
        let frame = try XCTUnwrap(json[key] as? [String: Any])
        return CGRect(
            x: try XCTUnwrap(frame["x"] as? Double),
            y: try XCTUnwrap(frame["y"] as? Double),
            width: try XCTUnwrap(frame["width"] as? Double),
            height: try XCTUnwrap(frame["height"] as? Double)
        )
    }

    @MainActor
    private func categoryPopoverWindows(excluding hostWindow: NSWindow) -> [NSWindow] {
        NSApplication.shared.windows.filter {
            $0 !== hostWindow
                && $0.isVisible
                && ($0.title == "timer.category.popover"
                    || $0.identifier?.rawValue == "timer.category.popover")
        }
    }


    func testCollapsedLayoutReturnsTimerHeightToDaylineInsideTheFixedShell() {
        XCTAssertEqual(NotchGeometry.expandedPanelWidth, 816, accuracy: 0.001)
        XCTAssertEqual(NotchGeometry.expandedPanelHeight, 384, accuracy: 0.001)

        let collapsed = MainPanelLayoutMetrics(width: 776, height: 321, isDaylineExpanded: false)

        XCTAssertEqual(collapsed.width, 776, accuracy: 0.001)
        XCTAssertEqual(collapsed.height, 321, accuracy: 0.001)
        XCTAssertEqual(collapsed.collapsedStackSpacing, 10, accuracy: 0.001)
        XCTAssertEqual(collapsed.collapsedHeatmapHeight, 124.11, accuracy: 0.001)
        XCTAssertEqual(collapsed.collapsedToggleHeight, 0, accuracy: 0.001)
        XCTAssertEqual(collapsed.collapsedTimerHeight, 148, accuracy: 0.001)
        XCTAssertEqual(
            collapsed.heatmapHeight + collapsed.timerHeight + collapsed.stackSpacing,
            collapsed.contentHeight,
            accuracy: 0.001
        )
    }

    func testExpandedLayoutUsesIntegratedDisclosureAndBalancedVerticalGutter() {
        for notchHeight in [32.0, 37.0, 42.0] {
            let childWidth = NotchGeometry.expandedPanelWidth - 40
            let childHeight = NotchGeometry.expandedPanelHeight - (notchHeight + 10) - 16
            let expanded = MainPanelLayoutMetrics(
                width: childWidth,
                height: childHeight,
                isDaylineExpanded: true
            )

            XCTAssertEqual(expanded.width, 776, accuracy: 0.001)
            XCTAssertEqual(expanded.height, childHeight, accuracy: 0.001)
            let stackedContentHeight = expanded.contentHeight - expanded.expandedStackSpacing
            let expectedTimerHeight = min(
                stackedContentHeight,
                min(92, max(78, stackedContentHeight * 0.32))
            )
            XCTAssertEqual(expanded.expandedStackSpacing, 8, accuracy: 0.001)
            XCTAssertEqual(expanded.expandedTimerHeight, expectedTimerHeight, accuracy: 0.001)
            let availableBodyWidth = expanded.contentWidth - expanded.columnSpacing
            XCTAssertEqual(
                expanded.rightWidth,
                min(520, availableBodyWidth * 0.58),
                accuracy: 0.001
            )
            XCTAssertEqual(
                expanded.todoWidth,
                availableBodyWidth - expanded.rightWidth,
                accuracy: 0.001
            )
            XCTAssertEqual(expanded.expandedToggleHeight, 0, accuracy: 0.001)
            XCTAssertEqual(
                expanded.expandedHeatmapHeight,
                stackedContentHeight - expectedTimerHeight,
                accuracy: 0.001
            )
            XCTAssertEqual(
                expanded.heatmapHeight + expanded.timerHeight + expanded.stackSpacing,
                expanded.contentHeight,
                accuracy: 0.001
            )
            XCTAssertEqual(DaylineViewMetrics.expandedInset, 4, accuracy: 0.001)
            let requiredDaylineHeight =
                DaylineViewMetrics.headerHeight
                + DaylineViewMetrics.axisHeight
                + DaylineViewMetrics.dayRowHeight * 5
                + DaylineViewMetrics.detailHeight
                + DaylineViewMetrics.expandedInset * 2
            XCTAssertGreaterThanOrEqual(
                expanded.expandedHeatmapHeight,
                requiredDaylineHeight
            )
        }
    }

    func testExpandedTimerDensityBalancesVisibleTopAndBottomInsets() {
        XCTAssertEqual(TimerViewDensity.expandedTimeBoxHeight, 48, accuracy: 0.001)
        XCTAssertEqual(TimerViewDensity.expandedPrimaryRowHeight, 60, accuracy: 0.001)
        XCTAssertEqual(TimerViewDensity.expandedRowGap, 4, accuracy: 0.001)
        XCTAssertEqual(TimerViewDensity.expandedSecondaryRowHeight, 24, accuracy: 0.001)
        XCTAssertEqual(TimerViewDensity.expandedTopInset, 3, accuracy: 0.001)
        XCTAssertEqual(TimerViewDensity.expandedBottomInset, 9, accuracy: 0.001)
        XCTAssertEqual(
            TimerViewDensity.expandedTopInset
                + (TimerViewDensity.expandedPrimaryRowHeight
                    - TimerViewDensity.expandedTimeBoxHeight) / 2,
            TimerViewDensity.expandedBottomInset,
            accuracy: 0.001
        )
        XCTAssertEqual(TimerViewDensity.minimumActionTarget, 24, accuracy: 0.001)
        XCTAssertEqual(TimerViewDensity.meaningfulTextSize, 11, accuracy: 0.001)
        XCTAssertEqual(
            TimerViewDensity.expandedPrimaryRowHeight
                + TimerViewDensity.expandedRowGap
                + TimerViewDensity.expandedSecondaryRowHeight
                + TimerViewDensity.expandedTopInset
                + TimerViewDensity.expandedBottomInset,
            100,
            accuracy: 0.001
        )
    }

    @MainActor
    func testExpandedTimerLayoutAXInIsolatedHost() throws {
        let childEnvironmentKey = "NATIVE_SCHEDULER_EXPANDED_TIMER_AX_CHILD"
        if ProcessInfo.processInfo.environment[childEnvironmentKey] != "1" {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = [
                "-XCTest",
                "NativeSchedulerTests.NotchShellTests/testExpandedTimerLayoutAXInIsolatedHost",
                Bundle(for: NotchShellTests.self).bundlePath
            ]
            var environment = ProcessInfo.processInfo.environment
            environment[childEnvironmentKey] = "1"
            process.environment = environment
            let standardOutput = Pipe()
            let standardError = Pipe()
            process.standardOutput = standardOutput
            process.standardError = standardError
            let terminated = expectation(description: "isolated expanded Timer AX host exits")
            process.terminationHandler = { _ in terminated.fulfill() }

            try process.run()
            wait(for: [terminated], timeout: 30)

            let output = String(decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let error = String(decoding: standardError.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertEqual(process.terminationStatus, 0, output + error)
            return
        }

        NSApplication.shared.finishLaunching()
        let container = NSPersistentContainer(name: "ExpandedTimerLayout", managedObjectModel: CoreDataStack.model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        let vm = TimerViewModel(
            engine: TimerEngine(soundPlayer: {}),
            context: container.viewContext,
            now: Date.init,
            save: { context in if context.hasChanges { try context.save() } }
        )
        vm.engine.mode = .duration
        vm.engine.durationSeconds = 25 * 60
        vm.engine.reset()
        let size = CGSize(width: 232, height: 96)
        let host = NSHostingView(rootView: TimerView(vm: vm, isDaylineExpanded: true).frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let windowIdentifier = "expanded-timer-layout.ax.\(UUID().uuidString)"
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.title = windowIdentifier
        window.setAccessibilityIdentifier(windowIdentifier)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        let clientDirectory = FileManager.default.temporaryDirectory
            .appending(path: "ExpandedTimerLayoutAXClient-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: clientDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: clientDirectory) }
        let client = try compileNativeAXClient(in: clientDirectory)
        func inspect(_ identifier: String) throws -> [String: Any] {
            try performExternalAXJSON(
                client: client,
                arguments: ["inspect", String(getpid()), windowIdentifier, identifier]
            ).json
        }

        let decrease = try inspect("timer.duration.decrease")
        let value = try inspect("timer.duration.value")
        let increase = try inspect("timer.duration.increase")
        let decreaseFrame = try jsonFrame(decrease, key: "elementFrame")
        let valueFrame = try jsonFrame(value, key: "elementFrame")
        let increaseFrame = try jsonFrame(increase, key: "elementFrame")
        XCTAssertLessThanOrEqual(decreaseFrame.maxX, valueFrame.minX)
        XCTAssertLessThanOrEqual(valueFrame.maxX, increaseFrame.minX)
        XCTAssertEqual(decrease["enabled"] as? Bool, true)
        XCTAssertEqual(increase["enabled"] as? Bool, true)
        XCTAssertEqual(decreaseFrame.size, CGSize(width: 44, height: 44))
        XCTAssertEqual(increaseFrame.size, CGSize(width: 44, height: 44))
        XCTAssertTrue((decrease["actions"] as? [String])?.contains(kAXPressAction as String) == true)
        XCTAssertTrue((increase["actions"] as? [String])?.contains(kAXPressAction as String) == true)

        _ = try inspect("timer.secondary.controls")
        let categoryFrame = try jsonFrame(try inspect("timer.category"), key: "elementFrame")
        let modeFrame = try jsonFrame(try inspect("timer.mode"), key: "elementFrame")
        let secondaryFrame = categoryFrame.union(modeFrame)
        let contentFrame = try jsonFrame(try inspect("timer.expanded.content"), key: "elementFrame")
        XCTAssertGreaterThan(secondaryFrame.minX - contentFrame.minX, 0)
        XCTAssertGreaterThan(contentFrame.maxX - secondaryFrame.maxX, 0)
        XCTAssertEqual(secondaryFrame.midX, contentFrame.midX, accuracy: 1)
        XCTAssertEqual(modeFrame.width, 96, accuracy: 0.5)
        XCTAssertEqual(TimerMode.allCases.map(\.label), ["Duration", "End Time", "Count Up"])
    }

    @MainActor
    func testDefaultTimerLayoutAXUsesHorizontalDurationControls() throws {
        if try runIsolatedHostedTodoTestIfNeeded(
            environmentKey: "NATIVE_SCHEDULER_DEFAULT_TIMER_AX_CHILD",
            testName: "NativeSchedulerTests.NotchShellTests/testDefaultTimerLayoutAXUsesHorizontalDurationControls"
        ) { return }

        NSApplication.shared.finishLaunching()
        let container = NSPersistentContainer(name: "DefaultTimerLayout", managedObjectModel: CoreDataStack.model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        let vm = TimerViewModel(
            engine: TimerEngine(soundPlayer: {}),
            context: container.viewContext,
            now: Date.init,
            save: { context in if context.hasChanges { try context.save() } }
        )
        vm.engine.mode = .duration
        vm.engine.durationSeconds = 25 * 60
        vm.engine.reset()

        let size = CGSize(width: 232, height: 180)
        let host = NSHostingView(
            rootView: TimerView(vm: vm, isDaylineExpanded: false)
                .frame(width: size.width, height: size.height)
        )
        host.frame = CGRect(origin: .zero, size: size)
        let windowIdentifier = "default-timer-layout.ax.\(UUID().uuidString)"
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.title = windowIdentifier
        window.setAccessibilityIdentifier(windowIdentifier)
        window.contentView = host
        window.orderFront(nil)
        defer {
            window.contentView = nil
            window.close()
        }
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        let clientDirectory = FileManager.default.temporaryDirectory
            .appending(path: "DefaultTimerLayoutAXClient-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: clientDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: clientDirectory) }
        let client = try compileNativeAXClient(in: clientDirectory)
        func inspect(_ identifier: String) throws -> [String: Any] {
            try performExternalAXJSON(
                client: client,
                arguments: ["inspect", String(getpid()), windowIdentifier, identifier]
            ).json
        }

        let decreaseFrame = try jsonFrame(try inspect("timer.duration.decrease"), key: "elementFrame")
        let valueFrame = try jsonFrame(try inspect("timer.duration.value"), key: "elementFrame")
        let increaseFrame = try jsonFrame(try inspect("timer.duration.increase"), key: "elementFrame")
        XCTAssertLessThanOrEqual(decreaseFrame.maxX, valueFrame.minX)
        XCTAssertLessThanOrEqual(valueFrame.maxX, increaseFrame.minX)
        XCTAssertEqual(decreaseFrame.midY, valueFrame.midY, accuracy: 1)
        XCTAssertEqual(valueFrame.midY, increaseFrame.midY, accuracy: 1)
        XCTAssertEqual(decreaseFrame.size, CGSize(width: 44, height: 44))
        XCTAssertEqual(increaseFrame.size, CGSize(width: 44, height: 44))
        let categoryFrame = try jsonFrame(try inspect("timer.category"), key: "elementFrame")
        let modeFrame = try jsonFrame(try inspect("timer.mode"), key: "elementFrame")
        XCTAssertEqual(categoryFrame.union(modeFrame).midX, window.frame.midX, accuracy: 1)
    }

    func testManyCategoryTodayTotalFitsTheRealExpandedSummaryWithoutTruncation() {
        let layout = MainPanelLayoutMetrics(width: 776, height: 321, isDaylineExpanded: true)
        let title = TodayUsageSummaryProjection.totalText(
            4 * 60 * 60 + 15 * 60,
            localeIdentifier: "en_US"
        )
        let font = NSFont.monospacedSystemFont(
            ofSize: TodayUsageSummaryLayout.meaningfulTextSize,
            weight: .semibold
        )
        let measuredWidth = (title as NSString).size(withAttributes: [.font: font]).width
        let availableWidth = TodayUsageSummaryLayout.textColumnWidth(summaryWidth: layout.summaryWidth)

        XCTAssertEqual(title, "Today · 4h 15m")
        XCTAssertGreaterThanOrEqual(TodayUsageSummaryLayout.meaningfulTextSize, 11)
        XCTAssertEqual(TodayUsageSummaryLayout.ringSpacing, 14, accuracy: 0.001)
        XCTAssertEqual(TodayUsageSummaryLayout.contentMaxWidth, 184, accuracy: 0.001)
        XCTAssertGreaterThan(
            layout.summaryWidth
                - TodayUsageSummaryLayout.contentMaxWidth
                - TodayUsageSummaryLayout.horizontalPadding * 2,
            0
        )
        XCTAssertLessThanOrEqual(
            measuredWidth,
            availableWidth,
            "The complete Today total must fit the live 776pt summary without ellipsis."
        )
    }

    func testExpandedLayoutClampsMalformedSmallProposalsWithoutOverflow() {
        let layout = MainPanelLayoutMetrics(width: 0, height: 76, isDaylineExpanded: true)

        XCTAssertGreaterThanOrEqual(layout.timerHeight, 0)
        XCTAssertGreaterThanOrEqual(layout.heatmapHeight, 0)
        XCTAssertGreaterThanOrEqual(layout.stackSpacing, 0)
        XCTAssertLessThanOrEqual(
            layout.heatmapHeight + layout.timerHeight + layout.stackSpacing,
            max(0, layout.contentHeight) + 0.001
        )
    }

    @MainActor
    func testExpandedNotchHostingViewProbesTheRealMainPanelPaddedChildAndAllocation() throws {
        for notchHeight in [32.0, 37.0, 42.0] {
            let capture = LayoutCapture()
            let state = NotchWindowState()
            state.isExpanded = true
            let timerVM = TimerViewModel()
            let probed = expectation(description: "Main panel layout probed at \(notchHeight)")
            let mainPanel = MainPanelView(
                timerVM: timerVM,
                layoutProbe: {
                    capture.probe = $0
                    probed.fulfill()
                }
            )
            let hostingView = NSHostingView(
                rootView: NotchView(
                    windowState: state,
                    timerState: NotchTimerState(),
                    notchSize: CGSize(width: 220, height: notchHeight),
                    expandedContent: AnyView(mainPanel),
                    onQuit: {}
                )
            )
            hostingView.frame = CGRect(x: 0, y: 0, width: 816, height: 384)
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
            wait(for: [probed], timeout: 2)

            let probe = try XCTUnwrap(capture.probe)
            XCTAssertEqual(probe.proposedSize.width, 776, accuracy: 0.001)
            XCTAssertEqual(probe.proposedSize.height, 384 - (notchHeight + 10) - 16, accuracy: 0.001)
            XCTAssertNotEqual(probe.proposedSize, CGSize(width: 776, height: 384))
            XCTAssertEqual(probe.metrics.width, probe.proposedSize.width, accuracy: 0.001)
            XCTAssertEqual(probe.metrics.height, probe.proposedSize.height, accuracy: 0.001)
            let stackedContentHeight = probe.metrics.contentHeight - probe.metrics.expandedStackSpacing
            let expectedTimerHeight = min(
                stackedContentHeight,
                min(92, max(78, stackedContentHeight * 0.32))
            )
            XCTAssertEqual(probe.metrics.expandedTimerHeight, expectedTimerHeight, accuracy: 0.001)
            XCTAssertEqual(probe.metrics.expandedToggleHeight, 0, accuracy: 0.001)
            XCTAssertEqual(
                probe.metrics.expandedHeatmapHeight,
                stackedContentHeight - expectedTimerHeight,
                accuracy: 0.001
            )
        }
    }

    @MainActor
    func testDefaultMainPanelOwnsDisclosurePresentationAcrossNativePress() throws {
        NSApplication.shared.finishLaunching()
        XCTAssertTrue(AXIsProcessTrusted())
        let clientDirectory = FileManager.default.temporaryDirectory
            .appending(path: "NativeSchedulerDefaultDisclosure-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: clientDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: clientDirectory) }
        let client = try compileNativeAXClient(in: clientDirectory)
        let store = DayActivityStore(observesChanges: false, recordsFetcher: { _, _, _ in [] })
        let presentationState = MainPanelPresentationState(isDaylineExpanded: false)
        let size = CGSize(width: 776, height: 321)
        let host = NSHostingView(rootView: MainPanelView(
            timerVM: TimerViewModel(),
            dayActivityStore: store,
            reduceMotionOverride: true,
            presentationState: presentationState
        ).frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        let windowIdentifier = "default-main-panel-disclosure"
        window.title = windowIdentifier
        window.setAccessibilityIdentifier(windowIdentifier)
        window.contentView = host
        NSApplication.shared.activate(ignoringOtherApps: true)
        let windowReady = expectation(
            forNotification: NSWindow.didUpdateNotification,
            object: window
        )
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        wait(for: [windowReady], timeout: 2)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        let initialToggle = try performExternalAXJSON(
            client: client,
            arguments: ["inspect", String(getpid()), windowIdentifier, "dayline.toggle"]
        )
        XCTAssertEqual(initialToggle.json["role"] as? String, kAXButtonRole as String)
        XCTAssertEqual(
            try jsonFrame(initialToggle.json, key: "elementFrame").size,
            CGSize(width: DaylineViewMetrics.minimumActionTarget, height: DaylineViewMetrics.minimumActionTarget)
        )
        let initialNodes = try Self.nativeAccessibilityNodes(
            processID: getpid(),
            windowIdentifier: windowIdentifier
        )
        XCTAssertEqual(initialNodes.filter { $0.identifier == "dayline.toggle" }.count, 1)
        let task10OutputDirectory = ProcessInfo.processInfo.environment["TASK_10_RENDER_OUTPUT"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        if let task10OutputDirectory {
            try FileManager.default.createDirectory(at: task10OutputDirectory, withIntermediateDirectories: true)
            try writePNG(of: host, to: task10OutputDirectory.appending(path: "task-10-compact.png"))
        }
        let nativeButton = try XCTUnwrap(nativeButton(
            withAccessibilityIdentifier: "dayline.toggle",
            in: host
        ))
        XCTAssertEqual(String(describing: type(of: nativeButton)), "DaylineDisclosureNativeButton")
        XCTAssertGreaterThanOrEqual(nativeButton.frame.width, SchedulerControl.minimumTarget)
        XCTAssertGreaterThanOrEqual(nativeButton.frame.height, SchedulerControl.minimumTarget)
        XCTAssertLessThanOrEqual(nativeButton.frame.width, 28)
        XCTAssertLessThanOrEqual(nativeButton.frame.height, 28)
        let expanded = expectation(description: "Dayline expanded")
        var expansionObservation: AnyCancellable? = presentationState.$isDaylineExpanded
            .dropFirst()
            .filter { $0 }
            .sink { _ in expanded.fulfill() }
        let invocation = try performExternalAXPress(
            client: client,
            clientSHA256: try sha256(of: client),
            windowIdentifier: windowIdentifier,
            elementIdentifier: "dayline.toggle"
        )
        wait(for: [expanded], timeout: 2)
        expansionObservation?.cancel()
        expansionObservation = nil
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let nodes = try Self.nativeAccessibilityNodes(
            processID: getpid(),
            windowIdentifier: windowIdentifier
        )
        let toggle = try XCTUnwrap(nodes.first { $0.identifier == "dayline.toggle" })
        XCTAssertEqual(invocation.process.exitStatus, 0)
        XCTAssertTrue(presentationState.isDaylineExpanded)
        XCTAssertEqual(toggle.label, DaylineViewControl.label(isExpanded: true))
        XCTAssertEqual(store.windowSnapshot?.days.count, 5)
        if let task10OutputDirectory {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            try writePNG(of: host, to: task10OutputDirectory.appending(path: "task-10-expanded.png"))
        }

        let collapsed = expectation(description: "Dayline collapsed")
        var collapseObservation: AnyCancellable? = presentationState.$isDaylineExpanded
            .dropFirst()
            .filter { !$0 }
            .sink { _ in collapsed.fulfill() }
        XCTAssertTrue(nativeButton.accessibilityPerformPress())
        wait(for: [collapsed], timeout: 2)
        collapseObservation?.cancel()
        collapseObservation = nil
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let collapsedNodes = try Self.nativeAccessibilityNodes(
            processID: getpid(),
            windowIdentifier: windowIdentifier
        )
        XCTAssertEqual(
            collapsedNodes.first { $0.identifier == "dayline.toggle" }?.label,
            DaylineViewControl.label(isExpanded: false)
        )
        XCTAssertFalse(presentationState.isDaylineExpanded)
        XCTAssertNil(store.windowSnapshot)
    }

    private func nativeButton(
        withAccessibilityIdentifier identifier: String,
        in view: NSView
    ) -> NSButton? {
        if let button = view as? NSButton, button.accessibilityIdentifier() == identifier {
            return button
        }
        return view.subviews.lazy.compactMap {
            self.nativeButton(withAccessibilityIdentifier: identifier, in: $0)
        }.first
    }

    @MainActor
    private func writePNG(of view: NSView, to url: URL) throws {
        let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: image)
        try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: url)
    }

    @MainActor
    private func exitEvent() -> NSEvent {
        NSEvent.enterExitEvent(
            with: .mouseExited,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            trackingNumber: 0,
            userData: nil
        )!
    }

    func testActiveTimerThemeUsesSingleResolver() {
        XCTAssertEqual(TimerViewModel.resolvedThemeColorHex("#ffa94d"), "#FFA94D")
        XCTAssertEqual(TimerViewModel.resolvedThemeColorHex(nil), "#4DABF7")
    }

    func testCategoryAccentHexNormalizesValidValuesAndFallsBackForMalformedValues() {
        XCTAssertEqual(Color.resolvedCategoryHex("#ffa94d"), "#FFA94D")
        XCTAssertEqual(Color.resolvedCategoryHex("FFA94D"), "#FFA94D")
        XCTAssertEqual(Color.resolvedCategoryHex("not-a-color"), "#4DABF7")
        XCTAssertEqual(Color.resolvedCategoryHex(nil), "#4DABF7")
    }

    func testCategoryAccentSnapshotCarriesSelectedCategoryInsteadOfDefaultFallback() {
        let snapshot = NotchTimerSnapshot(
            isRunning: true,
            progress: 0.5,
            categoryColorHex: "#FFA94D"
        )

        XCTAssertEqual(snapshot.categoryColorHex, "#FFA94D")
        XCTAssertNotEqual(snapshot.categoryColorHex, Color.nsDefaultCategory.hexString)
        XCTAssertEqual(NotchTimerSnapshot().categoryColorHex, "#4DABF7")
    }

    @MainActor
    func testCompletionEffectPublishesEveryExactHalfSecondPhaseAndExpiresAtThreeSeconds() {
        assertCompletionEffectProjectsExactEndpointsAndMidPhaseFromAbsoluteElapsedTime()
        let scheduler = ManualNotchCompletionScheduler()
        let start = Date(timeIntervalSince1970: 1_000)
        let state = NotchTimerState(
            scheduleCompletionPhase: scheduler.schedule,
            now: { start }
        )

        state.triggerCompletionEffect()
        XCTAssertEqual(state.completionEffect.generation, 1)
        XCTAssertEqual(state.completionEffect.opacity, 1.0)
        XCTAssertTrue(state.completionEffect.isActive)

        let expected: [(TimeInterval, Double?, Bool)] = [
            (0.5, 0.25, true),
            (0.5, 1.0, true),
            (0.5, 0.25, true),
            (0.5, 1.0, true),
            (0.5, 0.25, true),
            (0.5, nil, false)
        ]
        for (advance, opacity, isActive) in expected {
            scheduler.advance(by: advance)
            XCTAssertEqual(state.completionEffect.opacity, opacity)
            XCTAssertEqual(state.completionEffect.isActive, isActive)
        }
        XCTAssertEqual(scheduler.now, 3.0, accuracy: 0.001)
    }

    @MainActor
    func testDistinctCompletionRestartsAndStaleGenerationCannotMutateReplacement() {
        let scheduler = ManualNotchCompletionScheduler()
        let state = NotchTimerState(scheduleCompletionPhase: scheduler.schedule)

        state.triggerCompletionEffect()
        scheduler.advance(by: 0.5)
        XCTAssertEqual(state.completionEffect.opacity, 0.25)
        let stalePhaseIndex = 1

        state.triggerCompletionEffect()
        XCTAssertEqual(state.completionEffect.generation, 2)
        XCTAssertEqual(state.completionEffect.opacity, 1.0)
        scheduler.deliverIgnoringCancellation(at: stalePhaseIndex)
        XCTAssertEqual(state.completionEffect.generation, 2)
        XCTAssertEqual(state.completionEffect.opacity, 1.0)

        scheduler.advance(by: 0.5)
        XCTAssertEqual(state.completionEffect.opacity, 0.25)
        XCTAssertTrue(state.completionEffect.isActive)
    }

    @MainActor
    func testCompletionLifetimeIsUnaffectedByTimerAndExpansionStateChanges() {
        let scheduler = ManualNotchCompletionScheduler()
        let state = NotchTimerState(scheduleCompletionPhase: scheduler.schedule)
        let windowState = NotchWindowState()
        state.triggerCompletionEffect()
        let generation = state.completionEffect.generation

        state.update(NotchTimerSnapshot(activity: .determinateCountdown(progress: 0.4), categoryColorHex: "#FFA94D"))
        state.update(NotchTimerSnapshot(activity: .idle, categoryColorHex: "#FFA94D"))
        state.update(NotchTimerSnapshot(activity: .activeCountUp, categoryColorHex: "#51CF66"))
        state.update(NotchTimerSnapshot(activity: .idle, categoryColorHex: "#4DABF7"))
        windowState.isExpanded = true
        windowState.isExpanded = false

        XCTAssertEqual(state.completionEffect.generation, generation)
        XCTAssertTrue(state.completionEffect.isActive)
        scheduler.advance(by: 2.5)
        XCTAssertEqual(state.completionEffect.opacity, 0.25)
        scheduler.advance(by: 0.5)
        XCTAssertFalse(state.completionEffect.isActive)
    }

    @MainActor
    func testCompletionSchedulingIsCancelledWhenStateDeinitializes() {
        let scheduler = ManualNotchCompletionScheduler()
        weak var weakState: NotchTimerState?
        autoreleasepool {
            var state: NotchTimerState? = NotchTimerState(scheduleCompletionPhase: scheduler.schedule)
            state?.triggerCompletionEffect()
            weakState = state
            state = nil
        }

        XCTAssertNil(weakState)
        XCTAssertEqual(scheduler.entries.count, 6)
        XCTAssertTrue(scheduler.entries.allSatisfy(\.token.isCancelled))
    }

    func testNotchSnapshotSeparatesCountdownCountUpAndIdleAccessibilityStatus() {
        let countdown = NotchTimerSnapshot(
            activity: .determinateCountdown(progress: 0.4),
            categoryColorHex: "#FFA94D"
        )
        let countUp = NotchTimerSnapshot(activity: .activeCountUp, categoryColorHex: "#51CF66")
        let idle = NotchTimerSnapshot()

        XCTAssertEqual(countdown.activity, .determinateCountdown(progress: 0.4))
        XCTAssertEqual(countdown.accessibilityStatus, "Countdown running")
        XCTAssertEqual(countUp.activity, .activeCountUp)
        XCTAssertEqual(countUp.accessibilityStatus, "Count Up running")
        XCTAssertEqual(idle.activity, .idle)
        XCTAssertEqual(idle.accessibilityStatus, "Idle")
        XCTAssertEqual(
            NotchTimerSnapshot(isRunning: true, progress: 0, categoryColorHex: "#4DABF7", mode: .countUp).activity,
            .activeCountUp
        )
    }

    func testCountUpBreathingUsesExactFullCycleAndStaticReduceMotionEndpoint() {
        XCTAssertEqual(
            NotchCountUpBreathing.presentation(elapsed: 0, reduceMotion: false),
            .init(scale: 0.94, opacity: 0.72)
        )
        XCTAssertEqual(
            NotchCountUpBreathing.presentation(elapsed: 0.8, reduceMotion: false),
            .init(scale: 1.04, opacity: 1.0)
        )
        XCTAssertEqual(
            NotchCountUpBreathing.presentation(elapsed: 1.6, reduceMotion: false),
            .init(scale: 0.94, opacity: 0.72)
        )
        XCTAssertEqual(
            NotchCountUpBreathing.presentation(elapsed: 12.3, reduceMotion: true),
            .init(scale: 1.0, opacity: 1.0)
        )
    }

    func testInsetNotchShapePreservesOuterPathAndMovesStrokeBorderInside() {
        let bounds = CGRect(x: 0, y: 0, width: 228, height: 53)
        let shape = NotchShape(topCornerRadius: 10, bottomCornerRadius: 14)

        XCTAssertEqual(shape.path(in: bounds).boundingRect, bounds)
        XCTAssertEqual(shape.inset(by: 1).path(in: bounds).boundingRect, bounds.insetBy(dx: 1, dy: 1))
    }

    private func assertCompletionEffectProjectsExactEndpointsAndMidPhaseFromAbsoluteElapsedTime() {
        let start = Date(timeIntervalSinceReferenceDate: 10_000)
        let effect = NotchCompletionEffect(generation: 1, opacity: 1, startedAt: start)
        let endpoints: [(TimeInterval, Double)] = [
            (0, 1), (0.5, 0.25), (1, 1), (1.5, 0.25),
            (2, 1), (2.5, 0.25), (3, 0)
        ]

        for (elapsed, expected) in endpoints {
            XCTAssertEqual(
                effect.renderedOpacity(at: start.addingTimeInterval(elapsed), reduceMotion: false),
                expected,
                accuracy: 0.000_001,
                "Completion opacity at t=\(elapsed) must be an absolute phase endpoint."
            )
        }
        XCTAssertEqual(
            effect.renderedOpacity(at: start.addingTimeInterval(0.25), reduceMotion: false),
            0.625,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            effect.renderedOpacity(at: start.addingTimeInterval(2.75), reduceMotion: true),
            1,
            accuracy: 0.000_001
        )
    }

    @MainActor
    private func assertNativeCompletionRendererUsesAbsoluteEndpointAndMidPhaseAcrossRootReconstruction() throws {
        NSApplication.shared.finishLaunching()
        let renderReference = Date()
        let scheduler = ManualNotchCompletionScheduler()
        let timerState = NotchTimerState(
            scheduleCompletionPhase: scheduler.schedule,
            now: { renderReference.addingTimeInterval(-0.5) }
        )
        timerState.triggerCompletionEffect()
        let size = CGSize(width: NotchGeometry.expandedPanelWidth, height: 80)

        func renderRoot() throws -> (opacity: Float, expectedOpacity: Double, animationKeys: [String], maximumRed: CGFloat) {
            let root = AnyView(
                NotchView(
                    windowState: NotchWindowState(),
                    timerState: timerState,
                    notchSize: CGSize(width: 220, height: 37),
                    expandedContent: AnyView(EmptyView()),
                    onQuit: {},
                    reduceMotionOverride: false
                )
                .frame(width: size.width, height: size.height)
            )
            let host = NSHostingView(rootView: root)
            host.frame = CGRect(origin: .zero, size: size)
            let window = NSPanel(
                contentRect: host.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.animationBehavior = .none
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = host
            window.orderFrontRegardless()
            defer {
                window.contentView = nil
                window.close()
            }
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()

            func borderView(in view: NSView) -> NSView? {
                if String(describing: type(of: view)) == "CompletionBorderLayerView" { return view }
                return view.subviews.lazy.compactMap(borderView(in:)).first
            }
            let nativeBorder = try XCTUnwrap(borderView(in: host))
            let stroke = try XCTUnwrap(nativeBorder.layer?.sublayers?.first)
            let expectedOpacity = timerState.completionEffect.renderedOpacity(
                at: Date(),
                reduceMotion: false
            )
            let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: image)
            var maximumRed: CGFloat = 0
            for y in 0..<image.pixelsHigh {
                for x in 0..<image.pixelsWide {
                    guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                          color.redComponent > color.greenComponent * 2,
                          color.redComponent > color.blueComponent * 2 else { continue }
                    maximumRed = max(maximumRed, color.redComponent * color.alphaComponent)
                }
            }
            return (stroke.opacity, expectedOpacity, stroke.animationKeys() ?? [], maximumRed)
        }

        let endpoint = try renderRoot()
        XCTAssertEqual(Double(endpoint.opacity), endpoint.expectedOpacity, accuracy: 0.03)
        XCTAssertEqual(endpoint.opacity, 0.25, accuracy: 0.03)
        XCTAssertTrue(endpoint.animationKeys.isEmpty, "Absolute opacity must not receive a second CA interpolation.")
        XCTAssertEqual(endpoint.maximumRed, 0.25, accuracy: 0.06)

        let reconstructedEndpoint = try renderRoot()
        XCTAssertEqual(
            Double(reconstructedEndpoint.opacity),
            reconstructedEndpoint.expectedOpacity,
            accuracy: 0.03,
            "A newly constructed root must immediately reconstruct its current absolute phase."
        )

        let midReference = Date()
        let midState = NotchTimerState(
            scheduleCompletionPhase: scheduler.schedule,
            now: { midReference.addingTimeInterval(-0.25) }
        )
        midState.triggerCompletionEffect()
        let midRoot = AnyView(
            NotchView(
                windowState: NotchWindowState(),
                timerState: midState,
                notchSize: CGSize(width: 220, height: 37),
                expandedContent: AnyView(EmptyView()),
                onQuit: {},
                reduceMotionOverride: false
            )
            .frame(width: size.width, height: size.height)
        )
        let midHost = NSHostingView(rootView: midRoot)
        midHost.frame = CGRect(origin: .zero, size: size)
        let midWindow = NSPanel(contentRect: midHost.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        midWindow.animationBehavior = .none
        midWindow.contentView = midHost
        midWindow.orderFrontRegardless()
        defer { midWindow.close() }
        midHost.layoutSubtreeIfNeeded()
        midHost.displayIfNeeded()
        func midBorder(in view: NSView) -> NSView? {
            if String(describing: type(of: view)) == "CompletionBorderLayerView" { return view }
            return view.subviews.lazy.compactMap(midBorder(in:)).first
        }
        let midStroke = try XCTUnwrap(try XCTUnwrap(midBorder(in: midHost)).layer?.sublayers?.first)
        XCTAssertEqual(midStroke.opacity, 0.625, accuracy: 0.03)
        XCTAssertTrue((midStroke.animationKeys() ?? []).isEmpty)
    }

    @MainActor
    private func assertDecorativeCompletionRendererIsNeverAnAccessibilityElementAcrossRepeatedHosts() throws {
        NSApplication.shared.finishLaunching()
        for _ in 0..<12 {
            try autoreleasepool {
                let scheduler = ManualNotchCompletionScheduler()
                let timerState = NotchTimerState(scheduleCompletionPhase: scheduler.schedule)
                timerState.triggerCompletionEffect()
                let host = NSHostingView(rootView: NotchView(
                    windowState: NotchWindowState(),
                    timerState: timerState,
                    notchSize: CGSize(width: 220, height: 37),
                    expandedContent: AnyView(EmptyView()),
                    onQuit: {},
                    reduceMotionOverride: true
                ).frame(width: 816, height: 80))
                host.frame = CGRect(x: 0, y: 0, width: 816, height: 80)
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                @MainActor func borderView(in view: NSView) -> NSView? {
                    if String(describing: type(of: view)) == "CompletionBorderLayerView" { return view }
                    return view.subviews.lazy.compactMap(borderView(in:)).first
                }
                let nativeBorder = try XCTUnwrap(borderView(in: host))
                XCTAssertFalse(
                    nativeBorder.isAccessibilityElement(),
                    "The decorative native completion overlay must be deterministically absent from AX."
                )
            }
        }
    }

    @MainActor
    func testAutomaticFinishRendersThreeSemanticRedPeaksThenClearsInTheRealNonactivatingPanel() async throws {
        NSApplication.shared.finishLaunching()
        let container = NSPersistentContainer(
            name: "NotchCompletionRaster",
            managedObjectModel: CoreDataStack.model
        )
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        let timerState = NotchTimerState()
        let engine = TimerEngine(
            tickerFactory: { _ in TestTimerEngineTicker() },
            soundPlayer: {}
        )
        engine.mode = .duration
        engine.durationSeconds = 1
        engine.reset()
        let viewModel = TimerViewModel(
            engine: engine,
            context: container.viewContext,
            now: Date.init,
            save: { context in if context.hasChanges { try context.save() } }
        )
        let controller = FloatingPanelController(
            timerVM: viewModel,
            timerState: timerState,
            context: container.viewContext,
            now: Date.init,
            writeDailyLog: { _, _, _ in }
        )
        let existingWindows = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        controller.setup()
        let window = try XCTUnwrap(
            NSApplication.shared.windows.first {
                $0 is NotchWindow && !existingWindows.contains(ObjectIdentifier($0))
            }
        )
        defer {
            window.contentView = nil
            window.close()
        }
        let host = try XCTUnwrap(window.contentView)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        func semanticRedPixelCount() -> Int {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let shellRect = CGRect(
                x: host.bounds.minX,
                y: host.bounds.minY,
                width: host.bounds.width,
                height: 80
            )
            guard let image = host.bitmapImageRepForCachingDisplay(in: shellRect) else { return -1 }
            host.cacheDisplay(in: shellRect, to: image)
            return (0..<image.pixelsHigh).reduce(into: 0) { count, y in
                for x in 0..<image.pixelsWide {
                    guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    if color.alphaComponent > 0.2,
                       color.redComponent > 0.6,
                       color.redComponent > color.greenComponent * 2,
                       color.redComponent > color.blueComponent * 2 {
                        count += 1
                    }
                }
            }
        }

        let peaksRendered = expectation(description: "three completion peaks rendered")
        peaksRendered.expectedFulfillmentCount = 3
        let expiryRendered = expectation(description: "completion border cleared after expiry")
        var peakPixelCounts: [Int] = []
        var expiredPixelCount: Int?
        let renderObservation = timerState.$completionEffect
            .filter { $0.generation > 0 && ($0.opacity == 1 || !$0.isActive) }
            .sink { effect in
                DispatchQueue.main.async {
                    if effect.isActive {
                        peakPixelCounts.append(semanticRedPixelCount())
                        peaksRendered.fulfill()
                    } else {
                        (window as? NotchWindow)?.refreshPresentedContent()
                        DispatchQueue.main.async {
                            expiredPixelCount = semanticRedPixelCount()
                            expiryRendered.fulfill()
                        }
                    }
                }
            }

        viewModel.start()
        engine.finish()
        await fulfillment(of: [peaksRendered, expiryRendered], timeout: 5)
        withExtendedLifetime(renderObservation) {}

        XCTAssertEqual(peakPixelCounts.count, 3)
        XCTAssertTrue(
            peakPixelCounts.allSatisfy { $0 > 0 },
            "Automatic finish published three peaks, but rendered semantic-red pixel counts were \(peakPixelCounts)."
        )
        XCTAssertEqual(
            expiredPixelCount,
            0,
            "The semantic-red completion border remained visible after the 3.0-second expiry."
        )
    }

    @MainActor
    func testReduceMotionKeepsNativeCompletionBorderSolidUntilExpiryWithoutCAAnimation() throws {
        try assertNativeCompletionRendererUsesAbsoluteEndpointAndMidPhaseAcrossRootReconstruction()
        try assertDecorativeCompletionRendererIsNeverAnAccessibilityElementAcrossRepeatedHosts()
        NSApplication.shared.finishLaunching()
        let scheduler = ManualNotchCompletionScheduler()
        let timerState = NotchTimerState(scheduleCompletionPhase: scheduler.schedule)
        let windowState = NotchWindowState()
        timerState.triggerCompletionEffect()

        let size = CGSize(
            width: NotchGeometry.expandedPanelWidth,
            height: NotchGeometry.expandedPanelHeight + NotchGeometry.shadowPadding
        )
        func rootView() -> AnyView {
            AnyView(
                NotchView(
                    windowState: windowState,
                    timerState: timerState,
                    notchSize: CGSize(width: 220, height: 37),
                    expandedContent: AnyView(EmptyView()),
                    onQuit: {},
                    reduceMotionOverride: true
                )
                .frame(width: size.width, height: size.height)
            )
        }
        let host = NSHostingView(rootView: rootView())
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSPanel(
            contentRect: host.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        window.orderFrontRegardless()
        defer {
            window.contentView = nil
            window.close()
        }

        func semanticRedPixelCount() -> Int {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let shellRect = CGRect(
                x: host.bounds.minX,
                y: host.bounds.minY,
                width: host.bounds.width,
                height: 80
            )
            guard let image = host.bitmapImageRepForCachingDisplay(in: shellRect) else { return -1 }
            host.cacheDisplay(in: shellRect, to: image)
            return (0..<image.pixelsHigh).reduce(into: 0) { count, y in
                for x in 0..<image.pixelsWide {
                    guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    if color.alphaComponent > 0.2,
                       color.redComponent > 0.6,
                       color.redComponent > color.greenComponent * 2,
                       color.redComponent > color.blueComponent * 2 {
                        count += 1
                    }
                }
            }
        }
        func completionBorderLayerView(in view: NSView) -> NSView? {
            if String(describing: type(of: view)) == "CompletionBorderLayerView" {
                return view
            }
            return view.subviews.lazy.compactMap(completionBorderLayerView(in:)).first
        }
        func renderCurrentState() -> (pixels: Int, borderView: NSView?, animationKeys: [String]) {
            host.rootView = rootView()
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let borderView = completionBorderLayerView(in: host)
            let animationKeys = borderView?.layer?.sublayers?.first?.animationKeys() ?? []
            return (semanticRedPixelCount(), borderView, animationKeys)
        }

        let activation = renderCurrentState()
        XCTAssertGreaterThan(activation.pixels, 0)
        XCTAssertNotNil(activation.borderView)
        XCTAssertTrue(activation.animationKeys.isEmpty)

        scheduler.advance(by: 0.5)
        let trough = renderCurrentState()
        XCTAssertTrue(trough.borderView === activation.borderView)
        XCTAssertEqual(
            trough.pixels,
            activation.pixels,
            "Reduce Motion must keep the active native border solid instead of rendering the 0.25 pulse trough."
        )
        XCTAssertTrue(trough.animationKeys.isEmpty)

        scheduler.advance(by: 2.5)
        let expiry = renderCurrentState()
        XCTAssertNil(expiry.borderView, "The native completion renderer must be removed at t=3.0.")
        XCTAssertEqual(expiry.pixels, 0)
        XCTAssertTrue(expiry.animationKeys.isEmpty)
    }

    @MainActor
    func testControllerPublishesAtomicIdleSnapshotBeforeCompletionEffect() throws {
        let container = NSPersistentContainer(name: "NotchCompletionController", managedObjectModel: CoreDataStack.model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        let scheduler = ManualNotchCompletionScheduler()
        let timerState = NotchTimerState(scheduleCompletionPhase: scheduler.schedule)
        let engine = TimerEngine(tickerFactory: { _ in TestTimerEngineTicker() }, soundPlayer: {})
        let vm = TimerViewModel(
            engine: engine,
            context: container.viewContext,
            now: Date.init,
            save: { context in if context.hasChanges { try context.save() } }
        )
        engine.mode = .duration
        engine.durationSeconds = 1
        engine.reset()
        let controller = FloatingPanelController(
            timerVM: vm,
            timerState: timerState,
            context: container.viewContext,
            now: Date.init,
            writeDailyLog: { _, _, _ in }
        )
        controller.configureTimerMonitoring()
        vm.start()
        XCTAssertEqual(timerState.snapshot.activity, .determinateCountdown(progress: 0))

        var snapshotAtActivation: NotchTimerSnapshot?
        let activationObservation = timerState.$completionEffect
            .dropFirst()
            .filter(\.isActive)
            .sink { _ in snapshotAtActivation = timerState.snapshot }
        engine.finish()

        XCTAssertEqual(snapshotAtActivation?.activity, .idle)
        XCTAssertEqual(timerState.snapshot.activity, .idle)
        XCTAssertTrue(timerState.completionEffect.isActive)
        XCTAssertEqual(timerState.completionEffect.opacity, 1.0)
        let generation = timerState.completionEffect.generation
        engine.mode = .countUp
        vm.selectedCategory = nil
        XCTAssertEqual(timerState.completionEffect.generation, generation)
        withExtendedLifetime(activationObservation) {}
    }

    func testAnchorMidXPrefersHardwareNotchGap() {
        let result = NotchGeometry.anchorMidX(
            leftAuxMaxX: 702,
            rightAuxMinX: 810,
            safeAreaMidX: 760,
            screenMidX: 756
        )

        XCTAssertEqual(result, 756, accuracy: 0.001)
    }

    func testIdleShellWidthExpandsWhenTimerIndicatorIsVisible() {
        let widthWithoutIndicator = NotchGeometry.idleShellWidth(notchWidth: 184, showsProgress: false)
        let widthWithIndicator = NotchGeometry.idleShellWidth(notchWidth: 184, showsProgress: true)

        XCTAssertGreaterThan(widthWithIndicator, widthWithoutIndicator)
        XCTAssertEqual(widthWithoutIndicator, 184, accuracy: 0.001)
        XCTAssertEqual(widthWithIndicator, 228, accuracy: 0.001)
    }

    func testCollapsedHitRectEndsAtPaintedShellAndCentersTheOptionalRunningRail() {
        let bounds = CGRect(
            x: 0,
            y: 0,
            width: NotchGeometry.expandedPanelWidth,
            height: NotchGeometry.expandedPanelHeight + NotchGeometry.shadowPadding
        )
        let stoppedRect = NotchGeometry.hitRect(
            bounds: bounds,
            isExpanded: false,
            notchWidth: 184,
            notchHeight: 32,
            showsProgress: false
        )
        let runningRect = NotchGeometry.hitRect(
            bounds: bounds,
            isExpanded: false,
            notchWidth: 184,
            notchHeight: 32,
            showsProgress: true
        )

        XCTAssertEqual(stoppedRect, CGRect(x: 316, y: 0, width: 184, height: 33))
        XCTAssertEqual(runningRect, CGRect(x: 316, y: 0, width: 228, height: 33))
        XCTAssertEqual(runningRect.height, NotchGeometry.idleShellHeight(notchHeight: 32))
        XCTAssertFalse(runningRect.contains(CGPoint(x: runningRect.midX, y: runningRect.maxY + 1)))
        XCTAssertTrue(runningRect.contains(CGPoint(x: runningRect.midX, y: runningRect.maxY - 1)))
    }

    func testCollapsedClosedShapeContainmentMatchesVisiblePathAtBottomAndCorners() {
        let windowFrame = CGRect(x: 552, y: 839, width: 816, height: 404)
        let localRect = NotchGeometry.hitRect(
            bounds: CGRect(origin: .zero, size: windowFrame.size),
            isExpanded: false,
            notchWidth: 184,
            notchHeight: 32,
            showsProgress: false
        )
        let visiblePath = NotchShape(
            topCornerRadius: NotchGeometry.cornerRadiusClosed.top,
            bottomCornerRadius: NotchGeometry.cornerRadiusClosed.bottom
        ).path(in: localRect)
        let localPoints: [(String, CGPoint)] = [
            ("one pixel inside bottom", CGPoint(x: localRect.midX, y: localRect.maxY - 1)),
            ("one pixel outside bottom", CGPoint(x: localRect.midX, y: localRect.maxY + 1)),
            ("transparent top-left", CGPoint(x: localRect.minX + 1, y: localRect.minY + 7)),
            ("inside top-left", CGPoint(x: localRect.minX + 7, y: localRect.minY + 7)),
            ("transparent top-right", CGPoint(x: localRect.maxX - 1, y: localRect.minY + 7)),
            ("inside top-right", CGPoint(x: localRect.maxX - 7, y: localRect.minY + 7)),
            ("transparent bottom-left", CGPoint(x: localRect.minX + 1, y: localRect.maxY - 1)),
            ("inside bottom-left", CGPoint(x: localRect.minX + 21, y: localRect.maxY - 1)),
            ("transparent bottom-right", CGPoint(x: localRect.maxX - 1, y: localRect.maxY - 1)),
            ("inside bottom-right", CGPoint(x: localRect.maxX - 21, y: localRect.maxY - 1))
        ]

        for (name, localPoint) in localPoints {
            let screenPoint = CGPoint(
                x: windowFrame.minX + localPoint.x,
                y: windowFrame.maxY - localPoint.y
            )
            XCTAssertEqual(
                NotchGeometry.containsScreenPoint(
                    screenPoint,
                    windowFrame: windowFrame,
                    localRect: localRect
                ),
                visiblePath.contains(localPoint),
                name
            )
        }
    }

    func testExpandedHitRectMatchesExpandedShellBounds() {
        let bounds = CGRect(
            x: 0,
            y: 0,
            width: NotchGeometry.expandedPanelWidth,
            height: NotchGeometry.expandedPanelHeight + NotchGeometry.shadowPadding
        )
        let rect = NotchGeometry.hitRect(
            bounds: bounds,
            isExpanded: true,
            notchWidth: 184,
            notchHeight: 32,
            showsProgress: false
        )

        XCTAssertEqual(rect.width, NotchGeometry.expandedPanelWidth, accuracy: 0.001)
        XCTAssertEqual(rect.height, NotchGeometry.expandedPanelHeight + NotchGeometry.shadowPadding, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 0, accuracy: 0.001)
    }

    func testScreenPointBelowHardwareNotchRemainsInsideHoverHitRegion() {
        let windowFrame = CGRect(x: 552, y: 839, width: 816, height: 404)
        let hitRect = NotchGeometry.hitRect(
            bounds: CGRect(origin: .zero, size: windowFrame.size),
            isExpanded: false,
            notchWidth: 220,
            notchHeight: 37,
            showsProgress: false
        )

        XCTAssertTrue(NotchGeometry.containsScreenPoint(
            CGPoint(x: 960, y: 1_206),
            windowFrame: windowFrame,
            localRect: hitRect
        ))
        XCTAssertFalse(NotchGeometry.containsScreenPoint(
            CGPoint(x: 960, y: 1_000),
            windowFrame: windowFrame,
            localRect: hitRect
        ))
    }

    func testCollapsedGlobalPointerUsesClosedShapeAndOptionalRunningRail() {
        let windowFrame = CGRect(x: 552, y: 839, width: 816, height: 404)
        let bounds = CGRect(origin: .zero, size: windowFrame.size)
        let stoppedRect = NotchGeometry.hitRect(
            bounds: bounds,
            isExpanded: false,
            notchWidth: 220,
            notchHeight: 37,
            showsProgress: false
        )
        let runningRect = NotchGeometry.hitRect(
            bounds: bounds,
            isExpanded: false,
            notchWidth: 220,
            notchHeight: 37,
            showsProgress: true
        )
        let stoppedShellMaxX = stoppedRect.maxX
        let railPoint = CGPoint(x: windowFrame.minX + stoppedShellMaxX + 20, y: windowFrame.maxY - 20)
        let transparentCorner = CGPoint(
            x: windowFrame.minX + runningRect.minX + 1,
            y: windowFrame.maxY - (runningRect.maxY - 1)
        )

        XCTAssertTrue(NotchGlobalHover.shouldExpand(
            isExpanded: false,
            point: CGPoint(x: 960, y: 1_223),
            windowFrame: windowFrame,
            localRect: stoppedRect
        ))
        XCTAssertFalse(NotchGlobalHover.shouldExpand(
            isExpanded: false,
            point: transparentCorner,
            windowFrame: windowFrame,
            localRect: runningRect
        ))
        XCTAssertFalse(NotchGlobalHover.shouldExpand(
            isExpanded: false,
            point: railPoint,
            windowFrame: windowFrame,
            localRect: stoppedRect
        ))
        XCTAssertTrue(NotchGlobalHover.shouldExpand(
            isExpanded: false,
            point: railPoint,
            windowFrame: windowFrame,
            localRect: runningRect
        ))
        XCTAssertFalse(NotchGlobalHover.shouldExpand(
            isExpanded: true,
            point: CGPoint(x: 960, y: 1_203),
            windowFrame: windowFrame,
            localRect: stoppedRect
        ))
    }

    @MainActor
    func testHostingViewTracksCollapsedNativeHoverRegion() throws {
        let state = NotchWindowState()
        let timerState = NotchTimerState()
        let view = PassthroughHostingView(rootView: EmptyView())
        view.windowState = state
        view.timerState = timerState
        view.notchSize = CGSize(width: 220, height: 37)
        view.frame = CGRect(x: 0, y: 0, width: 816, height: 404)

        view.updateTrackingAreas()

        let area = try XCTUnwrap(view.trackingAreas.first {
            ($0.owner as AnyObject?) === view && $0.options.contains(.mouseEnteredAndExited)
        })
        XCTAssertEqual(area.rect, view.hoverHitRect)
        XCTAssertTrue(area.options.contains(.activeAlways))
        XCTAssertTrue(area.options.contains(.mouseMoved))
        XCTAssertEqual(area.rect.maxY, NotchGeometry.idleShellHeight(notchHeight: 37))
    }

    @MainActor
    func testCollapsedHostingViewRejectsTransparentCornersAndReevaluatesMouseMovedInsideTrackingBounds() async throws {
        NSApplication.shared.finishLaunching()
        let state = NotchWindowState()
        let timerState = NotchTimerState()
        let view = PassthroughHostingView(rootView: EmptyView())
        view.windowState = state
        view.timerState = timerState
        view.notchSize = CGSize(width: 220, height: 37)
        view.frame = CGRect(x: 0, y: 0, width: 816, height: 404)
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }

        let hitRect = view.hoverHitRect
        let transparentCorner = CGPoint(x: hitRect.minX + 1, y: hitRect.maxY - 1)
        let inside = CGPoint(x: hitRect.midX, y: hitRect.midY)
        XCTAssertNil(view.hitTest(transparentCorner))
        XCTAssertNotNil(view.hitTest(inside))

        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(CGPoint(
            x: mouse.x - inside.x,
            y: mouse.y - (window.frame.height - inside.y)
        ))
        let expanded = expectation(description: "mouse move inside exact closed shape expands")
        let observation = state.$isExpanded
            .dropFirst()
            .filter { $0 }
            .sink { _ in expanded.fulfill() }
        let move = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved,
            location: CGPoint(x: inside.x, y: window.frame.height - inside.y),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 0,
            pressure: 0
        ))

        view.mouseMoved(with: move)

        await fulfillment(of: [expanded], timeout: 1)
        withExtendedLifetime(observation) {}
    }

    func testWindowFrameStaysTopAlignedToScreen() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let frame = NotchGeometry.windowFrame(screenFrame: screenFrame, anchorMidX: 756)

        XCTAssertEqual(frame.midX, 756, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, screenFrame.maxY, accuracy: 0.001)
        XCTAssertEqual(frame.width, NotchGeometry.expandedPanelWidth, accuracy: 0.001)
    }

    @MainActor
    func testWindowStateTracksHoverExpansion() {
        let state = NotchWindowState()

        state.isExpanded = true
        XCTAssertTrue(state.isExpanded)

        state.isExpanded = false
        XCTAssertFalse(state.isExpanded)
    }

    @MainActor
    func testHostingViewMouseExitCollapsesWhenUnlocked() throws {
        let state = NotchWindowState()
        let view = PassthroughHostingView(rootView: EmptyView())
        view.windowState = state
        state.isExpanded = true

        view.mouseExited(with: try XCTUnwrap(NSEvent.enterExitEvent(
            with: .mouseExited,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            trackingNumber: 0,
            userData: nil
        )))

        XCTAssertFalse(state.isExpanded)
    }

    @MainActor
    func testHostingViewMouseExitRespectsInteractionLock() throws {
        let state = NotchWindowState()
        let view = PassthroughHostingView(rootView: EmptyView())
        view.windowState = state
        state.isExpanded = true
        defer {
            NotificationCenter.default.post(name: .nativeSchedulerInteractionLockChanged, object: false)
        }

        let event = exitEvent()
        NotificationCenter.default.post(name: .nativeSchedulerInteractionLockChanged, object: true)
        view.mouseExited(with: event)
        XCTAssertTrue(state.isExpanded)

        NotificationCenter.default.post(name: .nativeSchedulerInteractionLockChanged, object: false)
        view.mouseExited(with: event)
        XCTAssertFalse(state.isExpanded)
    }

    @MainActor
    func testPointerExitDoesNotCollapseWhileOptionsInteractionIsActive() throws {
        let state = NotchWindowState()
        let view = PassthroughHostingView(rootView: EmptyView())
        view.windowState = state
        state.isExpanded = true

        let event = exitEvent()

        state.beginShellMenuInteraction()
        view.mouseExited(with: event)
        XCTAssertTrue(state.isExpanded)

        state.endShellMenuInteraction()
        view.mouseExited(with: event)
        XCTAssertFalse(state.isExpanded)
    }

    @MainActor
    func testShellMenuCloseCannotUnlockSettingsInteraction() {
        let state = NotchWindowState()

        NotificationCenter.default.post(name: .nativeSchedulerInteractionLockChanged, object: true)
        state.beginShellMenuInteraction()
        state.endShellMenuInteraction()

        let view = PassthroughHostingView(rootView: EmptyView())
        view.windowState = state
        state.isExpanded = true
        view.mouseExited(with: exitEvent())
        XCTAssertTrue(state.isExpanded)
        NotificationCenter.default.post(name: .nativeSchedulerInteractionLockChanged, object: false)
    }

    @MainActor
    func testDuplicateShellMenuCallbacksRecoverWithoutClearingSettingsLock() {
        let state = NotchWindowState()
        let view = PassthroughHostingView(rootView: EmptyView())
        view.windowState = state
        state.isExpanded = true
        let event = exitEvent()

        state.beginShellMenuInteraction()
        state.beginShellMenuInteraction()
        state.endShellMenuInteraction()
        view.mouseExited(with: event)
        XCTAssertFalse(state.isExpanded)

        NotificationCenter.default.post(name: .nativeSchedulerInteractionLockChanged, object: true)
        state.beginShellMenuInteraction()
        state.endShellMenuInteraction()
        state.isExpanded = true
        view.mouseExited(with: event)
        XCTAssertTrue(state.isExpanded)
        NotificationCenter.default.post(name: .nativeSchedulerInteractionLockChanged, object: false)
    }

    @MainActor
    func testShellMenuButtonExposesAppKitActivationAndGearSymbolConfiguration() {
        let coordinator = ShellMenuButton.Coordinator(windowState: NotchWindowState(), onQuit: {})
        let button = ShellMenuButton.configureButton(ShellMenuNativeButton(), coordinator: coordinator)
        XCTAssertEqual(button.accessibilityRole(), .button)
        XCTAssertEqual(button.accessibilityLabel(), "Shell menu")
        XCTAssertEqual(button.contentTintColor, NSColor(Color.nsTextSecondary))
        XCTAssertEqual(button.accessibilityHelp(), "Open options menu")
        XCTAssertEqual(button.intrinsicContentSize, NSSize(width: 24, height: 24))
        XCTAssertNotNil(button.action)
        XCTAssertNotNil(button.target)
        withExtendedLifetime(coordinator) {}

        let image = ShellMenuButton.makeGearImage()
        XCTAssertEqual(image.symbolConfiguration, .init(pointSize: 11, weight: .semibold))
    }

    func testShellMenuCenterAlignsWithMainPanelDateHeaderAcrossNotchHeights() {
        for notchHeight in [CGFloat(32), 37, 42] {
            let expandedContentTop = notchHeight + NotchGeometry.expandedContentTopSpacing
            let mainPanelHeight = NotchGeometry.expandedPanelHeight
                - expandedContentTop
                - NotchGeometry.expandedContentBottomSpacing
            let mainPanelHeaderHeight = max(28, min(36, mainPanelHeight * 0.09))
            let dateHeaderCenterY = expandedContentTop + (mainPanelHeaderHeight / 2)
            let menuCenterY = NotchGeometry.shellMenuTopOffset(notchHeight: notchHeight)
                + (NotchGeometry.shellMenuButtonSize / 2)

            XCTAssertEqual(menuCenterY, dateHeaderCenterY, accuracy: 0.5)
        }
    }

    @MainActor
    func testTaskInputReturnSynchronizesLatestTextBeforeImmediateSubmit() async {
        var boundText = ""
        var submittedText: String?
        let submitted = expectation(description: "Submit leaves AppKit delegate reentrancy")
        let coordinator = TodoTaskInputField.Coordinator(
            text: Binding(
                get: { boundText },
                set: { boundText = $0 }
            ),
            isFocused: .constant(true),
            onSubmit: { title in
                submittedText = title
                submitted.fulfill()
            }
        )
        let field = NSTextField()
        field.stringValue = "Ship immediately"

        coordinator.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: field)
        )
        let handled = coordinator.control(
            field,
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(boundText, "")
        XCTAssertEqual(field.stringValue, "")
        XCTAssertNil(submittedText)

        await fulfillment(of: [submitted], timeout: 1)

        XCTAssertEqual(submittedText, "Ship immediately")
    }

    @MainActor
    private func runIsolatedHostedTodoTestIfNeeded(
        environmentKey: String,
        testName: String
    ) throws -> Bool {
        guard ProcessInfo.processInfo.environment[environmentKey] != "1" else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["-XCTest", testName, Bundle(for: NotchShellTests.self).bundlePath]
        var environment = ProcessInfo.processInfo.environment
        environment[environmentKey] = "1"
        process.environment = environment
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        let terminated = expectation(description: "isolated hosted todo test exits")
        process.terminationHandler = { _ in terminated.fulfill() }
        try process.run()
        wait(for: [terminated], timeout: 30)
        let transcript = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            + String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, transcript)
        return true
    }

    @MainActor
    func testNativeTodoSendButtonClickAndReturnEachSubmitExactlyOnce() async throws {
        if try runIsolatedHostedTodoTestIfNeeded(
            environmentKey: "NATIVE_SCHEDULER_TODO_SUBMIT_CHILD",
            testName: "NativeSchedulerTests.NotchShellTests/testNativeTodoSendButtonClickAndReturnEachSubmitExactlyOnce"
        ) { return }
        var clickCount = 0
        let send = TodoSubmitButton(isEnabled: true) { clickCount += 1 }
        let host = NSHostingView(rootView: send.frame(width: 44, height: 44))
        host.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()

        let button = try XCTUnwrap(
            nativeButton(withAccessibilityIdentifier: "todo.submit", in: host) as? TodoPointingHandButton
        )
        button.performClick(nil)
        XCTAssertEqual(clickCount, 1)
        XCTAssertEqual(button.cursorForInteraction, NSCursor.pointingHand)

        var returnCount = 0
        let submitted = expectation(description: "Return submit")
        let coordinator = TodoTaskInputField.Coordinator(
            text: .constant("Return task"),
            isFocused: .constant(true),
            onSubmit: { _ in
                returnCount += 1
                submitted.fulfill()
            }
        )
        let field = NSTextField()
        field.stringValue = "Return task"
        XCTAssertTrue(coordinator.control(field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
        await fulfillment(of: [submitted], timeout: 1)
        XCTAssertEqual(returnCount, 1)
        window.contentView = nil
        window.close()
    }

    @MainActor
    func testCondensedTaskDensityReclaimsTrashAndFolderCountWidth() throws {
        XCTAssertTrue(TodoListDensity.normal.showsMoveHandles)
        XCTAssertTrue(TodoListDensity.condensed.showsMoveHandles)

        let childKey = "NATIVE_SCHEDULER_TODO_DENSITY_AX_CHILD"
        if ProcessInfo.processInfo.environment[childKey] != "1" {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = [
                "-XCTest",
                "NativeSchedulerTests.NotchShellTests/testCondensedTaskDensityReclaimsTrashAndFolderCountWidth",
                Bundle(for: NotchShellTests.self).bundlePath
            ]
            var environment = ProcessInfo.processInfo.environment
            environment[childKey] = "1"
            process.environment = environment
            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error
            let terminated = expectation(description: "isolated todo density host exits")
            process.terminationHandler = { _ in terminated.fulfill() }
            try process.run()
            wait(for: [terminated], timeout: 30)
            let transcript = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                + String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            XCTAssertEqual(process.terminationStatus, 0, transcript)
            return
        }

        NSApplication.shared.finishLaunching()
        NSApplication.shared.activate(ignoringOtherApps: true)
        let container = NSPersistentContainer(name: "TodoDensity", managedObjectModel: CoreDataStack.model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, _ in }
        let section = TodoSectionEntity.create(title: "A long folder title", isCompletedSection: false, sortOrder: 0, in: container.viewContext)
        let item = TodoEntity.create(title: "A task title that needs every available point", priority: 0, section: section, in: container.viewContext)

        func host(density: TodoListDensity, identifier: String) -> (NSHostingView<AnyView>, NSWindow) {
            let root = AnyView(VStack {
                TodoSectionHeaderView(
                    section: section, itemCount: 12, isEditing: false, isDropTarget: false,
                    showsMoveHandle: density.showsMoveHandles,
                    isDragActive: false,
                    editingTitle: .constant(""),
                    showsItemCount: density == .normal, onDragProvider: nil,
                    onToggle: {}, onCommitTitle: {}, onEdit: {}, onDelete: {}
                )
                TodoRowView(
                    item: item,
                    showsMoveHandle: density.showsMoveHandles,
                    isNested: false,
                    isDragActive: false,
                    showsDeleteControl: density == .normal,
                    onDragChanged: nil,
                    onDragEnded: nil,
                    onToggle: {}, onDelete: {}
                )
            }.frame(width: 130, height: 90))
            let host = NSHostingView(rootView: root)
            host.frame = CGRect(x: 0, y: 0, width: 130, height: 90)
            let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.animationBehavior = .none
            window.isReleasedWhenClosed = false
            window.title = identifier
            window.setAccessibilityIdentifier(identifier)
            window.contentView = host
            window.orderFrontRegardless()
            XCTAssertTrue(window.isVisible)
            host.layoutSubtreeIfNeeded()
            return (host, window)
        }

        let normal = host(density: .normal, identifier: "todo-density-normal")
        let condensed = host(density: .condensed, identifier: "todo-density-condensed")
        let normalNodes = try Self.nativeAccessibilityNodes(processID: getpid(), windowIdentifier: "todo-density-normal")
        let condensedNodes = try Self.nativeAccessibilityNodes(processID: getpid(), windowIdentifier: "todo-density-condensed")
        let titleID = "todo.task.title.\(item.id.uuidString)"
        let folderTitleID = "todo.folder.title.\(section.id.uuidString)"
        XCTAssertEqual(
            try XCTUnwrap(condensedNodes.first { $0.identifier == titleID }).frame.minX,
            try XCTUnwrap(normalNodes.first { $0.identifier == titleID }).frame.minX,
            accuracy: 1
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(condensedNodes.first { $0.identifier == titleID }).frame.width,
            try XCTUnwrap(normalNodes.first { $0.identifier == titleID }).frame.width
        )
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(condensedNodes.first { $0.identifier == titleID }).frame.width,
            32
        )
        XCTAssertGreaterThan(
            try XCTUnwrap(condensedNodes.first { $0.identifier == folderTitleID }).frame.width,
            try XCTUnwrap(normalNodes.first { $0.identifier == folderTitleID }).frame.width
        )
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(condensedNodes.first { $0.identifier == folderTitleID }).frame.width,
            44
        )
        let toggleFrame = try XCTUnwrap(
            condensedNodes.first {
                $0.identifier == "todo.folder.toggle.\(section.id.uuidString)"
            }
        ).frame
        XCTAssertGreaterThanOrEqual(toggleFrame.width, SchedulerControl.minimumTarget)
        XCTAssertGreaterThanOrEqual(toggleFrame.height, SchedulerControl.minimumTarget)
        XCTAssertNil(
            normalNodes.first {
                $0.identifier == "todo.folder.edit.\(section.id.uuidString)"
            }
        )
        XCTAssertNil(
            normalNodes.first {
                $0.identifier == "todo.folder.delete.\(section.id.uuidString)"
            }
        )
        XCTAssertNil(condensedNodes.first { $0.identifier == "todo.task.delete.\(item.id.uuidString)" })
        XCTAssertNil(condensedNodes.first { $0.identifier == "todo.folder.count.\(section.id.uuidString)" })

        normal.0.rootView = AnyView(EmptyView())
        condensed.0.rootView = AnyView(EmptyView())
        normal.1.contentView = nil
        condensed.1.contentView = nil
        normal.1.close()
        condensed.1.close()
    }

    @MainActor
    func testRealTodoRowHoverEnablesOnlyMatchingRedTrashAndAXPressDeletesItsRow() throws {
        if try runIsolatedHostedTodoTestIfNeeded(
            environmentKey: "NATIVE_SCHEDULER_TODO_ROW_HOVER_CHILD",
            testName: "NativeSchedulerTests.NotchShellTests/testRealTodoRowHoverEnablesOnlyMatchingRedTrashAndAXPressDeletesItsRow"
        ) { return }

        NSApplication.shared.finishLaunching()
        NSApplication.shared.activate(ignoringOtherApps: true)
        let container = NSPersistentContainer(name: "TodoRowHover", managedObjectModel: CoreDataStack.model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, _ in }
        let firstItem = TodoEntity.create(title: "Long task title should remain readable in condensed layout", priority: 0, in: container.viewContext)
        let secondItem = TodoEntity.create(title: "Sibling task", priority: 1, in: container.viewContext)
        var deleted: [UUID] = []
        let root = VStack(spacing: 0) {
            TodoRowView(item: firstItem, onToggle: {}, onDelete: { deleted.append(firstItem.id) })
                .frame(height: 48)
            TodoRowView(item: secondItem, onToggle: {}, onDelete: { deleted.append(secondItem.id) })
                .frame(height: 48)
        }
        .frame(width: 420, height: 96)
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(x: 0, y: 0, width: 420, height: 96)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.title = "todo-row-hover"
        window.setAccessibilityIdentifier("todo-row-hover")
        if let screen = NSScreen.main {
            let mouse = NSEvent.mouseLocation
            let origins = [
                CGPoint(x: screen.frame.minX + 20, y: screen.frame.minY + 20),
                CGPoint(x: screen.frame.maxX - window.frame.width - 20, y: screen.frame.minY + 20)
            ]
            let origin = origins.max { lhs, rhs in
                hypot(lhs.x - mouse.x, lhs.y - mouse.y) < hypot(rhs.x - mouse.x, rhs.y - mouse.y)
            }
            if let origin { window.setFrameOrigin(origin) }
        }
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        let firstTrash = try XCTUnwrap(nativeButton(withAccessibilityIdentifier: "todo.task.delete.\(firstItem.id.uuidString)", in: host) as? TodoPointingHandButton)
        let secondTrash = try XCTUnwrap(nativeButton(withAccessibilityIdentifier: "todo.task.delete.\(secondItem.id.uuidString)", in: host) as? TodoPointingHandButton)
        XCTAssertFalse(firstTrash.isAccessibilityEnabled())
        XCTAssertFalse(secondTrash.isAccessibilityEnabled())
        XCTAssertEqual(firstTrash.alphaValue, 0, accuracy: 0.001)

        let trackers = todoRowHoverTrackers(in: host)
        XCTAssertEqual(trackers.count, 2)
        let firstTracker = try XCTUnwrap(trackers.first {
            $0.accessibilityIdentifier() == "todo.task.hover.\(firstItem.id.uuidString)"
        })
        let secondTracker = try XCTUnwrap(trackers.first {
            $0.accessibilityIdentifier() == "todo.task.hover.\(secondItem.id.uuidString)"
        })
        let monitorOwner = try XCTUnwrap(firstTracker.monitorOwner)
        XCTAssertTrue(secondTracker.monitorOwner === monitorOwner)
        XCTAssertEqual(monitorOwner.localMonitorTokenCount, 1)
        XCTAssertEqual(monitorOwner.globalPointerSubscriptionCount, 1)
        XCTAssertEqual(monitorOwner.registeredRowCount, 2)
        XCTAssertEqual(monitorOwner.registeredTrashCount, 2)
        XCTAssertTrue(monitorOwner.trashButton(for: firstItem.id) === firstTrash)
        XCTAssertTrue(monitorOwner.trashButton(for: secondItem.id) === secondTrash)
        XCTAssertGreaterThan(firstTracker.bounds.width, 100)
        XCTAssertGreaterThan(firstTracker.bounds.height, 20)
        XCTAssertGreaterThan(secondTracker.bounds.width, 100)
        XCTAssertGreaterThan(secondTracker.bounds.height, 20)
        XCTAssertNil(firstTracker.hitTest(CGPoint(x: firstTracker.bounds.midX, y: firstTracker.bounds.midY)))

        func mouseMoved(at point: CGPoint, eventNumber: Int) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: .mouseMoved,
                location: point,
                modifierFlags: [],
                timestamp: TimeInterval(eventNumber),
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: eventNumber,
                clickCount: 0,
                pressure: 0
            ))
        }

        let firstEntered = expectation(description: "local monitor entered first row")
        let firstEnteredObservation = firstTracker.hoverState.$isHovered
            .dropFirst()
            .filter { $0 }
            .sink { _ in firstEntered.fulfill() }
        let firstPoint = firstTracker.convert(
            CGPoint(x: firstTracker.bounds.midX, y: firstTracker.bounds.midY),
            to: nil
        )
        NotificationCenter.default.post(
            name: NotchGlobalPointerEvent.notificationName,
            object: NotchGlobalPointerEvent(screenPoint: window.convertPoint(toScreen: firstPoint))
        )
        wait(for: [firstEntered], timeout: 1)
        withExtendedLifetime(firstEnteredObservation) {}

        let activeFirstTrash = try XCTUnwrap(nativeButton(withAccessibilityIdentifier: "todo.task.delete.\(firstItem.id.uuidString)", in: host) as? TodoPointingHandButton)
        let inactiveSecondTrash = try XCTUnwrap(nativeButton(withAccessibilityIdentifier: "todo.task.delete.\(secondItem.id.uuidString)", in: host) as? TodoPointingHandButton)
        XCTAssertTrue(activeFirstTrash.isEnabled)
        XCTAssertTrue(activeFirstTrash.isAccessibilityEnabled())
        XCTAssertEqual(activeFirstTrash.alphaValue, 1, accuracy: 0.001)
        XCTAssertEqual(activeFirstTrash.contentTintColor, NSColor.systemRed)
        XCTAssertFalse(inactiveSecondTrash.isAccessibilityEnabled())
        XCTAssertEqual(inactiveSecondTrash.alphaValue, 0, accuracy: 0.001)
        XCTAssertTrue(activeFirstTrash.accessibilityPerformPress())
        XCTAssertEqual(deleted, [firstItem.id])

        let firstExited = expectation(description: "local monitor exited first row")
        let firstExitedObservation = firstTracker.hoverState.$isHovered
            .dropFirst()
            .filter { !$0 }
            .sink { _ in firstExited.fulfill() }
        let secondEntered = expectation(description: "local monitor entered sibling row")
        let secondEnteredObservation = secondTracker.hoverState.$isHovered
            .dropFirst()
            .filter { $0 }
            .sink { _ in secondEntered.fulfill() }
        let secondPoint = secondTracker.convert(
            CGPoint(x: secondTracker.bounds.midX, y: secondTracker.bounds.midY),
            to: nil
        )
        let secondMove = try mouseMoved(at: secondPoint, eventNumber: 2)
        monitorOwner.handleLocalMonitorEvent(secondMove)
        wait(for: [firstExited, secondEntered], timeout: 1)
        withExtendedLifetime((firstExitedObservation, secondEnteredObservation)) {}

        let inactiveFirstTrash = try XCTUnwrap(nativeButton(withAccessibilityIdentifier: "todo.task.delete.\(firstItem.id.uuidString)", in: host) as? TodoPointingHandButton)
        let activeSecondTrash = try XCTUnwrap(nativeButton(withAccessibilityIdentifier: "todo.task.delete.\(secondItem.id.uuidString)", in: host) as? TodoPointingHandButton)
        XCTAssertFalse(inactiveFirstTrash.isAccessibilityEnabled())
        XCTAssertEqual(inactiveFirstTrash.alphaValue, 0, accuracy: 0.001)
        XCTAssertTrue(activeSecondTrash.isAccessibilityEnabled())
        XCTAssertEqual(activeSecondTrash.alphaValue, 1, accuracy: 0.001)
        XCTAssertEqual(activeSecondTrash.contentTintColor, .systemRed)
        XCTAssertTrue(activeSecondTrash.accessibilityPerformPress())
        XCTAssertEqual(deleted, [firstItem.id, secondItem.id])

        let secondExited = expectation(description: "local monitor exited all rows")
        let secondExitedObservation = secondTracker.hoverState.$isHovered
            .dropFirst()
            .filter { !$0 }
            .sink { _ in secondExited.fulfill() }
        let outsideMove = try mouseMoved(at: CGPoint(x: -1, y: -1), eventNumber: 3)
        monitorOwner.handleLocalMonitorEvent(outsideMove)
        wait(for: [secondExited], timeout: 1)
        withExtendedLifetime(secondExitedObservation) {}
        XCTAssertFalse(firstTracker.hoverState.isHovered)
        XCTAssertFalse(secondTracker.hoverState.isHovered)
        XCTAssertFalse(try XCTUnwrap(nativeButton(withAccessibilityIdentifier: "todo.task.delete.\(firstItem.id.uuidString)", in: host)).isAccessibilityEnabled())
        XCTAssertFalse(try XCTUnwrap(nativeButton(withAccessibilityIdentifier: "todo.task.delete.\(secondItem.id.uuidString)", in: host)).isAccessibilityEnabled())

        window.contentView = nil
        XCTAssertEqual(monitorOwner.localMonitorTokenCount, 0)
        XCTAssertEqual(monitorOwner.globalPointerSubscriptionCount, 0)
        XCTAssertEqual(monitorOwner.registeredRowCount, 0)
        XCTAssertEqual(monitorOwner.registeredTrashCount, 0)
        XCTAssertNil(monitorOwner.trashButton(for: firstItem.id))
        XCTAssertNil(monitorOwner.trashButton(for: secondItem.id))
        window.close()
    }

    @MainActor
    private func todoRowHoverTrackers(in view: NSView) -> [TodoRowHoverTracker.HoverView] {
        let current = (view as? TodoRowHoverTracker.HoverView).map { [$0] } ?? []
        return current + view.subviews.flatMap(todoRowHoverTrackers(in:))
    }

    @MainActor
    func testVisibleRedTaskTrashDeletesOnlyItsTargetRow() throws {
        if try runIsolatedHostedTodoTestIfNeeded(
            environmentKey: "NATIVE_SCHEDULER_TODO_TRASH_CHILD",
            testName: "NativeSchedulerTests.NotchShellTests/testVisibleRedTaskTrashDeletesOnlyItsTargetRow"
        ) { return }
        let firstID = UUID()
        let secondID = UUID()
        var deleted: [UUID] = []
        let root = HStack {
            TodoTaskTrashButton(itemID: firstID, isVisible: true) { deleted.append(firstID) }
                .frame(width: 44, height: 44)
            TodoTaskTrashButton(itemID: secondID, isVisible: true) { deleted.append(secondID) }
                .frame(width: 44, height: 44)
        }
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(x: 0, y: 0, width: 88, height: 44)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()

        let first = try XCTUnwrap(nativeButton(withAccessibilityIdentifier: "todo.task.delete.\(firstID.uuidString)", in: host) as? TodoPointingHandButton)
        let second = try XCTUnwrap(nativeButton(withAccessibilityIdentifier: "todo.task.delete.\(secondID.uuidString)", in: host) as? TodoPointingHandButton)
        XCTAssertEqual(first.frame.width, 44, accuracy: 0.5)
        XCTAssertEqual(second.frame.width, 44, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(first.frame.height, 44)
        XCTAssertGreaterThanOrEqual(second.frame.height, 44)
        XCTAssertEqual(first.contentTintColor, .systemRed)
        XCTAssertEqual(second.contentTintColor, .systemRed)
        XCTAssertEqual(first.cursorForInteraction, NSCursor.pointingHand)
        first.performClick(nil)
        XCTAssertEqual(deleted, [firstID])
        XCTAssertTrue(second.accessibilityPerformPress())
        XCTAssertEqual(deleted, [firstID, secondID])
        window.contentView = nil
        window.close()
    }

    @MainActor
    func testExpandedMainPanelRendersEveryTaskEightFixtureAtTheRealPaddedChild() async throws {
        NSApplication.shared.finishLaunching()
        XCTAssertTrue(AXIsProcessTrusted(), "Native AX evidence requires pre-granted accessibility trust.")
        let axClientDirectory = FileManager.default.temporaryDirectory
            .appending(path: "NativeSchedulerAXClient-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: axClientDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: axClientDirectory) }
        let nativeAXClient = try compileNativeAXClient(in: axClientDirectory)
        let nativeAXClientHash = try sha256(of: nativeAXClient)
        let nativeAXClientSource = nativeAXClientSourceURL()
        let nativeAXClientSourceHash = try sha256(of: nativeAXClientSource)
        var utc = Calendar(identifier: .gregorian)
        utc.locale = Locale(identifier: "en_US")
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.locale = Locale(identifier: "en_US")
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let utcNow = try XCTUnwrap(
            utc.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 18))
        )
        let dstNow = try XCTUnwrap(losAngeles.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)))
        let defaultDays: [String?] = Array(repeating: nil, count: 5)
        let customDays: [String?] = Array(repeating: "#FF922B", count: 5)
        let scenarios = [
            Task8RenderScenario(name: "empty", now: utcNow, calendar: utc, notchHeight: 37, categoryHexes: [], startsTimer: false, timerCategoryHex: nil, reduceMotion: false, showsRecordingRetry: false),
            Task8RenderScenario(name: "default", now: utcNow, calendar: utc, notchHeight: 37, categoryHexes: defaultDays, startsTimer: true, timerCategoryHex: nil, reduceMotion: false, showsRecordingRetry: false),
            Task8RenderScenario(name: "custom", now: utcNow, calendar: utc, notchHeight: 37, categoryHexes: customDays, startsTimer: true, timerCategoryHex: "#FF922B", reduceMotion: false, showsRecordingRetry: false),
            Task8RenderScenario(name: "many-categories", now: utcNow, calendar: utc, notchHeight: 37, categoryHexes: ["#4DABF7", "#FF922B", "#51CF66", "#CC5DE8", "#FFD43B"], startsTimer: true, timerCategoryHex: nil, reduceMotion: false, showsRecordingRetry: false),
            Task8RenderScenario(name: "dst-fall-back", now: dstNow, calendar: losAngeles, notchHeight: 37, categoryHexes: customDays, startsTimer: false, timerCategoryHex: nil, reduceMotion: false, showsRecordingRetry: false),
            Task8RenderScenario(name: "notch-32", now: utcNow, calendar: utc, notchHeight: 32, categoryHexes: defaultDays, startsTimer: false, timerCategoryHex: nil, reduceMotion: false, showsRecordingRetry: false),
            Task8RenderScenario(name: "notch-42-reduce-motion", now: utcNow, calendar: utc, notchHeight: 42, categoryHexes: defaultDays, startsTimer: false, timerCategoryHex: nil, reduceMotion: true, showsRecordingRetry: false),
            Task8RenderScenario(name: "recording-retry", now: utcNow, calendar: utc, notchHeight: 37, categoryHexes: defaultDays, startsTimer: false, timerCategoryHex: nil, reduceMotion: false, showsRecordingRetry: true)
        ]
        let outputDirectory = ProcessInfo.processInfo.environment["TASK_8_RENDER_OUTPUT"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        if let outputDirectory {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }
        var layoutEvidence: [[String: Any]] = []
        var accessibilityEvidence: [[String: Any]] = []
        var nativeAXClientEvidence: [[String: Any]] = []
        var capturedImages: [NSBitmapImageRep] = []

        for scenario in scenarios {
            let result = try await renderTask8Scenario(
                scenario,
                nativeAXClient: nativeAXClient,
                nativeAXClientHash: nativeAXClientHash
            )
            try assertTask8NativeAccessibility(
                scenario: scenario,
                window: result.window,
                nodes: result.accessibility
            )
            let expectedHeight = NotchGeometry.expandedPanelHeight - (scenario.notchHeight + 10) - 16
            XCTAssertEqual(result.probe.proposedSize, CGSize(width: 776, height: expectedHeight))
            let stackedContentHeight = result.probe.metrics.contentHeight
                - result.probe.metrics.expandedStackSpacing
        let expectedTimerHeight = min(
            stackedContentHeight,
            min(92, max(78, stackedContentHeight * 0.32))
        )
            XCTAssertEqual(result.probe.metrics.timerHeight, expectedTimerHeight, accuracy: 0.001)
            XCTAssertEqual(result.probe.metrics.toggleHeight, 0, accuracy: 0.001)
            XCTAssertEqual(result.probe.metrics.stackSpacing, 8, accuracy: 0.001)
            XCTAssertEqual(
                result.probe.metrics.heatmapHeight
                    + result.probe.metrics.timerHeight
                    + result.probe.metrics.stackSpacing,
                result.probe.metrics.contentHeight,
                accuracy: 0.001
            )
            XCTAssertEqual(result.window.days.count, 5)
            XCTAssertEqual(result.image.pixelsWide, 1_552)
            XCTAssertEqual(result.image.pixelsHigh, Int(expectedHeight * 2))
            XCTAssertGreaterThan(nonBlackSampleCount(in: result.image), 10)
            if scenario.startsTimer {
                XCTAssertTrue(containsColor(Color.resolvedCategoryHex(scenario.timerCategoryHex), in: result.image))
            }
            if scenario.name == "many-categories" {
                let today = try XCTUnwrap(result.window.days.first)
                let entries = TodayUsageSummaryProjection.compactEntries(for: today)
                let title = TodayUsageSummaryProjection.totalText(
                    today.totalTrackedSeconds,
                    localeIdentifier: today.localeIdentifier
                )
                let font = NSFont.monospacedSystemFont(
                    ofSize: TodayUsageSummaryLayout.meaningfulTextSize,
                    weight: .semibold
                )
                let titleWidth = (title as NSString).size(withAttributes: [.font: font]).width
                let availableTitleWidth = TodayUsageSummaryLayout.textColumnWidth(
                    summaryWidth: result.probe.metrics.summaryWidth
                )
                XCTAssertGreaterThan(today.categoryTotals.count, 3)
                XCTAssertEqual(entries.count, 4)
                XCTAssertEqual(entries.last?.name, "Etc")
                XCTAssertEqual(title, "Today · 4h 15m")
                XCTAssertLessThanOrEqual(
                    titleWidth,
                    availableTitleWidth,
                    "The captured many-category Today total must not ellipsize."
                )
            }

            layoutEvidence.append([
                "scenario": scenario.name,
                "childWidth": result.probe.proposedSize.width,
                "childHeight": result.probe.proposedSize.height,
                "daylineHeight": result.probe.metrics.heatmapHeight,
                "timerSummaryHeight": result.probe.metrics.timerHeight,
                "disclosureRowHeight": result.probe.metrics.toggleHeight,
                "rows": result.window.days.count,
                "rowHeight": DaylineViewMetrics.dayRowHeight,
                "trackHeight": DaylineViewMetrics.trackHeight,
                "reduceMotion": scenario.reduceMotion
            ])
            accessibilityEvidence.append([
                "scenario": scenario.name,
                "nativeNodes": result.accessibility.map(\.json),
                "nativeInteraction": result.interaction,
                "supplementalContract": task8AccessibilityEvidence(
                    scenario: scenario.name,
                    window: result.window
                )
            ])
            nativeAXClientEvidence.append(contentsOf: result.externalAXActions)
            capturedImages.append(result.image)

            if let outputDirectory {
                let png = try XCTUnwrap(result.image.representation(using: .png, properties: [:]))
                try png.write(to: outputDirectory.appending(path: "task-8-\(scenario.name).png"))
            }
        }

        if let outputDirectory {
            XCTAssertEqual(nativeAXClientEvidence.count, 4)
            XCTAssertTrue(nativeAXClientEvidence.allSatisfy { ($0["exitStatus"] as? Int) == 0 })
            XCTAssertTrue(nativeAXClientEvidence.allSatisfy { ($0["stderr"] as? String) == "" })
            XCTAssertTrue(nativeAXClientEvidence.allSatisfy {
                (($0["result"] as? [String: Any])?["passed"] as? Bool) == true
            })
            XCTAssertEqual(nativeAXClientHash.count, 64)
            XCTAssertEqual(nativeAXClientSourceHash.count, 64)
            try writeJSON(layoutEvidence, to: outputDirectory.appending(path: "task-8-layout.json"))
            try writeJSON(accessibilityEvidence, to: outputDirectory.appending(path: "task-8-ax.json"))
            try writeJSON([
                "schemaVersion": 1,
                "client": [
                    "binaryPath": nativeAXClient.path,
                    "binarySHA256": nativeAXClientHash,
                    "sourcePath": nativeAXClientSource.path,
                    "sourceSHA256": nativeAXClientSourceHash
                ],
                "targetPID": Int(getpid()),
                "actions": nativeAXClientEvidence
            ], to: outputDirectory.appending(path: "task-8-native-ax-client-transcript.json"))
            let composite = try compositeImage(capturedImages, columns: 2, gutter: 16)
            let png = try XCTUnwrap(composite.representation(using: .png, properties: [:]))
            try png.write(to: outputDirectory.appending(path: "task-8-composite.png"))
        }
    }

    private func assertTask8NativeAccessibility(
        scenario: Task8RenderScenario,
        window: DayActivityWindowSnapshot,
        nodes: [NativeAXNode]
    ) throws {
        let expectedSegmentIdentifiers = window.days.flatMap(\.segments).map {
            DaylineContract.segmentAccessibilityIdentifier($0.id)
        }
        let daylineNodes = nodes.filter {
            $0.identifier == "dayline.header"
                || $0.identifier == "dayline.toggle"
                || $0.identifier.hasPrefix("dayline.segment|")
        }
        XCTAssertEqual(
            daylineNodes.map(\.identifier),
            ["dayline.header", "dayline.toggle"] + expectedSegmentIdentifiers,
            "Live AX traversal must preserve header, inter-card toggle, and newest-first segment order."
        )

        let header = try XCTUnwrap(daylineNodes.first { $0.identifier == "dayline.header" })
        XCTAssertEqual(header.role, kAXGroupRole as String)
        XCTAssertFalse(header.label.isEmpty)

        let actionableIdentifiers = ["dayline.toggle"] + expectedSegmentIdentifiers
        for identifier in actionableIdentifiers {
            let node = try XCTUnwrap(
                nodes.first { $0.identifier == identifier },
                "Live AX tree is missing actionable node \(identifier)."
            )
            XCTAssertEqual(node.role, kAXButtonRole as String, "\(identifier) must remain a native AX button.")
            XCTAssertTrue(node.actions.contains(kAXPressAction as String), "\(identifier) must support AXPress.")
            XCTAssertGreaterThanOrEqual(
                node.frame.width,
                DaylineViewMetrics.minimumActionTarget,
                "\(identifier) has only \(node.frame.width)pt of native AX width."
            )
            XCTAssertGreaterThanOrEqual(
                node.frame.height,
                DaylineViewMetrics.minimumActionTarget,
                "\(identifier) has only \(node.frame.height)pt of native AX height."
            )
            XCTAssertFalse(node.label.isEmpty, "\(identifier) needs a spoken label.")
        }

        if scenario.showsRecordingRetry {
            let retry = try XCTUnwrap(
                nodes.first { $0.identifier == "timer.recording.retry" },
                "Live AX tree is missing the recording retry button."
            )
            XCTAssertEqual(retry.role, kAXButtonRole as String)
            XCTAssertTrue(retry.actions.contains(kAXPressAction as String))
            XCTAssertGreaterThanOrEqual(retry.frame.width, DaylineViewMetrics.minimumActionTarget)
            XCTAssertGreaterThanOrEqual(
                retry.frame.height,
                DaylineViewMetrics.minimumActionTarget,
                "Recording retry has only \(retry.frame.height)pt of native AX height."
            )
            XCTAssertFalse(retry.label.isEmpty)
        }
    }

    @MainActor
    private func renderTask8Scenario(
        _ scenario: Task8RenderScenario,
        nativeAXClient: URL,
        nativeAXClientHash: String
    ) async throws -> (
        image: NSBitmapImageRep,
        probe: MainPanelLayoutProbe,
        window: DayActivityWindowSnapshot,
        accessibility: [NativeAXNode],
        interaction: [String: Any],
        externalAXActions: [[String: Any]]
    ) {
        let container = NSPersistentContainer(name: "Task8Render", managedObjectModel: CoreDataStack.model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        let context = container.viewContext
        let engine = TimerEngine()
        engine.mode = .duration
        engine.durationSeconds = 25 * 60
        var saveAttempt = 0
        let timerVM = TimerViewModel(
            engine: engine,
            context: context,
            now: { scenario.startsTimer ? Date() : scenario.now }
        ) { context in
            saveAttempt += 1
            if scenario.showsRecordingRetry, saveAttempt == 2 {
                throw NSError(domain: "Task8Render", code: 8)
            }
            if context.hasChanges { try context.save() }
        }
        if let colorHex = scenario.timerCategoryHex {
            let category = CategoryEntity.create(name: "Custom", colorHex: colorHex, sortOrder: 0, in: context)
            timerVM.changeCategory(to: category)
        }
        if scenario.startsTimer { timerVM.start() }
        if scenario.showsRecordingRetry {
            timerVM.start()
            timerVM.stop()
            XCTAssertTrue(timerVM.canRetryFinalization)
            XCTAssertEqual(timerVM.recordingError, "Recording could not be finalized. Retry.")
        }

        var records = scenario.categoryHexes.enumerated().map { index, colorHex -> DayActivityRecord in
            let dayOffset = scenario.name == "many-categories"
                ? 0
                : (scenario.startsTimer ? min(index + 1, 4) : index % 5)
            let dayStart = scenario.calendar.date(
                byAdding: .day,
                value: -dayOffset,
                to: scenario.calendar.startOfDay(for: scenario.now)
            )!
            let start = scenario.calendar.date(byAdding: .hour, value: 7 + index * 2, to: dayStart)!
            let resolvedHex = Color.resolvedCategoryHex(colorHex)
            let categoryID = colorHex == nil ? nil : UUID(uuidString: String(format: "A0000000-0000-0000-0000-%012d", index + 1))
            return DayActivityRecord(
                sessionID: UUID(uuidString: String(format: "B0000000-0000-0000-0000-%012d", index + 1))!,
                start: start,
                end: start.addingTimeInterval(45 * 60),
                categoryID: categoryID,
                categoryName: colorHex == nil ? "Default" : "Category \(index + 1)",
                categoryHex: resolvedHex,
                isRunning: false
            )
        }
        if let activeID = timerVM.activeSessionID {
            records.append(DayActivityRecord(
                sessionID: activeID,
                start: scenario.now.addingTimeInterval(-30 * 60),
                end: scenario.now.addingTimeInterval(-30 * 60),
                categoryID: timerVM.selectedCategory?.id,
                categoryName: timerVM.selectedCategory?.name ?? "Default",
                categoryHex: timerVM.themeColorHex,
                isRunning: true
            ))
        }
        let store = DayActivityStore(
            calendar: scenario.calendar,
            locale: Locale(identifier: "en_US"),
            now: { scenario.now },
            observesChanges: false,
            activeSessionID: timerVM.activeSessionID,
            recordsFetcher: { _, _, _ in records }
        )
        let capture = LayoutCapture()
        let presentationState = MainPanelPresentationState(isDaylineExpanded: true)
        let daylineInteraction = DaylineInteractionModel()
        let childSize = CGSize(
            width: 776,
            height: NotchGeometry.expandedPanelHeight - (scenario.notchHeight + 10) - 16
        )
        let hostRoot = MainPanelView(
            timerVM: timerVM,
            dayActivityStore: store,
            initialDaylineExpanded: true,
            reduceMotionOverride: scenario.reduceMotion,
            presentationState: presentationState,
            daylineInteraction: daylineInteraction,
            layoutProbe: { capture.probe = $0 }
        )
        .frame(width: childSize.width, height: childSize.height)
        let host = NSHostingView(rootView: hostRoot)
        host.frame = CGRect(origin: .zero, size: childSize)
        let hostWindow = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hostWindow.animationBehavior = .none
        hostWindow.isReleasedWhenClosed = false
        let windowIdentifier = "task8.host.\(scenario.name)"
        hostWindow.title = windowIdentifier
        hostWindow.setAccessibilityIdentifier(windowIdentifier)
        hostWindow.contentView = host
        hostWindow.setFrameOrigin(NSPoint(x: 40, y: 40))
        hostWindow.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let accessibility = try runAXOperation {
            try Self.nativeAccessibilityNodes(
                processID: getpid(),
                windowIdentifier: windowIdentifier
            )
        }
        let probe = try XCTUnwrap(capture.probe)
        let window = try XCTUnwrap(store.windowSnapshot)
        var interaction: [String: Any] = [:]
        var externalAXActions: [[String: Any]] = []
        if scenario.name == "default",
           let segment = window.days.flatMap(\.segments).first(where: { !$0.isActive }) {
            let segmentIdentifier = DaylineContract.segmentAccessibilityIdentifier(segment.id)
            let segmentPinned = expectation(description: "Dayline segment is pinned")
            let pinSubscription = daylineInteraction.statePublisher
                .map(\.pinnedSegmentID)
                .dropFirst()
                .filter { $0 == segment.id }
                .prefix(1)
                .sink { _ in segmentPinned.fulfill() }
            let selectInvocation = try performExternalAXPress(
                client: nativeAXClient,
                clientSHA256: nativeAXClientHash,
                windowIdentifier: windowIdentifier,
                elementIdentifier: segmentIdentifier
            )
            await fulfillment(of: [segmentPinned], timeout: 1)
            pinSubscription.cancel()
            XCTAssertEqual(daylineInteraction.pinnedSegmentID, segment.id)
            externalAXActions.append(selectInvocation.json(result: [
                "selectedModelIdentifier": segmentIdentifier,
                "passed": daylineInteraction.pinnedSegmentID == segment.id
            ]))

            let segmentReset = expectation(description: "Pinned Dayline segment is reset")
            let resetSubscription = daylineInteraction.statePublisher
                .map(\.pinnedSegmentID)
                .filter { $0 == nil }
                .prefix(1)
                .sink { _ in segmentReset.fulfill() }
            let daylineCollapsed = expectation(description: "Dayline presentation is collapsed")
            let collapseSubscription = presentationState.$isDaylineExpanded
                .filter { !$0 }
                .prefix(1)
                .sink { _ in daylineCollapsed.fulfill() }
            let collapseInvocation = try performExternalAXPress(
                client: nativeAXClient,
                clientSHA256: nativeAXClientHash,
                windowIdentifier: windowIdentifier,
                elementIdentifier: "dayline.toggle"
            )
            await fulfillment(of: [segmentReset, daylineCollapsed], timeout: 1)
            resetSubscription.cancel()
            collapseSubscription.cancel()
            XCTAssertNil(store.windowSnapshot)
            XCTAssertNil(daylineInteraction.pinnedSegmentID)
            externalAXActions.append(collapseInvocation.json(result: [
                "isDaylineExpanded": store.windowSnapshot != nil,
                "selectionReset": daylineInteraction.pinnedSegmentID == nil,
                "passed": store.windowSnapshot == nil && daylineInteraction.pinnedSegmentID == nil
            ]))

            let daylineReopened = expectation(description: "Dayline presentation is expanded")
            let reopenSubscription = presentationState.$isDaylineExpanded
                .filter { $0 }
                .prefix(1)
                .sink { _ in daylineReopened.fulfill() }
            let reopenInvocation = try performExternalAXPress(
                client: nativeAXClient,
                clientSHA256: nativeAXClientHash,
                windowIdentifier: windowIdentifier,
                elementIdentifier: "dayline.toggle"
            )
            await fulfillment(of: [daylineReopened], timeout: 1)
            reopenSubscription.cancel()
            XCTAssertEqual(store.windowSnapshot?.days.count, 5)
            XCTAssertNil(daylineInteraction.pinnedSegmentID)
            externalAXActions.append(reopenInvocation.json(result: [
                "isDaylineExpanded": store.windowSnapshot != nil,
                "selectionReset": daylineInteraction.pinnedSegmentID == nil,
                "passed": store.windowSnapshot?.days.count == 5 && daylineInteraction.pinnedSegmentID == nil
            ]))
            interaction["segmentSelectionReset"] = [
                "identifier": segmentIdentifier,
                "action": kAXPressAction as String,
                "selectedModelIdentifier": segmentIdentifier,
                "collapsed": true,
                "selectionReset": true,
                "reopened": true,
                "productStateSource": "DayActivityStore + DaylineInteractionModel",
                "passed": true
            ]
        }
        let renderRoot = MainPanelView(
            timerVM: timerVM,
            dayActivityStore: store,
            initialDaylineExpanded: true,
            reduceMotionOverride: scenario.reduceMotion
        )
        .frame(width: childSize.width, height: childSize.height)
        let renderer = ImageRenderer(content: renderRoot)
        renderer.proposedSize = ProposedViewSize(childSize)
        renderer.scale = 2
        let image = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        if scenario.startsTimer { timerVM.stop() }
        if scenario.showsRecordingRetry {
            let retryInvocation = try performExternalAXPress(
                client: nativeAXClient,
                clientSHA256: nativeAXClientHash,
                windowIdentifier: windowIdentifier,
                elementIdentifier: "timer.recording.retry"
            )
            XCTAssertFalse(timerVM.canRetryFinalization)
            XCTAssertNil(timerVM.recordingError)
            interaction["recordingRetry"] = [
                "identifier": "timer.recording.retry",
                "action": kAXPressAction as String,
                "canRetryAfterPress": timerVM.canRetryFinalization,
                "errorAfterPress": timerVM.recordingError.map { $0 as Any } ?? NSNull(),
                "passed": true
            ]
            externalAXActions.append(retryInvocation.json(result: [
                "canRetryAfterPress": timerVM.canRetryFinalization,
                "errorAfterPress": timerVM.recordingError.map { $0 as Any } ?? NSNull(),
                "passed": !timerVM.canRetryFinalization && timerVM.recordingError == nil
            ]))
        }
        hostWindow.orderOut(nil)
        withExtendedLifetime((container, hostWindow, host)) {}
        return (image, probe, window, accessibility, interaction, externalAXActions)
    }

    @MainActor
    private func compileNativeAXClient(in directory: URL) throws -> URL {
        let source = nativeAXClientSourceURL()
        let executable = directory.appending(path: "NativeAXClient")
        let result = try runExternalProcess(
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["swiftc", source.path, "-o", executable.path],
            timeout: 20
        )
        guard result.exitStatus == 0,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw NSError(domain: "Task8AXClient", code: 1, userInfo: [
                NSLocalizedDescriptionKey: [
                    "The external native AX client was not built.",
                    result.stdout,
                    result.stderr
                ].filter { !$0.isEmpty }.joined(separator: "\n")
            ])
        }
        return executable
    }

    private func nativeAXClientSourceURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Tools/NativeAXClient.swift")
    }

    private func sha256(of url: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: url))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    private func performExternalAXPress(
        client: URL,
        clientSHA256: String,
        windowIdentifier: String,
        elementIdentifier: String
    ) throws -> NativeAXInvocation {
        let targetPID = getpid()
        let result = try runExternalProcess(
            executable: client,
            arguments: [String(targetPID), windowIdentifier, elementIdentifier],
            timeout: 4
        )
        let expectedOutput = "AXPress|\(targetPID)|\(windowIdentifier)|\(elementIdentifier)\n"
        guard result.exitStatus == 0 else {
            throw NSError(domain: "Task8AXClient", code: Int(result.exitStatus), userInfo: [
                NSLocalizedDescriptionKey: "Native AX client failed for \(windowIdentifier)/\(elementIdentifier): \(result.stderr)"
            ])
        }
        guard result.stdout == expectedOutput, result.stderr.isEmpty else {
            throw NSError(domain: "Task8AXClient", code: 3, userInfo: [
                NSLocalizedDescriptionKey: [
                    "Native AX client returned invalid output.",
                    "expected stdout: \(expectedOutput.debugDescription)",
                    "actual stdout: \(result.stdout.debugDescription)",
                    "stderr: \(result.stderr.debugDescription)"
                ].joined(separator: "\n")
            ])
        }
        return NativeAXInvocation(
            process: result,
            clientBinarySHA256: clientSHA256,
            targetPID: targetPID,
            windowIdentifier: windowIdentifier,
            elementIdentifier: elementIdentifier
        )
    }

    @MainActor
    private func runExternalProcess(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> ExternalProcessResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        let terminated = expectation(
            description: "External process \(executable.lastPathComponent) terminated"
        )
        process.terminationHandler = { _ in
            terminated.fulfill()
        }
        try process.run()

        if XCTWaiter.wait(for: [terminated], timeout: timeout) == .timedOut {
            process.terminate()
            process.waitUntilExit()
            throw NSError(domain: "Task8AXClient", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "External process timed out: \(executable.lastPathComponent)."
            ])
        }
        process.waitUntilExit()

        let stdout = String(
            data: standardOutput.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: standardError.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return ExternalProcessResult(
            command: [executable.path] + arguments,
            stdout: stdout,
            stderr: stderr,
            exitStatus: process.terminationStatus
        )
    }

    @MainActor
    private func runAXOperation<Value>(
        _ operation: @escaping @Sendable () throws -> Value
    ) throws -> Value {
        let box = AXResultBox<Value>()
        let completed = expectation(description: "Native AX operation completed")
        DispatchQueue.global(qos: .userInitiated).async {
            box.store(Result { try operation() })
            completed.fulfill()
        }
        wait(for: [completed], timeout: 3)
        guard let result = box.load() else {
            throw NSError(domain: "Task8AX", code: Int(AXError.cannotComplete.rawValue))
        }
        return try result.get()
    }

    private static func nativeAccessibilityNodes(
        processID: pid_t,
        windowIdentifier: String
    ) throws -> [NativeAXNode] {
        let window = try nativeAccessibilityWindow(
            processID: processID,
            windowIdentifier: windowIdentifier
        )
        var nodes: [NativeAXNode] = []
        var visited = Set<CFHashCode>()

        func walk(_ element: AXUIElement) {
            guard visited.insert(CFHash(element)).inserted else { return }
            let role = axString(element, attribute: kAXRoleAttribute as CFString)
            let description = axString(element, attribute: kAXDescriptionAttribute as CFString)
            let title = axString(element, attribute: kAXTitleAttribute as CFString)
            let identifier = axString(element, attribute: kAXIdentifierAttribute as CFString)
            let value = axString(element, attribute: kAXValueAttribute as CFString)
            nodes.append(NativeAXNode(
                traversalIndex: nodes.count,
                role: role,
                label: description.isEmpty ? title : description,
                identifier: identifier,
                isEnabled: axBool(element, attribute: kAXEnabledAttribute as CFString) ?? true,
                frame: axFrame(element),
                actions: axActions(element),
                value: value
            ))
            let ordered = (try? axElements(
                element,
                attribute: NSAccessibility.Attribute.childrenInNavigationOrderAttribute.rawValue as CFString
            )) ?? []
            let children = ordered.isEmpty
                ? ((try? axElements(element, attribute: kAXChildrenAttribute as CFString)) ?? [])
                : ordered
            children.forEach(walk)
        }

        walk(window)
        return nodes
    }

    private static func nativeAccessibilityWindow(
        processID: pid_t,
        windowIdentifier: String
    ) throws -> AXUIElement {
        let application = AXUIElementCreateApplication(processID)
        let windows = try axElements(application, attribute: kAXWindowsAttribute as CFString)
        guard let window = windows.first(where: {
            axString($0, attribute: kAXIdentifierAttribute as CFString) == windowIdentifier
                || axString($0, attribute: kAXTitleAttribute as CFString) == windowIdentifier
        }) else {
            throw NSError(domain: "Task8AX", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Task 8 host window was absent from the live AX tree."
            ])
        }
        return window
    }

    private static func axElements(
        _ element: AXUIElement,
        attribute: CFString
    ) throws -> [AXUIElement] {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else {
            throw NSError(domain: "Task8AX", code: Int(error.rawValue), userInfo: [
                NSLocalizedDescriptionKey: "AX attribute \(attribute) failed with \(error.rawValue)."
            ])
        }
        return value as? [AXUIElement] ?? []
    }

    private static func axValue(
        _ element: AXUIElement,
        attribute: CFString
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }

    private static func axString(
        _ element: AXUIElement,
        attribute: CFString
    ) -> String {
        axValue(element, attribute: attribute) as? String ?? ""
    }

    private static func axBool(
        _ element: AXUIElement,
        attribute: CFString
    ) -> Bool? {
        (axValue(element, attribute: attribute) as? NSNumber)?.boolValue
    }

    private static func axFrame(_ element: AXUIElement) -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        if let rawPosition = axValue(element, attribute: kAXPositionAttribute as CFString),
           CFGetTypeID(rawPosition) == AXValueGetTypeID() {
            AXValueGetValue(rawPosition as! AXValue, .cgPoint, &origin)
        }
        if let rawSize = axValue(element, attribute: kAXSizeAttribute as CFString),
           CFGetTypeID(rawSize) == AXValueGetTypeID() {
            AXValueGetValue(rawSize as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }

    private static func axActions(_ element: AXUIElement) -> [String] {
        var value: CFArray?
        guard AXUIElementCopyActionNames(element, &value) == .success else { return [] }
        return value as? [String] ?? []
    }

    private func nonBlackSampleCount(in image: NSBitmapImageRep) -> Int {
        stride(from: 0, to: image.pixelsHigh, by: 40).reduce(0) { count, y in
            count + stride(from: 0, to: image.pixelsWide, by: 40).filter { x in
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                return max(color.redComponent, color.greenComponent, color.blueComponent) > 0.025
            }.count
        }
    }

    private func writeViewSnapshot(_ view: NSView, to url: URL) throws {
        let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: image)
        let png = try XCTUnwrap(image.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    private func containsColor(_ hex: String, in image: NSBitmapImageRep) -> Bool {
        let expected = NSColor(Color(hex: hex)).usingColorSpace(.sRGB)!
        return stride(from: 0, to: image.pixelsHigh, by: 4).contains { y in
            stride(from: 0, to: image.pixelsWide, by: 4).contains { x in
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                return max(
                    abs(color.redComponent - expected.redComponent),
                    abs(color.greenComponent - expected.greenComponent),
                    abs(color.blueComponent - expected.blueComponent)
                ) < 0.08
            }
        }
    }

    private func compositeImage(
        _ images: [NSBitmapImageRep],
        columns: Int,
        gutter: Int
    ) throws -> NSBitmapImageRep {
        let tileWidth = try XCTUnwrap(images.map(\.pixelsWide).max())
        let tileHeight = try XCTUnwrap(images.map(\.pixelsHigh).max())
        let rows = Int(ceil(Double(images.count) / Double(columns)))
        let width = columns * tileWidth + (columns - 1) * gutter
        let height = rows * tileHeight + (rows - 1) * gutter
        let composite = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: composite))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        for (index, image) in images.enumerated() {
            let column = index % columns
            let row = rows - 1 - index / columns
            image.draw(in: NSRect(
                x: column * (tileWidth + gutter),
                y: row * (tileHeight + gutter),
                width: image.pixelsWide,
                height: image.pixelsHigh
            ))
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return composite
    }

    private func task8AccessibilityEvidence(
        scenario: String,
        window: DayActivityWindowSnapshot
    ) -> [String: Any] {
        let rows = DaylineContract.expandedRows(for: window)
        let order = DaylineInteractionState().accessibilityOrder(in: window.days).map { item -> String in
            switch item {
            case .header:
                return "header"
            case .toggle:
                return "toggle"
            case let .segment(id):
                return "segment|\(id.dayStart.timeIntervalSinceReferenceDate)|\(id.sessionID.uuidString.lowercased())|\(id.winningPieceStart.timeIntervalSinceReferenceDate)"
            }
        }
        return [
            "scenario": scenario,
            "order": order,
            "dayLabels": rows.map(\.label),
            "dayCount": rows.count,
            "activeSegmentCount": window.days.flatMap(\.segments).filter(\.isActive).count,
            "toggleLabel": DaylineViewControl.label(isExpanded: true),
            "minimumActionTarget": DaylineViewMetrics.minimumActionTarget
        ]
    }

    private func writeJSON(_ value: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }
}
