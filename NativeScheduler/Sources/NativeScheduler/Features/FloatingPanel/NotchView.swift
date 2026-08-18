import AppKit
import SwiftUI

struct NotchView: View {
    @ObservedObject var windowState: NotchWindowState
    @ObservedObject var timerState: NotchTimerState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let notchSize: CGSize
    let expandedContent: AnyView
    let onQuit: () -> Void
    let reduceMotionOverride: Bool?

    @State private var isHovering = false

    init(
        windowState: NotchWindowState,
        timerState: NotchTimerState,
        notchSize: CGSize,
        expandedContent: AnyView,
        onQuit: @escaping () -> Void,
        reduceMotionOverride: Bool? = nil
    ) {
        self.windowState = windowState
        self.timerState = timerState
        self.notchSize = notchSize
        self.expandedContent = expandedContent
        self.onQuit = onQuit
        self.reduceMotionOverride = reduceMotionOverride
    }

    private let expandedContentHorizontalPadding: CGFloat = 20
    private let mainPanelHorizontalPadding: CGFloat = 14
    private var isExpanded: Bool { windowState.isExpanded }
    private var shouldReduceMotion: Bool { reduceMotionOverride ?? reduceMotion }

    private var shellMenuTopOffset: CGFloat {
        NotchGeometry.shellMenuTopOffset(notchHeight: notchSize.height)
    }

    private var panelWidth: CGFloat {
        if isExpanded {
            return NotchGeometry.expandedPanelWidth
        }

        return NotchGeometry.idleShellWidth(
            notchWidth: notchSize.width,
            showsProgress: timerState.snapshot.isRunning
        )
    }

    private var panelHeight: CGFloat {
        isExpanded ? NotchGeometry.expandedPanelHeight : NotchGeometry.idleShellHeight(notchHeight: notchSize.height)
    }

    private var panelLeadingPadding: CGFloat {
        if isExpanded { return 0 }
        return max(0, NotchGeometry.idleShellMinX(boundsWidth: NotchGeometry.expandedPanelWidth, notchWidth: notchSize.width))
    }

    private var topRadius: CGFloat {
        isExpanded ? NotchGeometry.cornerRadiusOpen.top : NotchGeometry.cornerRadiusClosed.top
    }

