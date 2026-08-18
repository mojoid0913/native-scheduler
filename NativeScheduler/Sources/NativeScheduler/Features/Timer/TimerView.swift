// NativeScheduler/Sources/NativeScheduler/Features/Timer/TimerView.swift
import AppKit
import SwiftUI

enum TimerViewDensity {
    static let expandedTimeBoxHeight: CGFloat = 48
    static let expandedPrimaryRowHeight: CGFloat = 60
    static let expandedRowGap: CGFloat = 4
    static let expandedSecondaryRowHeight: CGFloat = 24
    static let expandedTopInset: CGFloat = 3
    static let expandedBottomInset: CGFloat = 9
    static let minimumActionTarget: CGFloat = 24
    static let expandedDurationActionTarget: CGFloat = 44
    static let meaningfulTextSize: CGFloat = 11
}

enum TimerAccessibilityMetrics {
    static let compactWarningFontSize: CGFloat = 10
    static let compactWarningScaleFactor: CGFloat = 1
}

struct TimerView: View {
    static let defaultCategoryColorHex = Color.resolvedCategoryHex(nil)

    @ObservedObject var vm: TimerViewModel
    let isDaylineExpanded: Bool
    let reduceMotionOverride: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var densityNamespace
    private let timerInputBoxSize = CGSize(width: 104, height: 62)
    private let primaryControlLeadingOffset: CGFloat = 5
    private let controlSpacing: CGFloat = 10

    // Seeded on .onAppear from vm.engine so UserDefaults-loaded defaults show correctly.
    @State private var durationInput: String = "25"
    @State private var endTimeInput: Date = Date()
    @State private var endTimeText: String = ""
    @State private var showsCategoryPopover = false
    @State private var newCategoryName = ""
    @State private var selectedCategoryColor = CategoryPalette.quickAdd[0]

    init(
        vm: TimerViewModel,
        isDaylineExpanded: Bool = false,
        reduceMotionOverride: Bool? = nil
    ) {
        self.vm = vm
        self.isDaylineExpanded = isDaylineExpanded
        self.reduceMotionOverride = reduceMotionOverride
    }

    var body: some View {
        GeometryReader { proxy in
            if isDaylineExpanded {
                expandedDensityLayout
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                centeredLayout
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .offset(y: -3)
            }
        }
        .animation(
            DaylineMotion.expansionAnimation(reduceMotion: shouldReduceMotion),
            value: isDaylineExpanded
        )
        .animation(shouldReduceMotion ? nil : .easeInOut(duration: 0.2), value: vm.engine.isRunning)
        .padding(.horizontal, SchedulerSpacing.cardInset)
        .padding(
            .top,
            isDaylineExpanded ? TimerViewDensity.expandedTopInset : SchedulerSpacing.compact
        )
        .padding(
            .bottom,
            isDaylineExpanded ? TimerViewDensity.expandedBottomInset : SchedulerSpacing.compact
        )
        .schedulerCardSurface()
        .onAppear {
            syncInputsFromEngine()
        }
    }

