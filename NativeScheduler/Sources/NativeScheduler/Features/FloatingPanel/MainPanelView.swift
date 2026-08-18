// NativeScheduler/Sources/NativeScheduler/Features/FloatingPanel/MainPanelView.swift
import Combine
import AppKit
import SwiftUI

@MainActor
final class MainPanelPresentationState: ObservableObject {
    @Published var isDaylineExpanded: Bool

    init(isDaylineExpanded: Bool) {
        self.isDaylineExpanded = isDaylineExpanded
    }
}

struct MainPanelView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var dayActivityStore: DayActivityStore
    @ObservedObject var timerVM: TimerViewModel
    @StateObject private var todoVM   = TodoViewModel()
    @State private var showSettings   = false
    @ObservedObject private var presentationState: MainPanelPresentationState
    private let daylineInteraction: DaylineInteractionModel
    private let showsLayoutDebugOverlay = false
    private let layoutProbe: (MainPanelLayoutProbe) -> Void
    private let reduceMotionOverride: Bool?

    @MainActor
    init(
        timerVM: TimerViewModel,
        dayActivityStore: DayActivityStore? = nil,
        initialDaylineExpanded: Bool = false,
        reduceMotionOverride: Bool? = nil,
        presentationState: MainPanelPresentationState? = nil,
        daylineInteraction: DaylineInteractionModel? = nil,
        layoutProbe: @escaping (MainPanelLayoutProbe) -> Void = { _ in }
    ) {
        self.timerVM = timerVM
        self.layoutProbe = layoutProbe
        self.reduceMotionOverride = reduceMotionOverride
        _presentationState = ObservedObject(wrappedValue: presentationState ?? MainPanelPresentationState(
            isDaylineExpanded: initialDaylineExpanded
        ))
        self.daylineInteraction = daylineInteraction ?? DaylineInteractionModel()
        let store = dayActivityStore ?? DayActivityStore(
                context: CoreDataStack.shared.viewContext,
                activeSessionID: timerVM.activeSessionID
            )
        store.setExpanded(initialDaylineExpanded)
        _dayActivityStore = StateObject(wrappedValue: store)
    }

    var body: some View {
        let snapshot = dayActivityStore.snapshot
        let isDaylineExpanded = presentationState.isDaylineExpanded

        GeometryReader { proxy in
            let layout = MainPanelLayoutMetrics(width: proxy.size.width, height: proxy.size.height, isDaylineExpanded: isDaylineExpanded)
            let _ = layoutProbe(MainPanelLayoutProbe(proposedSize: proxy.size, metrics: layout))
            let width = layout.width
            let height = layout.height
            let headerHeight = layout.headerHeight
            let horizontalPadding = layout.horizontalPadding
            let bottomPadding = layout.bottomPadding
            let contentWidth = layout.contentWidth
            let contentHeight = layout.contentHeight
            let columnSpacing = layout.columnSpacing
            let timerWidth = layout.timerWidth
            let rightWidth = layout.rightWidth
            let todoWidth = layout.todoWidth
            let stackSpacing = layout.stackSpacing
            let heatmapHeight = layout.heatmapHeight
            let timerHeight = layout.timerHeight
            let summaryWidth = layout.summaryWidth
            let summarySpacing = layout.summarySpacing

            VStack(spacing: 0) {
                panelHeader
                    .frame(height: headerHeight)

                HStack(alignment: .top, spacing: columnSpacing) {
                    TodoListView(
                        vm: todoVM,
                        density: isDaylineExpanded ? .condensed : .normal
                    )
                    .frame(width: todoWidth, height: contentHeight)

                    VStack(spacing: stackSpacing) {
                        DaylineView(
                            snapshot: snapshot,
                            windowSnapshot: dayActivityStore.windowSnapshot,
                            isExpanded: isDaylineExpanded,
                            hasFetchError: dayActivityStore.hasFetchError,
                            recoveryWarningCount: dayActivityStore.recoveryWarningCount,
                            reduceMotionOverride: reduceMotionOverride,
                            interactionModel: daylineInteraction,
                            onToggle: toggleDayline,
                            onRetry: { dayActivityStore.reload() }
                        )
                            .frame(width: rightWidth, height: heatmapHeight)

                        HStack(spacing: isDaylineExpanded ? summarySpacing : 0) {
                            if isDaylineExpanded {
                                TodayUsageSummaryView(snapshot: snapshot)
                                    .frame(width: summaryWidth, height: timerHeight)
                                    .transition(summaryTransition)
                            }

                            TimerView(
                                vm: timerVM,
                                isDaylineExpanded: isDaylineExpanded,
                                reduceMotionOverride: reduceMotionOverride
                            )
                                .frame(width: timerWidth, height: timerHeight)
                        }
                        .frame(width: rightWidth, height: timerHeight)
                    }
                    .frame(width: rightWidth, height: contentHeight, alignment: .bottom)
                }
                .overlay(alignment: .topLeading) {
                    daylineDisclosureRail
                        .frame(width: columnSpacing, height: contentHeight)
                        .offset(x: todoWidth)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, bottomPadding)
            }
            .frame(width: width, height: height)
            .overlay(alignment: .topLeading) {
                if showsLayoutDebugOverlay {
                    MainPanelDebugOverlay(
                        panelSize: proxy.size,
                        headerHeight: headerHeight,
                        horizontalPadding: horizontalPadding,
                        bottomPadding: bottomPadding,
                        contentWidth: contentWidth,
                        contentHeight: contentHeight,
                        todoWidth: todoWidth,
                        rightWidth: rightWidth,
                        heatmapHeight: heatmapHeight,
                        timerHeight: timerHeight
                    )
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.nsBackground)
        .onReceive(timerVM.$activeSessionID) { activeSessionID in
            dayActivityStore.setActiveSessionID(activeSessionID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .nativeSchedulerOpenSettings)) { _ in
            NotificationCenter.default.post(name: .nativeSchedulerInteractionLockChanged, object: true)
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            SettingsView {
                timerVM.refreshSettings()
                todoVM.reload()
            }
            .onDisappear {
                NotificationCenter.default.post(name: .nativeSchedulerInteractionLockChanged, object: false)
            }
        }
    }

    private var daylineToggleButton: some View {
        DaylineDisclosureButton(
            isExpanded: isDaylineExpanded,
            presentationState: presentationState,
            dayActivityStore: dayActivityStore,
            interactionModel: daylineInteraction,
            reduceMotion: reduceMotionOverride ?? reduceMotion
        )
        .accessibilitySortPriority(1)
    }

    private var daylineDisclosureRail: some View {
        ZStack {
            Rectangle()
                .fill(Color.nsBorder.opacity(0.76))
                .frame(width: 0.5)

            daylineToggleButton
                .frame(
                    width: SchedulerControl.minimumTarget,
                    height: SchedulerControl.minimumTarget
                )
                .background(Color.nsBackground)
        }
    }

    private var isDaylineExpanded: Bool { presentationState.isDaylineExpanded }

    // MARK: - Panel header

    private var panelHeader: some View {
        HStack(alignment: .center) {
            Text(todayDateString)
                .font(SchedulerType.monospacedContext)
                .foregroundColor(.nsTextTertiary)
                .lineLimit(1)
                .padding(.leading, SchedulerSpacing.cardInset)

            Spacer()
        }
    }

    private func toggleDayline() {
        let expanded = !isDaylineExpanded
        guard let animation = DaylineMotion.expansionAnimation(reduceMotion: reduceMotionOverride ?? reduceMotion) else {
            presentationState.isDaylineExpanded = expanded
            return
        }
        withAnimation(animation) {
            presentationState.isDaylineExpanded = expanded
        }
    }

    private var summaryTransition: AnyTransition {
        guard !(reduceMotionOverride ?? reduceMotion) else { return .identity }
        return .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .opacity
        )
    }

    // MARK: - Helpers

    private var todayDateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

private final class DaylineDisclosureNativeButton: NSButton {
    var presentationState: MainPanelPresentationState?
    weak var dayActivityStore: DayActivityStore?
    weak var interactionModel: DaylineInteractionModel?
    var reduceMotion = false
    private var isExpanded = false

    override var intrinsicContentSize: NSSize {
        NSSize(width: DaylineViewMetrics.minimumActionTarget, height: DaylineViewMetrics.minimumActionTarget)
    }

    @objc func activate(_ sender: Any?) {
        guard let presentationState else { return }
        let expanded = !presentationState.isDaylineExpanded
        guard let animation = DaylineMotion.expansionAnimation(reduceMotion: reduceMotion) else {
            presentationState.isDaylineExpanded = expanded
            interactionModel?.resetToCurrentActivity()
            dayActivityStore?.setExpanded(expanded)
            configure(isExpanded: expanded)
            return
        }
        withAnimation(animation) {
            presentationState.isDaylineExpanded = expanded
            interactionModel?.resetToCurrentActivity()
            dayActivityStore?.setExpanded(expanded)
        }
        configure(isExpanded: expanded)
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

    override func accessibilityPerformPress() -> Bool {
        if Thread.isMainThread {
            activate(nil)
        } else {
            DispatchQueue.main.sync { [weak self] in
                self?.activate(nil)
            }
        }
        return true
    }

    func configure(isExpanded: Bool) {
        self.isExpanded = isExpanded
        let label = DaylineViewControl.label(isExpanded: isExpanded)
        title = ""
        image = NSImage(
            systemSymbolName: DaylineViewControl.symbol(isExpanded: isExpanded),
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 10, weight: .medium))
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        contentTintColor = NSColor(Color.nsTextSecondary)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier("dayline.toggle")
        setAccessibilityLabel(label)
        setAccessibilityHelp(label)
    }

}

private struct DaylineDisclosureButton: NSViewRepresentable {
    let isExpanded: Bool
    let presentationState: MainPanelPresentationState
    let dayActivityStore: DayActivityStore
    let interactionModel: DaylineInteractionModel
    let reduceMotion: Bool

    @MainActor
    func makeNSView(context: Context) -> DaylineDisclosureNativeButton {
        let button = DaylineDisclosureNativeButton()
        configure(button)
        return button
    }

    @MainActor
    func updateNSView(_ button: DaylineDisclosureNativeButton, context: Context) {
        configure(button)
    }

    @MainActor
    private func configure(_ button: DaylineDisclosureNativeButton) {
        button.presentationState = presentationState
        button.dayActivityStore = dayActivityStore
        button.interactionModel = interactionModel
        button.reduceMotion = reduceMotion
        button.isBordered = false
        button.isTransparent = false
        button.focusRingType = .none
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor(Color.nsBackground).cgColor
        button.layer?.cornerRadius = SchedulerRadius.row
        button.layer?.borderWidth = 0
        button.configure(isExpanded: isExpanded)
        button.target = button
        button.action = #selector(DaylineDisclosureNativeButton.activate(_:))
    }
}

struct MainPanelLayoutProbe {
    let proposedSize: CGSize
    let metrics: MainPanelLayoutMetrics
}

struct MainPanelLayoutMetrics {
    let width: CGFloat
    let height: CGFloat
    let headerHeight: CGFloat
    let horizontalPadding: CGFloat
    let bottomPadding: CGFloat
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    let columnSpacing: CGFloat
    let timerWidth: CGFloat
    let rightWidth: CGFloat
    let todoWidth: CGFloat
    let collapsedStackSpacing: CGFloat
    let expandedStackSpacing: CGFloat
    let stackSpacing: CGFloat
    let collapsedHeatmapHeight: CGFloat
    let expandedHeatmapHeight: CGFloat
    let heatmapHeight: CGFloat
    let collapsedToggleHeight: CGFloat
    let expandedToggleHeight: CGFloat
    let toggleHeight: CGFloat
    let collapsedTimerHeight: CGFloat
    let expandedTimerHeight: CGFloat
    let timerHeight: CGFloat
    let summaryWidth: CGFloat
    let summarySpacing: CGFloat

    init(width: CGFloat, height: CGFloat, isDaylineExpanded: Bool) {
        self.width = width
        self.height = height
        headerHeight = max(28, min(36, height * 0.09))
        horizontalPadding = max(12, width * 0.018)
        bottomPadding = max(10, height * 0.03)
        contentWidth = width - (horizontalPadding * 2)
        contentHeight = height - headerHeight - bottomPadding
        columnSpacing = 24
        let availableBodyWidth = contentWidth - columnSpacing
        let collapsedTimerWidth = min(244, max(0, availableBodyWidth * 0.34))
        collapsedToggleHeight = 0
        expandedToggleHeight = 0
        collapsedStackSpacing = min(SchedulerSpacing.compact, max(0, contentHeight))
        expandedStackSpacing = min(SchedulerSpacing.sm, max(0, contentHeight))
        let collapsedStackContentHeight = max(0, contentHeight - collapsedStackSpacing)
        let expandedStackContentHeight = max(0, contentHeight - expandedStackSpacing)
        collapsedTimerHeight = min(148, max(0, collapsedStackContentHeight * 0.56))
        collapsedHeatmapHeight = max(0, collapsedStackContentHeight - collapsedTimerHeight)
        expandedTimerHeight = min(
            expandedStackContentHeight,
            min(92, max(78, expandedStackContentHeight * 0.32))
        )
        expandedHeatmapHeight = max(0, expandedStackContentHeight - expandedTimerHeight)
        stackSpacing = isDaylineExpanded ? expandedStackSpacing : collapsedStackSpacing
        heatmapHeight = isDaylineExpanded ? expandedHeatmapHeight : collapsedHeatmapHeight
        toggleHeight = isDaylineExpanded ? expandedToggleHeight : collapsedToggleHeight
        timerHeight = isDaylineExpanded ? expandedTimerHeight : collapsedTimerHeight
        rightWidth = isDaylineExpanded
            ? min(520, max(0, availableBodyWidth * 0.58))
            : collapsedTimerWidth
        todoWidth = max(0, availableBodyWidth - rightWidth)
        summarySpacing = min(SchedulerSpacing.sm, max(0, rightWidth - collapsedTimerWidth))
        timerWidth = isDaylineExpanded
            ? max(0, rightWidth - summarySpacing) / 2
            : collapsedTimerWidth
        summaryWidth = isDaylineExpanded
            ? timerWidth
            : max(0, rightWidth - timerWidth - summarySpacing)
    }
}

extension Notification.Name {
    static let nativeSchedulerOpenSettings = Notification.Name("NativeSchedulerOpenSettings")
    static let nativeSchedulerInteractionLockChanged = Notification.Name("NativeSchedulerInteractionLockChanged")
}

private struct MainPanelDebugOverlay: View {
    let panelSize: CGSize
    let headerHeight: CGFloat
    let horizontalPadding: CGFloat
    let bottomPadding: CGFloat
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    let todoWidth: CGFloat
    let rightWidth: CGFloat
    let heatmapHeight: CGFloat
    let timerHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(Color.cyan.opacity(0.9), lineWidth: 1)

            Rectangle()
                .stroke(Color.yellow.opacity(0.9), lineWidth: 1)
                .frame(height: headerHeight)

            Rectangle()
                .stroke(Color.green.opacity(0.9), lineWidth: 1)
                .frame(width: contentWidth, height: contentHeight)
                .offset(x: horizontalPadding, y: headerHeight)

            Rectangle()
                .stroke(Color.orange.opacity(0.9), lineWidth: 1)
                .frame(width: todoWidth, height: contentHeight)
                .offset(x: horizontalPadding, y: headerHeight)

            VStack(alignment: .leading, spacing: 3) {
                debugLabel("PANEL \(fmt(panelSize.width)) x \(fmt(panelSize.height))pt")
                debugLabel("HEADER \(fmt(headerHeight))pt")
                debugLabel("CONTENT \(fmt(contentWidth)) x \(fmt(contentHeight))pt")
                debugLabel("TODO \(fmt(todoWidth)) x \(fmt(contentHeight))pt")
                debugLabel("RIGHT \(fmt(rightWidth))pt, HEAT \(fmt(heatmapHeight))pt, TIMER \(fmt(timerHeight))pt")
                debugLabel("PAD x \(fmt(horizontalPadding))pt, bottom \(fmt(bottomPadding))pt")
            }
            .padding(6)
        }
    }

    private func debugLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func fmt(_ value: CGFloat) -> String {
        String(format: "%.0f", value)
    }
}