    private var bottomRadius: CGFloat {
        isExpanded ? NotchGeometry.cornerRadiusOpen.bottom : NotchGeometry.cornerRadiusClosed.bottom
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            growingPanel
                .padding(.leading, panelLeadingPadding)
                .animation(isExpanded ? NotchAnimation.expand : NotchAnimation.collapse, value: isExpanded)
                .animation(NotchAnimation.expand, value: timerState.snapshot.isRunning)
                .animation(NotchAnimation.hover, value: isHovering)
        }
        .padding(.bottom, NotchGeometry.shadowPadding)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(NotchAnimation.hover) { isHovering = hovering }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private var growingPanel: some View {
        ZStack(alignment: .top) {
            Color.black

            if isExpanded {
                expandedContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, expandedContentHorizontalPadding)
                    .padding(.top, notchSize.height + NotchGeometry.expandedContentTopSpacing)
                    .padding(.bottom, NotchGeometry.expandedContentBottomSpacing)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeIn(duration: 0.10).delay(0.18)),
                        removal: .opacity.animation(.easeOut(duration: 0.07))
                    ))

                shellMenu
                    .padding(.top, shellMenuTopOffset)
                    .padding(.trailing, expandedContentHorizontalPadding + mainPanelHorizontalPadding)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
            } else if timerState.snapshot.isRunning {
                timerActivityMark
                    .padding(.top, 8)
                    .padding(.trailing, 14)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .transition(.opacity.animation(.easeInOut(duration: 0.16)))
            }
        }
        .frame(width: panelWidth, height: panelHeight)
        .clipShape(NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius))
        .overlay {
            if timerState.completionEffect.isActive {
                TimelineView(.animation(
                    minimumInterval: 1.0 / 60.0,
                    paused: shouldReduceMotion
                )) { context in
                    CompletionBorderView(
                        topCornerRadius: topRadius,
                        bottomCornerRadius: bottomRadius,
                        opacity: timerState.completionEffect.renderedOpacity(
                            at: context.date,
                            reduceMotion: shouldReduceMotion
                        )
                    )
                }
                .accessibilityHidden(true)
            }
        }
        .shadow(
            color: .black.opacity(isExpanded ? 0.65 : (isHovering ? 0.40 : 0)),
            radius: 10, x: 0, y: 4
        )
        .contentShape(Rectangle())
        .overlay(alignment: .topLeading) {
            if !isExpanded {
                Button {
                    windowState.isExpanded = true
                } label: {
                    Color.clear
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open NativeScheduler panel")
                .accessibilityValue(timerState.snapshot.accessibilityStatus)
                .accessibilityHint("Show timer and task controls")
            }
        }
    }

    @ViewBuilder
    private var timerActivityMark: some View {
        switch timerState.snapshot.activity {
        case .idle:
            EmptyView()
        case .determinateCountdown:
            progressRing(size: 18, lineWidth: 2.5)
        case .activeCountUp:
            countUpStopwatch(size: 18)
        }
    }

    private func countUpStopwatch(size: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: shouldReduceMotion)) { context in
            let presentation = NotchCountUpBreathing.presentation(
                elapsed: timerState.countUpBreathingElapsed(at: context.date),
                reduceMotion: shouldReduceMotion
            )
            Image(systemName: "stopwatch")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: timerState.snapshot.categoryColorHex))
                .scaleEffect(presentation.scale)
                .opacity(presentation.opacity)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func progressRing(size: CGFloat, lineWidth: CGFloat) -> some View {
        let progress = max(0, min(timerState.snapshot.progress, 1))
        let categoryColor = Color(hex: timerState.snapshot.categoryColorHex)

        return ZStack {
            Circle()
                .stroke(categoryColor.opacity(0.18), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(categoryColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var shellMenu: some View {
        ShellMenuButton(windowState: windowState, onQuit: onQuit)
            .frame(
                width: NotchGeometry.shellMenuButtonSize,
                height: NotchGeometry.shellMenuButtonSize
            )
    }
}

private final class CompletionBorderLayerView: NSView {
    private let strokeLayer = CAShapeLayer()
    private var topCornerRadius: CGFloat = 0
    private var bottomCornerRadius: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
        strokeLayer.fillColor = NSColor.clear.cgColor
        strokeLayer.strokeColor = nil
        strokeLayer.isHidden = true
        strokeLayer.lineWidth = 2
        layer?.addSublayer(strokeLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func update(
        topCornerRadius: CGFloat,
        bottomCornerRadius: CGFloat,
        opacity: Double
    ) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        needsLayout = true

        let isVisible = opacity > 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strokeLayer.removeAllAnimations()
        strokeLayer.strokeColor = isVisible ? NSColor.systemRed.cgColor : nil
        strokeLayer.isHidden = !isVisible
        strokeLayer.opacity = Float(opacity)
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strokeLayer.frame = bounds
        strokeLayer.path = NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
        .inset(by: 1)
        .path(in: bounds)
        .cgPath
        CATransaction.commit()
    }
}

private struct CompletionBorderView: NSViewRepresentable {
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat
    let opacity: Double

    func makeNSView(context: Context) -> CompletionBorderLayerView {
        CompletionBorderLayerView(frame: .zero)
    }

    func updateNSView(_ view: CompletionBorderLayerView, context: Context) {
        view.update(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius,
            opacity: opacity
        )
    }
}

final class ShellMenuNativeButton: NSButton {
    override var intrinsicContentSize: NSSize {
        NSSize(
            width: NotchGeometry.shellMenuButtonSize,
            height: NotchGeometry.shellMenuButtonSize
        )
    }

    override func mouseDown(with event: NSEvent) {
        performClick(nil)
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 36 || event.keyCode == 49 else {
            super.keyDown(with: event)
            return
        }
        performClick(nil)
    }
}

struct ShellMenuButton: NSViewRepresentable {
    let windowState: NotchWindowState
    let onQuit: () -> Void

    @MainActor
    final class Coordinator: NSObject, NSMenuDelegate {
        let windowState: NotchWindowState
        let onQuit: () -> Void
        weak var button: NSButton?

        init(windowState: NotchWindowState, onQuit: @escaping () -> Void) {
            self.windowState = windowState
            self.onQuit = onQuit
        }

        @objc func openMenu(_ sender: Any?) {
            guard let button = button else { return }
            button.menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
        }

        @objc func settingsSelected() {
            NotificationCenter.default.post(name: .nativeSchedulerOpenSettings, object: nil)
        }

        @objc func quitSelected() {
            onQuit()
        }

        func menuWillOpen(_ menu: NSMenu) {
            windowState.beginShellMenuInteraction()
        }

        func menuDidClose(_ menu: NSMenu) {
            windowState.endShellMenuInteraction()
            guard let window = button?.window,
                  !window.frame.contains(NSEvent.mouseLocation) else { return }
            windowState.collapseForPointerExit()
        }
    }

    @MainActor
    func makeCoordinator() -> Coordinator {
        Coordinator(windowState: windowState, onQuit: onQuit)
    }

    @MainActor
    func makeNSView(context: Context) -> ShellMenuNativeButton {
        Self.configureButton(ShellMenuNativeButton(), coordinator: context.coordinator)
    }

    @MainActor
    static func configureButton(
        _ button: ShellMenuNativeButton,
        coordinator: Coordinator
    ) -> ShellMenuNativeButton {
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.14).cgColor
        button.layer?.cornerRadius = 11
        button.image = Self.makeGearImage()
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = NSColor(Color.nsTextSecondary)
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel("Shell menu")
        button.setAccessibilityHelp("Open options menu")
        button.target = coordinator
        button.action = #selector(Coordinator.openMenu(_:))

        let menu = NSMenu()
        menu.delegate = coordinator
        let settings = NSMenuItem(title: "Settings", action: #selector(Coordinator.settingsSelected), keyEquivalent: "")
        settings.target = coordinator
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit NativeScheduler", action: #selector(Coordinator.quitSelected), keyEquivalent: "")
        quit.target = coordinator
        menu.addItem(quit)
        button.menu = menu
        coordinator.button = button
        return button
    }

    @MainActor
    func updateNSView(_ button: ShellMenuNativeButton, context: Context) {
        context.coordinator.button = button
    }

    static func makeGearImage() -> NSImage {
        let image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Shell menu")!
        return image.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold)) ?? image
    }
}