    private var centeredLayout: some View {
        VStack(alignment: .center, spacing: SchedulerSpacing.compact) {
            primaryTimeControl
                .frame(maxWidth: .infinity, alignment: .center)
                .offset(x: primaryControlLeadingOffset)
                .matchedGeometryEffect(
                    id: "timer.primary-controls",
                    in: densityNamespace,
                    properties: .frame,
                    isSource: !isDaylineExpanded
                )

            if vm.recordingError != nil {
                expandedSecondaryControls
            } else {
                HStack(spacing: controlSpacing) {
                    animatedCategorySelector

                    animatedModeToggle
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var expandedDensityLayout: some View {
        VStack(alignment: .center, spacing: TimerViewDensity.expandedRowGap) {
            expandedPrimaryTimeControl
                .frame(height: TimerViewDensity.expandedPrimaryRowHeight)
                .matchedGeometryEffect(
                    id: "timer.primary-controls",
                    in: densityNamespace,
                    properties: .frame,
                    isSource: !isDaylineExpanded
                )

            expandedSecondaryControls
                .frame(height: TimerViewDensity.expandedSecondaryRowHeight)
        }
        .overlay {
            Color.clear
                .accessibilityElement()
                .accessibilityLabel("Expanded timer content")
                .accessibilityIdentifier("timer.expanded.content")
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var expandedPrimaryTimeControl: some View {
        if vm.engine.isRunning || vm.engine.isPaused {
            HStack(spacing: 9) {
                countdownBox(
                    size: CGSize(width: timerInputBoxSize.width, height: TimerViewDensity.expandedTimeBoxHeight),
                    fontSize: 26,
                    cornerRadius: 8
                )
                controlButtons
            }
            .frame(height: TimerViewDensity.expandedPrimaryRowHeight)
        } else {
            switch vm.engine.mode {
            case .duration:
                expandedDurationPicker
            case .endTime:
                expandedEndTimePicker
            case .countUp:
                expandedCountUpPicker
            }
        }
    }

    @ViewBuilder
    private var expandedSecondaryControls: some View {
        if let error = vm.recordingError {
            if vm.canRetryFinalization {
                Button(action: vm.retryFinalization) {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, minHeight: TimerViewDensity.minimumActionTarget)
                        .overlay {
                            Label("Retry recording save", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                                .font(.system(size: TimerViewDensity.meaningfulTextSize, weight: .semibold))
                                .foregroundColor(.daylineError)
                                .lineLimit(1)
                                .allowsHitTesting(false)
                        }
                }
                .buttonStyle(.plain)
                .help(error)
                .accessibilityLabel("\(error) Retry recording save")
                .accessibilityIdentifier("timer.recording.retry")
            } else {
                Label("Recording save error", systemImage: "exclamationmark.triangle")
                    .font(.system(size: TimerViewDensity.meaningfulTextSize, weight: .semibold))
                    .foregroundColor(.daylineError)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: TimerViewDensity.minimumActionTarget)
                    .help(error)
                    .accessibilityLabel(error)
            }
        } else {
            HStack(spacing: 8) {
                animatedCategorySelector
                    .frame(width: 88, alignment: .leading)
                    .clipped()
                animatedModeToggle
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("timer.secondary.controls")
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 8)
        }
    }

    private var animatedCategorySelector: some View {
        categorySelector
            .matchedGeometryEffect(
                id: "timer.category-selector",
                in: densityNamespace,
                properties: .frame,
                isSource: !isDaylineExpanded
            )
    }

    private var animatedModeToggle: some View {
        modeToggle
            .matchedGeometryEffect(
                id: "timer.mode-toggle",
                in: densityNamespace,
                properties: .frame,
                isSource: !isDaylineExpanded
            )
    }

    @ViewBuilder
    private var primaryTimeControl: some View {
        if vm.engine.isRunning || vm.engine.isPaused {
            activeTimerControl
        } else {
            switch vm.engine.mode {
            case .duration:
                durationPicker
            case .endTime:
                endTimePicker
            case .countUp:
                countUpPicker
            }
        }
    }

    private var activeTimerControl: some View {
        HStack(spacing: 9) {
            runningCountdownBox
                .frame(width: timerInputBoxSize.width, height: timerInputBoxSize.height)
            controlButtons
        }
        .frame(height: timerInputBoxSize.height + 18)
        .padding(.vertical, 1)
    }

    private var runningCountdownBox: some View {
        countdownBox(size: timerInputBoxSize, fontSize: 30, cornerRadius: 10)
    }

    private func countdownBox(size: CGSize, fontSize: CGFloat, cornerRadius: CGFloat) -> some View {
        Text(activeCountdownString)
            .font(.system(size: fontSize, weight: .light, design: .monospaced))
            .foregroundColor(vm.engine.isFinished ? .red : .nsTextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: size.width, height: size.height)
            .background(Color.nsBorder.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(themeColor.opacity(0.16), lineWidth: 2)
            }
            .overlay {
                TimerCountdownBorder(progress: countdownProgress, cornerRadius: cornerRadius)
                    .stroke(themeColor, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .animation(shouldReduceMotion ? nil : .linear(duration: 0.18), value: vm.engine.remaining)
            }
            .animation(.none, value: vm.engine.remaining)
            .accessibilityValue(activeCountdownString)
            .accessibilityLabel(vm.engine.mode == .countUp ? "Elapsed time" : "Time remaining")
    }

    private var expandedDurationPicker: some View {
        HStack(spacing: 9) {
            HStack(spacing: 0) {
                expandedDurationAdjustButton(
                    icon: "chevron.left",
                    isEnabled: durationMinutes > 5,
                    label: "Decrease duration",
                    identifier: "timer.duration.decrease"
                ) {
                    setDuration(durationMinutes - 5)
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(durationMinutes)")
                        .font(.system(size: 26, weight: .light, design: .monospaced))
                        .foregroundColor(.nsTextPrimary)
                    Text("min")
                        .font(.system(size: TimerViewDensity.meaningfulTextSize, weight: .medium))
                        .foregroundColor(.nsTextSecondary)
                }
                .lineLimit(1)
                .frame(minWidth: 56, maxHeight: TimerViewDensity.expandedTimeBoxHeight)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(durationMinutes) minutes")
                .accessibilityIdentifier("timer.duration.value")

                expandedDurationAdjustButton(
                    icon: "chevron.right",
                    isEnabled: durationMinutes < 60,
                    label: "Increase duration",
                    identifier: "timer.duration.increase"
                ) {
                    setDuration(durationMinutes + 5)
                }
            }
            .frame(height: TimerViewDensity.expandedTimeBoxHeight)
            .background(Color.nsBorder.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            controlButtons
        }
        .frame(height: TimerViewDensity.expandedPrimaryRowHeight)
    }

    private func expandedDurationAdjustButton(
        icon: String,
        isEnabled: Bool,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isEnabled ? .nsTextSecondary.opacity(0.85) : .nsTextSecondary.opacity(0.22))
                .frame(
                    width: TimerViewDensity.expandedDurationActionTarget,
                    height: TimerViewDensity.expandedDurationActionTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var expandedCountUpPicker: some View {
        HStack(spacing: 9) {
            countdownBox(
                size: CGSize(width: timerInputBoxSize.width, height: TimerViewDensity.expandedTimeBoxHeight),
                fontSize: 26,
                cornerRadius: 8
            )
            controlButtons
        }
        .frame(height: TimerViewDensity.expandedPrimaryRowHeight)
    }

    private var expandedEndTimePicker: some View {
        HStack(spacing: 9) {
            VStack(spacing: 0) {
                MaskedTimeTextField(text: $endTimeText) {
                    applyEndTimeText()
                }
                .frame(width: timerInputBoxSize.width, height: TimerViewDensity.expandedTimeBoxHeight)
                .background(Color.nsBorder.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(endTimeWarningColor ?? Color.clear, lineWidth: 1.4)
                }
                .onChange(of: endTimeText) { _, newValue in
                    if let resolved = resolveEndTime(from: newValue) {
                        setEndTime(resolved, updateText: false)
                    }
                }
                .onDisappear {
                    applyEndTimeText()
                }
                .accessibilityLabel("End time")

                Text(endTimeWarning?.message ?? " ")
                    .font(.system(size: TimerViewDensity.meaningfulTextSize, weight: .medium))
                    .foregroundColor(endTimeWarningColor ?? .clear)
                    .lineLimit(1)
                    .frame(height: TimerViewDensity.expandedPrimaryRowHeight - TimerViewDensity.expandedTimeBoxHeight)
                    .accessibilityHidden(endTimeWarning == nil)
            }
            .frame(width: timerInputBoxSize.width, height: TimerViewDensity.expandedPrimaryRowHeight)

            controlButtons
        }
        .frame(height: TimerViewDensity.expandedPrimaryRowHeight)
    }

    private var durationPicker: some View {
        expandedDurationPicker
            .padding(.vertical, 1)
    }

    private var endTimePicker: some View {
        HStack(spacing: 9) {
            ZStack {
                MaskedTimeTextField(text: $endTimeText) {
                    applyEndTimeText()
                }
                    .frame(width: timerInputBoxSize.width, height: timerInputBoxSize.height)
                    .background(Color.nsBorder.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(endTimeWarningColor ?? Color.clear, lineWidth: 1.4)
                    }
                    .overlay(alignment: .bottom) {
                        if let warning = endTimeWarning {
                            HStack(spacing: 3) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(
                                        .system(
                                            size: TimerAccessibilityMetrics.compactWarningFontSize,
                                            weight: .bold
                                        )
                                    )
                                Text(warning.message)
                                    .font(
                                        .system(
                                            size: TimerAccessibilityMetrics.compactWarningFontSize,
                                            weight: .medium
                                        )
                                    )
                            }
                            .foregroundColor(warning.color)
                            .lineLimit(1)
                            .minimumScaleFactor(
                                TimerAccessibilityMetrics.compactWarningScaleFactor
                            )
                            .padding(.horizontal, 4)
                            .padding(.bottom, 3)
                        }
                    }
                    .onChange(of: endTimeText) { _, newValue in
                        if let resolved = resolveEndTime(from: newValue) {
                            setEndTime(resolved, updateText: false)
                        }
                    }
                    .onDisappear {
                        applyEndTimeText()
                    }
                    .accessibilityLabel("End time")
            }
            .frame(width: timerInputBoxSize.width, height: timerInputBoxSize.height + 18)

            controlButtons
        }
        .padding(.vertical, 1)
    }

    private var countUpPicker: some View {
        HStack(spacing: 9) {
            countdownBox(size: timerInputBoxSize, fontSize: 30, cornerRadius: 10)
                .frame(width: timerInputBoxSize.width, height: timerInputBoxSize.height)
            controlButtons
        }
        .frame(height: timerInputBoxSize.height + 18)
        .padding(.vertical, 1)
    }

    private var modeToggle: some View {
        Button {
            toggleMode()
        } label: {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.nsBorder.opacity(0.9))

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.nsChevron)
                    .frame(width: 30)
                    .padding(2)
                    .offset(x: CGFloat(modeIndex) * 32)

                HStack(spacing: 0) {
                    ForEach(TimerMode.allCases, id: \.rawValue) { mode in
                        timerModeIcon(mode)
                    }
                }
            }
            .frame(width: 96, height: isDaylineExpanded ? TimerViewDensity.expandedSecondaryRowHeight : 26)
        }
        .buttonStyle(.plain)
        .disabled(isTimerActiveOrPaused)
        .animation(shouldReduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.86), value: vm.engine.mode)
        .accessibilityLabel("Timer mode: \(vm.engine.mode.label)")
        .accessibilityValue(TimerMode.allCases.map(\.label).joined(separator: ", "))
        .accessibilityIdentifier("timer.mode")
        .accessibilityHint(
            isTimerActiveOrPaused
                ? "Timer mode cannot be changed while the timer is active."
                : "Switch timer mode."
        )
    }

    private func timerModeIcon(_ mode: TimerMode) -> some View {
        Image(systemName: mode.iconName)
            .font(.system(size: 12, weight: .semibold))
            .imageScale(.small)
            .foregroundColor(vm.engine.mode == mode ? .black : .nsTextSecondary)
            .frame(
                width: 32,
                height: isDaylineExpanded ? TimerViewDensity.expandedSecondaryRowHeight : 26,
                alignment: .center
            )
            .contentShape(Rectangle())
    }

    private var categorySelector: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(themeColor)
                    .frame(width: 13, height: 13)
                Text(vm.selectedCategory?.name ?? "Default")
                    .font(.system(size: 11))
                    .foregroundColor(.nsTextPrimary)
                    .lineLimit(1)
            }
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .frame(minHeight: TimerViewDensity.minimumActionTarget)
            .background(Color.nsBorder)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .allowsHitTesting(false)
            .overlay {
                CategorySelectorNativeButton(
                    label: "Select category: \(vm.selectedCategory?.name ?? "Default")",
                    isPresented: $showsCategoryPopover,
                    content: AnyView(categoryPopover)
                )
            }
            .onDisappear {
                guard showsCategoryPopover else { return }
                showsCategoryPopover = false
                NotificationCenter.default.post(name: .nativeSchedulerCloseCategoryPopover, object: nil)
            }
            .accessibilityLabel("Select category: \(vm.selectedCategory?.name ?? "Default")")
        }
    }

