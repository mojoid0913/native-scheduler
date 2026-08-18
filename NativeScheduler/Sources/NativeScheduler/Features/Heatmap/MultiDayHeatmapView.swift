// NativeScheduler/Sources/NativeScheduler/Features/Heatmap/MultiDayHeatmapView.swift
import SwiftUI

/// v1.1 — Navigable heatmap card. Today's data streams live from HeatmapViewModel;
/// past days (offset –1 … –6) load from DailyLogReader (stub hook for dev sprint).
///
/// Replaces HeatmapView in MainPanelView. Grid geometry, colors, and type tokens
/// are identical to HeatmapView — only the nav header and data source change.
struct MultiDayHeatmapView: View {
    @ObservedObject var todayVM: HeatmapViewModel

    /// Signed offset from today: 0 = today, –1 = yesterday, …, –6 = 6 days ago.
    @State private var dayOffset: Int = 0

    /// Slots for the currently-displayed historical day. Empty = no data or not loaded.
    /// Uses the same [Int: SlotInfo] dictionary as HeatmapViewModel.slots.
    @State private var historicalSlots: [Int: HeatmapViewModel.SlotInfo] = [:]

    private static let maxOffset = 6

    // ── Grid geometry — mirrors HeatmapView exactly ──────────────────────
    private let cellW:     CGFloat = 20
    private let cellH:     CGFloat = 18
    private let gap:       CGFloat = 2
    private let rowLabelW: CGFloat = 16

    /// Drives the current-time marker and hour label highlight.
    /// Uses a 60-second timer (column advances on the hour; sub-minute resolution unneeded).
    @State private var markerTick: Date = Date()

    private var colStride:     CGFloat { cellW + gap }
    private var currentHour:   Int { Calendar.current.component(.hour,   from: markerTick) }
    private var currentMinute: Int { Calendar.current.component(.minute, from: markerTick) }

    private var isToday: Bool { dayOffset == 0 }

