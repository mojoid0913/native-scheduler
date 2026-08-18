@preconcurrency import AppKit
import Combine
import SwiftUI

struct NotchGlobalPointerEvent: Sendable {
    static let notificationName = Notification.Name("NativeScheduler.NotchGlobalPointerEvent")

    let screenPoint: CGPoint
}

enum NotchGlobalHover {
    static func shouldExpand(
        isExpanded: Bool,
        point: CGPoint,
        windowFrame: CGRect,
        localRect: CGRect
    ) -> Bool {
        !isExpanded && NotchGeometry.containsScreenPoint(
            point,
            windowFrame: windowFrame,
            localRect: localRect
        )
    }
}

final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    weak var windowState: NotchWindowState?
    weak var timerState: NotchTimerState?
    var notchSize: CGSize = .zero
    private var hoverTrackingArea: NSTrackingArea?
    private var hoverTask: Task<Void, Never>?

    var hoverHitRect: CGRect {
        NotchGeometry.hitRect(
            bounds: bounds,
            isExpanded: windowState?.isExpanded ?? false,
            notchWidth: notchSize.width,
            notchHeight: notchSize.height,
            showsProgress: timerState?.snapshot.isRunning ?? false
        )
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let windowState, !windowState.isExpanded else {
            return super.hitTest(point)
        }

        return containsHoverPoint(point) ? super.hitTest(point) : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: hoverHitRect,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        handleCollapsedPointerMovement(event)
    }

    override func mouseMoved(with event: NSEvent) {
        handleCollapsedPointerMovement(event)
    }

    private func containsHoverPoint(_ point: CGPoint) -> Bool {
        NotchGeometry.containsLocalPoint(
            point,
            localRect: hoverHitRect,
            isExpanded: windowState?.isExpanded ?? false
        )
    }

    private func handleCollapsedPointerMovement(_ event: NSEvent) {
        hoverTask?.cancel()
        guard windowState?.isExpanded == false,
              containsHoverPoint(convert(event.locationInWindow, from: nil)) else { return }

        hoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled,
                  let self,
                  let windowState = self.windowState,
                  !windowState.isExpanded,
                  let window = self.window,
                  NotchGeometry.containsScreenPoint(
                    NSEvent.mouseLocation,
                    windowFrame: window.frame,
                    localRect: self.hoverHitRect
                  ) else { return }
            windowState.isExpanded = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoverTask?.cancel()
        guard let windowState, windowState.isExpanded else { return }
        windowState.collapseForPointerExit()
    }
}

final class NotchWindow: NSPanel {
    private let windowState: NotchWindowState
    private let timerState: NotchTimerState
    private let expandedContent: AnyView
    private let onQuit: () -> Void

    private var hostingView: PassthroughHostingView<AnyView>?
    private var expansionCancellable: AnyCancellable?
    private var globalHoverTask: Task<Void, Never>?
    private nonisolated(unsafe) var globalMouseMonitor: Any?
    private nonisolated(unsafe) var localKeyMonitor: Any?
    private nonisolated(unsafe) var screenObserver: NSObjectProtocol?

    init(
        windowState: NotchWindowState,
        timerState: NotchTimerState,
        expandedContent: AnyView,
        onQuit: @escaping () -> Void
    ) {
        self.windowState = windowState
        self.timerState = timerState
        self.expandedContent = expandedContent
        self.onQuit = onQuit

        let screen = NotchGeometry.preferredScreen() ?? NSScreen.screens[0]
        let frame = NotchGeometry.windowFrame(for: screen)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false

        setupContent()
        setupExpansionObserver()
        setupMonitors()
        setupScreenObserver()
    }

    func updateForCurrentScreen() {
        guard let screen = NotchGeometry.preferredScreen() else {
            orderOut(nil)
            return
        }

        setFrame(NotchGeometry.windowFrame(for: screen), display: false)
        refreshRootView(for: screen)
        orderFrontRegardless()
    }

    func refreshPresentedContent() {
        guard let screen = self.screen ?? NotchGeometry.preferredScreen() else { return }
        refreshRootView(for: screen, identity: UUID())
    }

    private func setupContent() {
        let screen = NotchGeometry.preferredScreen() ?? NSScreen.screens[0]
        let hostingView = PassthroughHostingView(rootView: makeRootView(for: screen))
        hostingView.windowState = windowState
        hostingView.timerState = timerState
        hostingView.notchSize = CGSize(
            width: NotchGeometry.notchWidth(for: screen),
            height: NotchGeometry.notchHeight(for: screen)
        )
        hostingView.frame = CGRect(origin: .zero, size: frame.size)
        contentView = hostingView
        self.hostingView = hostingView
    }

    private func refreshRootView(for screen: NSScreen, identity: UUID? = nil) {
        guard let hostingView else { return }
        hostingView.notchSize = CGSize(
            width: NotchGeometry.notchWidth(for: screen),
            height: NotchGeometry.notchHeight(for: screen)
        )
        hostingView.frame = CGRect(origin: .zero, size: frame.size)
        let rootView = makeRootView(for: screen)
        hostingView.rootView = if let identity {
            AnyView(rootView.id(identity))
        } else {
            rootView
        }
        hostingView.updateTrackingAreas()
    }

    private func makeRootView(for screen: NSScreen) -> AnyView {
        AnyView(
            NotchView(
                windowState: windowState,
                timerState: timerState,
                notchSize: CGSize(
                    width: NotchGeometry.notchWidth(for: screen),
                    height: NotchGeometry.notchHeight(for: screen)
                ),
                expandedContent: expandedContent,
                onQuit: onQuit
            )
        )
    }

    private func setupExpansionObserver() {
        expansionCancellable = windowState.$isExpanded
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, let screen = self.screen ?? NotchGeometry.preferredScreen() else { return }
                    self.refreshRootView(for: screen)
                }
            }
    }

    private func setupMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            let screenPoint = NSEvent.mouseLocation
            DispatchQueue.main.async { [weak self] in
                self?.handleGlobalPointerEvent(at: screenPoint)
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            guard event.keyCode == 53, self.windowState.isExpanded else { return event }
            self.windowState.isExpanded = false
            return nil
        }
    }

    private func handleGlobalPointerEvent(at point: CGPoint) {
        NotificationCenter.default.post(
            name: NotchGlobalPointerEvent.notificationName,
            object: NotchGlobalPointerEvent(screenPoint: point)
        )
        guard let hostingView else { return }
        if NotchGlobalHover.shouldExpand(
            isExpanded: windowState.isExpanded,
            point: point,
            windowFrame: frame,
            localRect: hostingView.hoverHitRect
        ) {
            guard globalHoverTask == nil else { return }
            globalHoverTask = Task { @MainActor [weak self] in
                defer { self?.globalHoverTask = nil }
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled,
                      let self,
                      let hostingView = self.hostingView,
                      NotchGlobalHover.shouldExpand(
                        isExpanded: self.windowState.isExpanded,
                        point: NSEvent.mouseLocation,
                        windowFrame: self.frame,
                        localRect: hostingView.hoverHitRect
                      ) else { return }
                self.windowState.isExpanded = true
            }
            return
        }

        globalHoverTask?.cancel()
        if windowState.isExpanded, !frame.contains(point) {
            windowState.collapseForPointerExit()
        }
    }

    private func setupScreenObserver() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateForCurrentScreen()
            }
        }
    }

    deinit {
        globalHoverTask?.cancel()
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