    private var categoryPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Categories")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.nsTextPrimary)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 5) {
                categoryOption(
                    name: "Default",
                    colorHex: Self.defaultCategoryColorHex,
                    isSelected: vm.selectedCategory == nil,
                    accessibilityIdentifier: "timer.category.option.Default"
                ) {
                    vm.changeCategory(to: nil)
                    NotificationCenter.default.post(name: .nativeSchedulerCloseCategoryPopover, object: nil)
                }

                ForEach(vm.categories, id: \.objectID) { category in
                    categoryOption(
                        name: category.name,
                        colorHex: category.colorHex,
                        isSelected: vm.selectedCategory?.objectID == category.objectID,
                        accessibilityIdentifier: "timer.category.option.\(category.name)"
                    ) {
                        vm.changeCategory(to: category)
                        NotificationCenter.default.post(name: .nativeSchedulerCloseCategoryPopover, object: nil)
                    }
                }
            }

            Divider().background(Color.nsBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Add Category")
                    .font(SchedulerType.metadata)
                    .foregroundColor(.nsTextTertiary)
                    .lineLimit(1)

                TextField("Category name", text: $newCategoryName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.nsTextPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.nsBorder.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: SchedulerRadius.row, style: .continuous))
                    .accessibilityIdentifier("timer.category.name")

                HStack(spacing: 6) {
                    ForEach(CategoryPalette.quickAdd, id: \.self) { colorHex in
                        Button {
                            selectedCategoryColor = colorHex
                        } label: {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hex: colorHex))
                                .frame(width: 18, height: 18)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(
                                            selectedCategoryColor == colorHex ? Color.nsTextPrimary : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Category color \(colorHex)")
                        .accessibilityIdentifier("timer.category.color.\(colorHex)")
                    }
                }

                Button("Add") {
                    if let category = vm.addCategory(name: newCategoryName, colorHex: selectedCategoryColor) {
                        vm.changeCategory(to: category)
                        newCategoryName = ""
                        NotificationCenter.default.post(name: .nativeSchedulerCloseCategoryPopover, object: nil)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .nsTextSecondary : .black)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.nsBorder : Color.nsChevron)
                .clipShape(RoundedRectangle(cornerRadius: SchedulerRadius.row, style: .continuous))
                .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("timer.category.add")
            }
        }
        .padding(12)
        .frame(width: 220)
        .background(Color.nsSurfaceElevated)
    }

    private func categoryOption(
        name: String,
        colorHex: String,
        isSelected: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: colorHex))
                    .frame(width: 12, height: 12)

                Text(name)
                    .font(.system(size: 11))
                    .foregroundColor(.nsTextPrimary)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.nsChevron)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: TimerViewDensity.minimumActionTarget)
            .background(isSelected ? Color.nsBorder.opacity(0.75) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: SchedulerRadius.row, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAction {
            action()
        }
    }

    private var controlButtons: some View {
        HStack(spacing: vm.engine.isPaused ? 2 : 6) {
            if vm.engine.isRunning {
                controlButton(
                    icon: "stop.fill",
                    label: "Stop",
                    action: {
                        performLocked {
                            vm.pause()
                        }
                    }
                )
            } else if vm.engine.isPaused {
                controlButton(
                    icon: "play.fill",
                    label: "Resume",
                    action: {
                        performLocked {
                            vm.start()
                        }
                    }
                )

                controlButton(
                    icon: "arrow.counterclockwise",
                    label: "Reset",
                    action: {
                        performLocked {
                            vm.stop()
                        }
                    }
                )
            } else {
                controlButton(
                    icon: "play.fill",
                    label: "Start",
                    isEnabled: canStartTimer,
                    action: {
                        performLocked {
                            guard canStartTimer else { return }
                            vm.start()
                        }
                    }
                )
            }
        }
    }

    private var themeColor: Color {
        Color(hex: vm.themeColorHex)
    }

    private var shouldReduceMotion: Bool {
        reduceMotionOverride ?? reduceMotion
    }

    private var isTimerActiveOrPaused: Bool {
        vm.engine.isRunning || vm.engine.isPaused
    }

    private var progressSessionTotal: TimeInterval {
        if vm.engine.sessionTotal > 0 {
            return vm.engine.sessionTotal
        }

        switch vm.engine.mode {
        case .duration:
            return vm.engine.durationSeconds
        case .endTime:
            return max(vm.engine.remaining, vm.engine.targetEndTime.timeIntervalSinceNow)
        case .countUp:
            return 0
        }
    }

    private var countdownProgress: Double {
        TimerProgress.fraction(
            remaining: vm.engine.remaining,
            sessionTotal: progressSessionTotal,
            isRunning: isTimerActiveOrPaused
        )
    }

    private var activeCountdownString: String {
        vm.engine.remaining.countdownDisplayString
    }

    private var durationMinutes: Int {
        max(5, Int(round(vm.engine.durationSeconds / 60)))
    }

    private var canStartTimer: Bool {
        guard !vm.engine.isRunning, !vm.canRetryFinalization else { return false }
        guard vm.engine.mode == .endTime else { return true }
        let now = Date()
        guard let resolved = resolveEndTime(from: endTimeText, now: now) else { return false }
        return resolved > now && !EndTimeResolver.isCurrentMinute(resolved, now: now)
    }

    private var isEndTimeInvalid: Bool {
        endTimeWarning == .invalid
    }

    private var endTimeWarning: EndTimeWarning? {
        let now = Date()
        guard vm.engine.mode == .endTime else { return nil }
        guard !endTimeText.contains("_") else { return nil }
        guard let resolved = resolveEndTime(from: endTimeText, now: now) else { return .invalid }

        if EndTimeResolver.isCurrentMinute(resolved, now: now) {
            return .invalid
        }

        if EndTimeResolver.resolvesAfterToday(resolved, now: now) {
            return .tomorrow
        }

        return nil
    }

    private var endTimeWarningColor: Color? {
        endTimeWarning?.color
    }

    private var endTimeDisplay: String {
        formatEndTime(endTimeInput)
    }

    private func setMode(_ mode: TimerMode) {
        guard !isTimerActiveOrPaused else { return }
        vm.engine.mode = mode
        if mode == .endTime {
            seedEndTimeFromNow()
        }
        vm.reset()
    }

    private var modeIndex: Int {
        TimerMode.allCases.firstIndex(of: vm.engine.mode) ?? 0
    }

    private func toggleMode() {
        let modes = TimerMode.allCases
        setMode(modes[(modeIndex + 1) % modes.count])
    }

    private func setDuration(_ minutes: Int) {
        let snapped = min(60, max(5, Int((Double(minutes) / 5.0).rounded()) * 5))
        durationInput = "\(snapped)"
        vm.engine.durationSeconds = TimeInterval(snapped * 60)
        vm.reset()
    }

    private func setEndTime(_ date: Date, updateText: Bool = true) {
        endTimeInput = date
        if updateText {
            endTimeText = endTimeDisplay
        }
        vm.engine.targetEndTime = date
        if vm.engine.mode == .endTime {
            vm.engine.prepareEndTimeCountdown()
        } else {
            vm.reset()
        }
    }

    private func seedEndTimeFromNow() {
        let calendar = Calendar.current
        let now = Date()
        let currentMinute = calendar.dateInterval(of: .minute, for: now)?.start ?? now

        endTimeInput = currentMinute
        endTimeText = formatEndTime(currentMinute)
        vm.engine.targetEndTime = currentMinute
        vm.engine.prepareEndTimeCountdown()
    }

    private func syncInputsFromEngine() {
        let mins = Int(vm.engine.durationSeconds / 60)
        durationInput = "\(mins)"
        endTimeInput = vm.engine.targetEndTime
        endTimeText = formatEndTime(vm.engine.targetEndTime)

        guard !isTimerActiveOrPaused, vm.engine.mode == .endTime else { return }
        vm.engine.prepareEndTimeCountdown()
    }

    private func applyEndTimeText() {
        guard let resolved = resolveEndTime(from: endTimeText) else {
            return
        }
        setEndTime(resolved, updateText: false)
    }

    private func resolveEndTime(from text: String, now: Date = Date()) -> Date? {
        EndTimeResolver.resolve(text, now: now)
    }

    private func formatEndTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func performLocked(_ action: @escaping () -> Void) {
        NotificationCenter.default.post(name: .nativeSchedulerInteractionLockChanged, object: true)
        action()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NotificationCenter.default.post(name: .nativeSchedulerInteractionLockChanged, object: false)
        }
    }

    @ViewBuilder
    private func controlButton(
        icon: String,
        label: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: isDaylineExpanded ? 12 : (vm.engine.isPaused ? 14 : 16), weight: .semibold))
                .foregroundColor(isEnabled ? .nsTextPrimary : .nsTextSecondary.opacity(0.38))
                .frame(
                    width: isDaylineExpanded ? TimerViewDensity.minimumActionTarget : (vm.engine.isPaused ? 30 : 40),
                    height: isDaylineExpanded ? TimerViewDensity.minimumActionTarget : 40
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

private extension TimerMode {
    var iconName: String {
        switch self {
        case .duration:
            return "hourglass"
        case .endTime:
            return "clock"
        case .countUp:
            return "stopwatch"
        }
    }
}

private enum EndTimeWarning {
    case invalid
    case tomorrow

    var message: String {
        switch self {
        case .invalid:
            return "Invalid input"
        case .tomorrow:
            return "Count til tomorrow"
        }
    }

    var color: Color {
        switch self {
        case .invalid:
            return .red.opacity(0.92)
        case .tomorrow:
            return .orange.opacity(0.95)
        }
    }
}

struct EndTimeResolver {
    static func resolve(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard text.count == 5, text[text.index(text.startIndex, offsetBy: 2)] == ":" else { return nil }
        guard !text.contains("_") else { return nil }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init)

        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              ((0...23).contains(hour) || (hour == 24 && minute == 0)),
              (0...59).contains(minute)
        else { return nil }

        let startOfToday = calendar.startOfDay(for: now)
        guard let today = calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: startOfToday) else {
            return nil
        }

        let currentMinute = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        if today < currentMinute {
            return calendar.date(byAdding: .day, value: 1, to: today)
        }
        return today
    }

    static func isCurrentMinute(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let lhs = calendar.dateInterval(of: .minute, for: date)?.start ?? date
        let rhs = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        return lhs == rhs
    }

    static func resolvesAfterToday(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: date) > calendar.startOfDay(for: now)
    }
}