    private var displayedDate: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
    }

    private var dateLabel: String {
        if isToday { return "Today" }
        if Calendar.current.isDateInYesterday(displayedDate) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: displayedDate)
    }

    private var activeSlots: [Int: HeatmapViewModel.SlotInfo] {
        isToday ? todayVM.slots : historicalSlots
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            navHeader

            // Hour axis (offset by row-label column)
            HStack(spacing: 0) {
                Spacer().frame(width: rowLabelW + gap)
                hourLabels
            }

            // Grid with minute-row labels on the left
            HStack(alignment: .top, spacing: gap) {
                minuteRowLabels
                gridWithMarker
            }
        }
        .padding(.horizontal, SchedulerSpacing.compact)
        .padding(.vertical, SchedulerSpacing.compact)
        .schedulerCardSurface()
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { tick in
            markerTick = tick
        }
        .onChange(of: dayOffset) { _, _ in loadHistoricalIfNeeded() }
    }

    // MARK: - Navigation header
    //
    // Design: minimal — two arrow buttons flank a centered date label.
    // "Today" pill jump-button replaces the right arrow when viewing a past day,
    // making it fast to snap back without repeatedly clicking → chevron.

    private var navHeader: some View {
        HStack(spacing: 6) {
            navArrow(systemImage: "chevron.left",
                     label: "Previous day",
                     disabled: dayOffset <= -Self.maxOffset) {
                withAnimation(.easeInOut(duration: 0.15)) { dayOffset -= 1 }
            }

            Spacer()

            Text(dateLabel)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(isToday ? .nsChevron : .nsTextSecondary)
                .contentTransition(.identity)
                .animation(.easeInOut(duration: 0.15), value: dayOffset)

            Spacer()

            if isToday {
                // Dimmed right arrow — can't go into the future
                navArrow(systemImage: "chevron.right",
                         label: "Next day (unavailable)",
                         disabled: true) {}
            } else {
                // "Today" jump pill
                Button {
                    withAnimation(.easeInOut(duration: 0.20)) { dayOffset = 0 }
                } label: {
                    Text("Today")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.nsChevron.opacity(0.75))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.nsBorder)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Jump to today's heatmap")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 2)
    }

    private func navArrow(
        systemImage: String,
        label: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(disabled
                    ? Color.nsTextSecondary.opacity(0.22)
                    : Color.nsTextSecondary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    // MARK: - Hour labels (every 3 h; current hour in nsChevron on today)

    private var hourLabels: some View {
        HStack(spacing: gap) {
            ForEach(0..<24, id: \.self) { h in
                Text(h % 3 == 0 ? String(format: "%02d", h) : "")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor((isToday && h == currentHour)
                        ? .nsChevron
                        : .nsTextSecondary)
                    .frame(width: cellW, alignment: .leading)
            }
        }
    }

    // MARK: - Minute row labels (0, 15, 30, 45)

    private var minuteRowLabels: some View {
        VStack(spacing: gap) {
            ForEach(0..<HeatmapSlot.rowsPerHour, id: \.self) { row in
                Text("\(row * HeatmapSlot.minutesPerSlot)")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(Color.nsTextSecondary.opacity(0.5))
                    .frame(width: rowLabelW, height: cellH, alignment: .trailing)
            }
        }
    }

    // MARK: - Grid + current-time marker

    private var gridWithMarker: some View {
        ZStack(alignment: .topLeading) {
            cellGrid
            if isToday { currentTimeMarker }
        }
    }

    private var cellGrid: some View {
        VStack(spacing: gap) {
            ForEach(0..<HeatmapSlot.rowsPerHour, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<24, id: \.self) { col in
                        let idx  = col * HeatmapSlot.rowsPerHour + row
                        let info = activeSlots[idx]
                        let tip  = tooltipText(info: info, col: col, row: row)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(cellColor(info: info, col: col, row: row))
                            .frame(width: cellW, height: cellH)
                            .help(tip)
                            .animation(.easeInOut(duration: 0.3), value: info?.color)
                            .accessibilityLabel(tip)
                    }
                }
            }
        }
    }

    // MARK: - Cell color
    //
    // Three states (same as HeatmapView):
    //   • Activity present  → category color
    //   • Past/current slot → nsDefaultSlot (#3A3A3A)
    //   • Future slot (today only) → nsFutureSlot (#252525) — "hasn't happened"
    // Historical days have no future slots — all cells are past/activity.

    private func cellColor(info: HeatmapViewModel.SlotInfo?, col: Int, row: Int) -> Color {
        if let info { return info.color }
        return (isToday && isFutureSlot(col: col, row: row)) ? .nsFutureSlot : .nsDefaultSlot
    }

    private func isFutureSlot(col: Int, row: Int) -> Bool {
        guard isToday else { return false }
        let slotRow = currentMinute / HeatmapSlot.minutesPerSlot
        if col > currentHour { return true }
        if col == currentHour && row > slotRow { return true }
        return false
    }

    // MARK: - Current-time marker (today only)
    //
    // 1pt white at 60% opacity spanning full column height,
    // centered on the active column. Driven by markerTick (60s resolution).

    private var currentTimeMarker: some View {
        let gridHeight = CGFloat(HeatmapSlot.rowsPerHour) * cellH + CGFloat(HeatmapSlot.rowsPerHour - 1) * gap
        let centerX    = CGFloat(currentHour) * colStride + cellW / 2

        return Rectangle()
            .fill(Color.white.opacity(0.60))
            .frame(width: 1, height: gridHeight)
            .offset(x: centerX - 0.5, y: 0)
            .allowsHitTesting(false)
    }

    // MARK: - Tooltip

    private func tooltipText(info: HeatmapViewModel.SlotInfo?, col: Int, row: Int) -> String {
        let h = col, m = row * HeatmapSlot.minutesPerSlot
        let datePrefix = isToday ? "" : "\(dateLabel) · "
        let timeStr = String(format: "\(datePrefix)%02d:%02d–%02d:%02d", h, m, h, m + HeatmapSlot.minutesPerSlot)
        guard let info else { return "\(timeStr) · No activity" }
        return "\(timeStr) · \(info.categoryName) (\(info.dominantMinutes) min)"
    }

    // MARK: - Historical data loading
    //
    // v1.1 dev hook: implement DailyLogReader.shared.load(for:) to mmap the .bin
    // file and return [Int: HeatmapViewModel.SlotInfo].
    // Until then the grid shows empty (all nsDefaultSlot) for past days.

    private func loadHistoricalIfNeeded() {
        guard !isToday else { return }
        historicalSlots = [:]
        // TODO v1.1 Developer: wire DailyLogReader here.
        // historicalSlots = DailyLogReader.shared.load(for: displayedDate)
    }
}