private struct MaskedTimeTextField: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void

    func makeNSView(context: Context) -> MaskedTimeInputView {
        let view = MaskedTimeInputView()
        view.onTextChange = { value in
            text = value
        }
        view.onCommit = onCommit
        view.setMaskedText(text)
        return view
    }

    func updateNSView(_ nsView: MaskedTimeInputView, context: Context) {
        nsView.onTextChange = { value in
            text = value
        }
        nsView.onCommit = onCommit
        if nsView.maskedText != text {
            nsView.setMaskedText(text)
        }
    }
}

struct EndTimeCaretResolver {
    enum ColonSide: Equatable {
        case before
        case after
    }

    struct Selection: Equatable {
        var position: Int
        var colonSide: ColonSide?
    }

    static func selection(at x: CGFloat, positions: [CGFloat]) -> Selection {
        let stops = visualStops(using: positions)
        let nearest = stops.enumerated().min { lhs, rhs in
            let lhsDistance = abs(lhs.element.x - x)
            let rhsDistance = abs(rhs.element.x - x)
            if lhsDistance == rhsDistance {
                return lhs.offset > rhs.offset
            }
            return lhsDistance < rhsDistance
        }
        guard let nearest else {
            return Selection(position: 0, colonSide: nil)
        }
        return nearest.element.selection
    }

    static func caretX(for position: Int, colonSide: ColonSide, positions: [CGFloat]) -> CGFloat {
        if position == 2 {
            return colonCaretX(side: colonSide, positions: positions)
        }
        let digitCenters = [positions[0], positions[1], positions[3], positions[4]]
        let leadingGap = (digitCenters[1] - digitCenters[0]) / 2
        let trailingGap = (digitCenters[3] - digitCenters[2]) / 2
        let stops = [
            digitCenters[0] - leadingGap,
            (digitCenters[0] + digitCenters[1]) / 2,
            colonCaretX(side: .after, positions: positions),
            (digitCenters[2] + digitCenters[3]) / 2,
            digitCenters[3] + trailingGap
        ]
        return stops[min(max(position, 0), stops.count - 1)]
    }

    private static func visualStops(using positions: [CGFloat]) -> [(selection: Selection, x: CGFloat)] {
        let digitCenters = [positions[0], positions[1], positions[3], positions[4]]
        let leadingGap = (digitCenters[1] - digitCenters[0]) / 2
        let trailingGap = (digitCenters[3] - digitCenters[2]) / 2
        return [
            (Selection(position: 0, colonSide: nil), digitCenters[0] - leadingGap),
            (Selection(position: 1, colonSide: nil), (digitCenters[0] + digitCenters[1]) / 2),
            (Selection(position: 2, colonSide: .before), colonCaretX(side: .before, positions: positions)),
            (Selection(position: 2, colonSide: .after), colonCaretX(side: .after, positions: positions)),
            (Selection(position: 3, colonSide: nil), (digitCenters[2] + digitCenters[3]) / 2),
            (Selection(position: 4, colonSide: nil), digitCenters[3] + trailingGap)
        ]
    }

    private static func colonCaretX(side: ColonSide, positions: [CGFloat]) -> CGFloat {
        let colonCenter = positions[2]
        let hourToMinuteSpan = positions[3] - positions[1]
        let offset = max(4, hourToMinuteSpan * 0.20)
        return side == .before ? colonCenter - offset : colonCenter + offset
    }
}

private final class MaskedTimeInputView: NSView {
    var onTextChange: ((String) -> Void)?
    var onCommit: (() -> Void)?

    private var digits: [Character?] = Array(repeating: nil, count: 4)
    private var caretPosition = 0
    private var colonCaretSide: EndTimeCaretResolver.ColonSide = .after
    private var showsCaret = true
    private var caretTimer: Timer?

    var maskedText: String {
        "\(displayCharacter(at: 0))\(displayCharacter(at: 1)):\(displayCharacter(at: 2))\(displayCharacter(at: 3))"
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setMaskedText(_ text: String) {
        let chars = Array(text)
        guard chars.count == 5, chars[2] == ":" else {
            digits = Array(repeating: nil, count: 4)
            caretPosition = 0
            colonCaretSide = .after
            needsDisplay = true
            return
        }

        let slots = [chars[0], chars[1], chars[3], chars[4]]
        digits = slots.map { $0.isNumber ? Optional($0) : nil }
        caretPosition = firstEmptySlot() ?? 4
        if caretPosition == 2 {
            colonCaretSide = .after
        }
        needsDisplay = true
    }

    func commit() {
        onCommit?()
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        startCaretBlink()
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        commit()
        stopCaretBlink()
        needsDisplay = true
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let selection = caretSelection(at: point.x)
        caretPosition = selection.position
        if let colonSide = selection.colonSide {
            colonCaretSide = colonSide
        }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if let chars = event.charactersIgnoringModifiers, let char = chars.first {
            if char.isNumber {
                let writeIndex = min(caretPosition, 3)
                digits[writeIndex] = char
                caretPosition = min(writeIndex + 1, 4)
                if caretPosition == 2 {
                    colonCaretSide = .after
                }
                emitChange()
                needsDisplay = true
                return
            }

            switch char {
            case "\u{7F}", "\u{08}":
                handleBackspace()
                return
            case "\u{03}":
                commit()
                return
            default:
                break
            }
        }

        switch event.keyCode {
        case 51:
            handleBackspace()
        case 117:
            if caretPosition <= 3 {
                digits[caretPosition] = nil
            }
            emitChange()
            needsDisplay = true
        case 123:
            caretPosition = max(0, caretPosition - 1)
            if caretPosition == 2 {
                colonCaretSide = .after
            }
            needsDisplay = true
        case 124:
            caretPosition = min(4, caretPosition + 1)
            if caretPosition == 2 {
                colonCaretSide = .after
            }
            needsDisplay = true
        case 36, 76:
            commit()
        default:
            break
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let chars = Array(maskedText)
        let positions = characterPositions()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 32, weight: .light)

        for index in chars.indices {
            let char = chars[index]
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: char == "_" ? NSColor.secondaryLabelColor : NSColor.labelColor
            ]
            let string = String(char) as NSString
            let size = string.size(withAttributes: attributes)
            let point = CGPoint(
                x: positions[index] - size.width / 2,
                y: bounds.midY - size.height / 2
            )
            string.draw(at: point, withAttributes: attributes)
        }

        if window?.firstResponder === self {
            drawCaret(using: positions)
        }
    }

    private func displayCharacter(at index: Int) -> Character {
        digits[index] ?? "_"
    }

    private func emitChange() {
        onTextChange?(maskedText)
    }

    private func handleBackspace() {
        guard caretPosition > 0 else {
            needsDisplay = true
            return
        }
        let deleteIndex = caretPosition - 1
        digits[deleteIndex] = nil
        caretPosition = deleteIndex
        if caretPosition == 2 {
            colonCaretSide = .after
        }
        emitChange()
        needsDisplay = true
    }

    private func firstEmptySlot() -> Int? {
        digits.firstIndex(where: { $0 == nil })
    }

    private func maskedCharacterIndex(forSlot index: Int) -> Int {
        index < 2 ? index : index + 1
    }

    private func drawCaret(using positions: [CGFloat]) {
        guard showsCaret else { return }
        let caretX = EndTimeCaretResolver.caretX(for: caretPosition, colonSide: colonCaretSide, positions: positions)
        let caretRect = CGRect(x: caretX, y: bounds.midY - 16, width: 2.6, height: 32)
        NSColor.labelColor.withAlphaComponent(0.86).setFill()
        caretRect.fill()
    }

    private func startCaretBlink() {
        stopCaretBlink()
        showsCaret = true
        caretTimer = Timer.scheduledTimer(withTimeInterval: 0.52, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.showsCaret.toggle()
                self.needsDisplay = true
            }
        }
    }

    private func stopCaretBlink() {
        caretTimer?.invalidate()
        caretTimer = nil
        showsCaret = true
    }

    private func characterPositions() -> [CGFloat] {
        let step: CGFloat = 18
        let colonGap: CGFloat = 7
        let totalWidth = (step * 4) + colonGap
        let start = bounds.midX - totalWidth / 2
        return [
            start + step * 0.5,
            start + step * 1.5,
            start + step * 2.0 + colonGap / 2,
            start + step * 2.5 + colonGap,
            start + step * 3.5 + colonGap
        ]
    }

    private func caretSelection(at x: CGFloat) -> EndTimeCaretResolver.Selection {
        EndTimeCaretResolver.selection(at: x, positions: characterPositions())
    }
}

private struct TimerCountdownBorder: Shape {
    var progress: Double
    var cornerRadius: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var fullPath = Path()
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let midX = rect.midX

        // Start at top-center and move counter-clockwise so progress visually
        // "turns left" around the countdown box.
        fullPath.move(to: CGPoint(x: midX, y: minY))
        fullPath.addLine(to: CGPoint(x: minX + radius, y: minY))
        fullPath.addQuadCurve(
            to: CGPoint(x: minX, y: minY + radius),
            control: CGPoint(x: minX, y: minY)
        )
        fullPath.addLine(to: CGPoint(x: minX, y: maxY - radius))
        fullPath.addQuadCurve(
            to: CGPoint(x: minX + radius, y: maxY),
            control: CGPoint(x: minX, y: maxY)
        )
        fullPath.addLine(to: CGPoint(x: maxX - radius, y: maxY))
        fullPath.addQuadCurve(
            to: CGPoint(x: maxX, y: maxY - radius),
            control: CGPoint(x: maxX, y: maxY)
        )
        fullPath.addLine(to: CGPoint(x: maxX, y: minY + radius))
        fullPath.addQuadCurve(
            to: CGPoint(x: maxX - radius, y: minY),
            control: CGPoint(x: maxX, y: minY)
        )
        fullPath.addLine(to: CGPoint(x: midX, y: minY))

        return fullPath.trimmedPath(from: 0, to: max(0, min(1, progress)))
    }
}

private final class CategorySelectorAppKitButton: NSButton {
    var onActivate: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 36 || event.keyCode == 49 else {
            super.keyDown(with: event)
            return
        }
        onActivate?()
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }
}

private struct CategorySelectorNativeButton: NSViewRepresentable {
    let label: String
    @Binding var isPresented: Bool
    let content: AnyView

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        var isPresented: Binding<Bool>
        var content: AnyView
        private var popover: NSPopover?
        private var closeObserver: NSObjectProtocol?
        private var isInteractionLocked = false
        private weak var presentingWindow: NSWindow?

        init(isPresented: Binding<Bool>, content: AnyView) {
            self.isPresented = isPresented
            self.content = content
            super.init()
            closeObserver = NotificationCenter.default.addObserver(
                forName: .nativeSchedulerCloseCategoryPopover,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.dismiss()
                }
            }
        }

        func teardown() {
            dismiss()
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
                self.closeObserver = nil
            }
        }

        func update(isPresented: Binding<Bool>, content: AnyView) {
            self.isPresented = isPresented
            self.content = content
            if let controller = popover?.contentViewController as? NSHostingController<AnyView> {
                controller.rootView = content
            }
            if !isPresented.wrappedValue, popover?.isShown == true {
                popover?.close()
            }
        }

        func toggle(from button: NSButton) {
            guard popover?.isShown != true else { return }

            presentingWindow = button.window
            setInteractionLocked(true)
            isPresented.wrappedValue = true

            let controller = NSHostingController(rootView: content)
            controller.view.layoutSubtreeIfNeeded()
            let popover = NSPopover()
            popover.behavior = .applicationDefined
            popover.animates = false
            popover.delegate = self
            popover.contentViewController = controller
            popover.contentSize = controller.view.fittingSize
            self.popover = popover
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
            if let window = popover.contentViewController?.view.window {
                let identifier = NSUserInterfaceItemIdentifier("timer.category.popover")
                window.identifier = identifier
                window.title = identifier.rawValue
                window.setAccessibilityIdentifier(identifier.rawValue)
            }
        }

        private func dismiss() {
            isPresented.wrappedValue = false
            let currentPopover = popover
            popover = nil
            currentPopover?.delegate = nil
            currentPopover?.close()
            setInteractionLocked(false)
            refreshPresentingContent()
        }

        func popoverDidClose(_ notification: Notification) {
            isPresented.wrappedValue = false
            popover = nil
            setInteractionLocked(false)
        }

        private func setInteractionLocked(_ isLocked: Bool) {
            guard isInteractionLocked != isLocked else { return }
            isInteractionLocked = isLocked
            NotificationCenter.default.post(
                name: .nativeSchedulerInteractionLockChanged,
                object: isLocked
            )
        }

        private func refreshPresentingContent() {
            guard let presentingWindow else { return }
            DispatchQueue.main.async { [weak presentingWindow] in
                if let notchWindow = presentingWindow as? NotchWindow {
                    notchWindow.refreshPresentedContent()
                } else {
                    (presentingWindow?.contentView as? CategoryPresentationRefreshing)?
                        .refreshCategoryPresentation()
                }
            }
        }

    }

    @MainActor
    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, content: content)
    }

    @MainActor
    func makeNSView(context: Context) -> CategorySelectorAppKitButton {
        let button = CategorySelectorAppKitButton()
        button.isBordered = false
        button.focusRingType = .none
        button.onActivate = { [weak coordinator = context.coordinator, weak button] in
            guard let button else { return }
            coordinator?.toggle(from: button)
        }
        configure(button)
        return button
    }

    @MainActor
    func updateNSView(_ button: CategorySelectorAppKitButton, context: Context) {
        context.coordinator.update(isPresented: $isPresented, content: content)
        button.onActivate = { [weak coordinator = context.coordinator, weak button] in
            guard let button else { return }
            coordinator?.toggle(from: button)
        }
        configure(button)
    }

    @MainActor
    static func dismantleNSView(_ button: CategorySelectorAppKitButton, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    private func configure(_ button: CategorySelectorAppKitButton) {
        button.title = ""
        button.image = nil
        button.isTransparent = true
        button.setAccessibilityRole(.button)
        button.setAccessibilityIdentifier("timer.category")
        button.setAccessibilityLabel(label)
        button.setAccessibilityHelp("Open category options")
    }
}

@MainActor
private protocol CategoryPresentationRefreshing: AnyObject {
    func refreshCategoryPresentation()
}

extension NSHostingView: CategoryPresentationRefreshing {
    func refreshCategoryPresentation() {
        rootView = rootView
    }
}

private extension Notification.Name {
    static let nativeSchedulerCloseCategoryPopover = Notification.Name(
        "NativeSchedulerCloseCategoryPopover"
    )
}
