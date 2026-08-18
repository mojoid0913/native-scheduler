// NativeScheduler/Sources/NativeScheduler/Features/Heatmap/HeatmapView.swift
import SwiftUI

struct HeatmapView: View {
    @ObservedObject var vm: HeatmapViewModel
    var showsFullDay: Bool = true

    @State private var markerTick: Date = Date()

    private var currentHour: Int {
        Calendar.current.component(.hour, from: markerTick)
    }

    private var currentMinute: Int {
        Calendar.current.component(.minute, from: markerTick)
    }

    private var displayedHours: [Int] {
        guard !showsFullDay else { return Array(0..<24) }
        let windowHours = 8
        let startHour = min(max(currentHour - 2, 0), 24 - windowHours)
        return Array(startHour..<(startHour + windowHours))
    }

    private var displayRowsPerHour: Int {
        showsFullDay ? HeatmapSlot.rowsPerHour : 3
    }

    private var displayMinutesPerSlot: Int {
        showsFullDay ? HeatmapSlot.minutesPerSlot : 20
    }

    var body: some View {
        GeometryReader { proxy in
            let hours = displayedHours
            let metrics = HeatmapMetrics(
                size: proxy.size,
                columnCount: hours.count,
                rowCount: displayRowsPerHour,
                hasExpandedLayout: showsFullDay
            )

            HStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: metrics.labelGap) {
                    HStack(spacing: 0) {
                        Spacer().frame(width: metrics.rowLabelWidth + metrics.gap)
                        hourLabels(hours: hours, metrics: metrics)
                    }

                    HStack(alignment: .top, spacing: metrics.gap) {
                        minuteRowLabels(metrics: metrics)
                        gridWithMarker(hours: hours, metrics: metrics)
                    }
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.verticalPadding)
                .padding(.bottom, metrics.bottomPadding)
                .frame(width: metrics.contentWidth, alignment: .topLeading)
                .background(Color.nsSurface)
                .clipShape(RoundedRectangle(cornerRadius: metrics.cornerRadius))
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topTrailing)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { tick in
            markerTick = tick
            vm.refreshCurrentSlot(now: tick)
        }
    }

    private func hourLabels(hours: [Int], metrics: HeatmapMetrics) -> some View {
        HStack(spacing: metrics.gap) {
            ForEach(hours, id: \.self) { hour in
                Text(showsFullDay && hour % 3 != 0 ? "" : String(format: "%02d", hour))
                    .font(.system(size: metrics.hourFontSize, design: .monospaced))
                    .foregroundColor(hour == currentHour ? .nsChevron : .nsTextSecondary)
                    .frame(width: metrics.cellWidth, alignment: .leading)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private func minuteRowLabels(metrics: HeatmapMetrics) -> some View {
        VStack(spacing: metrics.gap) {
            ForEach(0..<displayRowsPerHour, id: \.self) { row in
                Text("\(row * displayMinutesPerSlot)")
                    .font(.system(size: metrics.minuteFontSize, design: .monospaced))
                    .foregroundStyle(Color.nsTextSecondary.opacity(0.5))
                    .frame(width: metrics.rowLabelWidth, height: metrics.cellHeight, alignment: .trailing)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private func gridWithMarker(hours: [Int], metrics: HeatmapMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            cellGrid(hours: hours, metrics: metrics)
            currentTimeMarker(hours: hours, metrics: metrics)
        }
    }

    private func cellGrid(hours: [Int], metrics: HeatmapMetrics) -> some View {
        VStack(spacing: metrics.gap) {
            ForEach(0..<displayRowsPerHour, id: \.self) { row in
                HStack(spacing: metrics.gap) {
                    ForEach(hours, id: \.self) { hour in
                        let info = vm.slotInfo(hour: hour, row: row, minutesPerSlot: displayMinutesPerSlot)
                        let tip = tooltipText(info: info, hour: hour, row: row)

                        RoundedRectangle(cornerRadius: metrics.cellCornerRadius)
                            .fill(cellColor(info: info, hour: hour, row: row))
                            .frame(width: metrics.cellWidth, height: metrics.cellHeight)
                            .help(tip)
                            .animation(.easeInOut(duration: 0.3), value: info?.color)
                            .accessibilityLabel(tip)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func currentTimeMarker(hours: [Int], metrics: HeatmapMetrics) -> some View {
        if let hourIndex = hours.firstIndex(of: currentHour) {
            let centerX = CGFloat(hourIndex) * metrics.colStride + metrics.cellWidth / 2

            Rectangle()
                .fill(Color.white.opacity(0.60))
                .frame(width: max(1, metrics.cellWidth * 0.06), height: metrics.gridHeight)
                .offset(x: centerX - 0.5, y: 0)
                .allowsHitTesting(false)
        }
    }

    private func cellColor(info: HeatmapViewModel.SlotInfo?, hour: Int, row: Int) -> Color {
        if let info { return info.color }
        return isFutureSlot(hour: hour, row: row) ? .nsFutureSlot : .nsDefaultSlot
    }

    private func isFutureSlot(hour: Int, row: Int) -> Bool {
        let currentSlotRow = currentMinute / displayMinutesPerSlot
        if hour > currentHour { return true }
        if hour == currentHour && row > currentSlotRow { return true }
        return false
    }

    private func tooltipText(info: HeatmapViewModel.SlotInfo?, hour: Int, row: Int) -> String {
        let minute = row * displayMinutesPerSlot
        let time = String(format: "%02d:%02d\u{2013}%02d:%02d", hour, minute, hour, minute + displayMinutesPerSlot)
        guard let info else { return "\(time) · No activity" }
        return "\(time) · \(info.categoryName) (\(info.dominantMinutes) min)"
    }
}

private struct HeatmapMetrics {
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let bottomPadding: CGFloat
    let gap: CGFloat
    let rowLabelWidth: CGFloat
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let labelGap: CGFloat
    let hourFontSize: CGFloat
    let minuteFontSize: CGFloat
    let cornerRadius: CGFloat
    let cellCornerRadius: CGFloat
    let columnCount: Int
    let rowCount: Int

    init(size: CGSize, columnCount: Int, rowCount: Int, hasExpandedLayout: Bool) {
        self.columnCount = max(1, columnCount)
        self.rowCount = max(1, rowCount)
        horizontalPadding = max(6, size.width * 0.012)
        verticalPadding = max(6, size.height * 0.055)
        bottomPadding = hasExpandedLayout ? verticalPadding + 5 : verticalPadding + 4
        gap = max(1.5, min(3, size.width * 0.004))
        rowLabelWidth = max(12, size.width * 0.030)
        labelGap = max(3, size.height * 0.03)

        let availableGridWidth = max(120, size.width - (horizontalPadding * 2) - rowLabelWidth - gap)
        let widthBasedCell = (availableGridWidth - (gap * CGFloat(max(0, self.columnCount - 1)))) / CGFloat(self.columnCount)

        let availableGridHeight = max(48, size.height - verticalPadding - bottomPadding - labelGap - 12)
        let heightBasedCell = (availableGridHeight - (gap * CGFloat(self.rowCount - 1))) / CGFloat(self.rowCount)
        let squareCell = max(7, min(30, max(min(widthBasedCell, 30), min(heightBasedCell, widthBasedCell))))
        cellWidth = squareCell
        cellHeight = squareCell

        hourFontSize = max(7, min(9, cellWidth * 0.48))
        minuteFontSize = max(6, min(8, cellHeight * 0.45))
        cornerRadius = max(7, min(10, size.width * 0.018))
        cellCornerRadius = max(1.5, min(3, cellWidth * 0.12))
    }

    var colStride: CGFloat { cellWidth + gap }
    var contentWidth: CGFloat {
        horizontalPadding * 2
        + rowLabelWidth
        + gap
        + CGFloat(columnCount) * cellWidth
        + CGFloat(max(0, columnCount - 1)) * gap
    }
    var gridHeight: CGFloat {
        CGFloat(rowCount) * cellHeight + CGFloat(rowCount - 1) * gap
    }
}

struct DaylineRange: Equatable, Sendable {
    let start: Date
    let end: Date

    var duration: TimeInterval { end.timeIntervalSince(start) }

    func fraction(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / duration))
    }
}

struct DaylineLane: Equatable, Sendable {
    let label: String
    let range: DaylineRange
}

struct DaylineExpandedRow: Identifiable, Equatable, Sendable {
    let snapshot: DayActivitySnapshot
    let label: String
    let showsTemporalContext: Bool

    var id: Date { snapshot.dayStart }
    var range: DaylineRange {
        DaylineRange(start: snapshot.dayStart, end: snapshot.nextDayStart)
    }
}

enum DaylineViewMetrics {
    static let expandedInset: CGFloat = 4
    static let headerHeight: CGFloat = 24
    static let axisHeight: CGFloat = 12
    static let dayRowHeight: CGFloat = 20
    static let trackHeight: CGFloat = 10
    static let detailHeight: CGFloat = 24
    static let dayLabelWidth: CGFloat = 70
    static let dayTotalWidth: CGFloat = 60
    static let rowSpacing: CGFloat = 6
    static let meaningfulTextSize: CGFloat = 11
    static let minimumActionTarget: CGFloat = 24
}

struct DaylineSegmentGeometry: Equatable, Sendable {
    let startFraction: Double
    let endFraction: Double
    let fillFraction: Double
    let minimumStrokePoints: Double
}

struct DaylineRenderTarget: Identifiable {
    let segment: DayActivitySegment
    let geometry: DaylineSegmentGeometry
    let hitStartPoints: CGFloat
    let hitWidthPoints: CGFloat
    let visibleOffsetPoints: CGFloat
    let visibleWidthPoints: CGFloat

    var id: DayActivitySegmentID { segment.id }
}

struct DaylinePatternToken: Equatable, Sendable {
    let dash: [Double]
    let cap: String
    let isDefault: Bool
}

enum DaylineContract {
    static let title = "Stream"
    static let expandedAxisLabels = ["00", "06", "12", "18", "24"]

    static func compactRange(for snapshot: DayActivitySnapshot) -> DaylineRange {
        let calendar = calendar(for: snapshot)
        let hourStart = calendar.dateInterval(of: .hour, for: snapshot.asOf)?.start ?? snapshot.asOf
        let candidateStart = calendar.date(byAdding: .hour, value: -2, to: hourStart) ?? hourStart
        let desiredEnd = candidateStart.addingTimeInterval(8 * 60 * 60)
        let dayCapacity = snapshot.nextDayStart.timeIntervalSince(snapshot.dayStart)
        var start = max(candidateStart, snapshot.dayStart)
        var end = min(desiredEnd, snapshot.nextDayStart)

        if dayCapacity >= 8 * 60 * 60, end.timeIntervalSince(start) < 8 * 60 * 60 {
            if start == snapshot.dayStart {
                end = min(snapshot.dayStart.addingTimeInterval(8 * 60 * 60), snapshot.nextDayStart)
            } else if end == snapshot.nextDayStart {
                start = max(snapshot.nextDayStart.addingTimeInterval(-8 * 60 * 60), snapshot.dayStart)
            }
        }

        return DaylineRange(start: start, end: end)
    }

    static func compactTickDates(for range: DaylineRange, snapshot: DayActivitySnapshot) -> [Date] {
        let calendar = calendar(for: snapshot)
        var ticks: [Date] = []
        var tick = range.start

        while tick <= range.end {
            ticks.append(tick)
            guard let next = calendar.date(byAdding: .hour, value: 2, to: tick), next > tick else { break }
            tick = next
        }

        return ticks
    }

    static func expandedRows(for window: DayActivityWindowSnapshot) -> [DaylineExpandedRow] {
        window.days.prefix(5).enumerated().map { index, snapshot in
            DaylineExpandedRow(
                snapshot: snapshot,
                label: index == 0 ? "Today" : dayLabel(for: snapshot),
                showsTemporalContext: index == 0
            )
        }
    }

    static func compactDurationText(_ seconds: TimeInterval, localeIdentifier: String) -> String {
        let isKorean = localeIdentifier.lowercased().hasPrefix("ko")
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        guard totalSeconds > 0 else { return isKorean ? "0분" : "0m" }
        let totalMinutes = totalSeconds / 60
        guard totalMinutes > 0 else { return isKorean ? "<1분" : "<1m" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if isKorean {
            if hours == 0 { return "\(minutes)분" }
            return minutes == 0 ? "\(hours)시간" : "\(hours)시간 \(minutes)분"
        }
        if hours == 0 { return "\(minutes)m" }
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }

    static func segmentGeometry(
        for segment: DayActivitySegment,
        in range: DaylineRange
    ) -> DaylineSegmentGeometry? {
        let start = max(segment.start, range.start)
        let end = min(segment.end, range.end)
        guard end > start, range.duration > 0 else { return nil }

        let startFraction = range.fraction(at: start)
        let endFraction = range.fraction(at: end)
        guard endFraction > startFraction else { return nil }

        return DaylineSegmentGeometry(
            startFraction: startFraction,
            endFraction: endFraction,
            fillFraction: endFraction - startFraction,
            minimumStrokePoints: 1
        )
    }

    static func renderTargets(
        for segments: [DayActivitySegment],
        in range: DaylineRange,
        trackWidth: CGFloat
    ) -> [DaylineRenderTarget] {
        let width = max(0, trackWidth)
        guard width > 0 else { return [] }
        let visible = segments.compactMap { segment -> (DayActivitySegment, DaylineSegmentGeometry)? in
            guard let geometry = segmentGeometry(for: segment, in: range) else { return nil }
            return (segment, geometry)
        }
        .sorted { left, right in
            if left.1.startFraction == right.1.startFraction {
                return left.1.endFraction < right.1.endFraction
            }
            return left.1.startFraction < right.1.startFraction
        }

        return visible.map { segment, geometry in
            let visibleStart = width * geometry.startFraction
            let visibleWidth = width * geometry.fillFraction
            let hitWidth = min(
                width,
                max(visibleWidth, DaylineViewMetrics.minimumActionTarget)
            )
            let centeredStart = visibleStart - (hitWidth - visibleWidth) / 2
            let hitStart = min(max(centeredStart, 0), width - hitWidth)

            return DaylineRenderTarget(
                segment: segment,
                geometry: geometry,
                hitStartPoints: hitStart,
                hitWidthPoints: hitWidth,
                visibleOffsetPoints: visibleStart - hitStart,
                visibleWidthPoints: visibleWidth
            )
        }
    }

    static func segmentID(
        at point: CGFloat,
        in targets: [DaylineRenderTarget]
    ) -> DayActivitySegmentID? {
        guard point.isFinite else { return nil }
        if let exact = targets.first(where: { target in
            let visibleStart = target.hitStartPoints + target.visibleOffsetPoints
            let visibleEnd = visibleStart + target.visibleWidthPoints
            return point >= visibleStart && point < visibleEnd
        }) {
            return exact.segment.id
        }

        return targets.enumerated()
            .filter { _, target in
                point >= target.hitStartPoints
                    && point <= target.hitStartPoints + target.hitWidthPoints
            }
            .min { left, right in
                let leftDistance = distanceFromVisibleInk(point, target: left.element)
                let rightDistance = distanceFromVisibleInk(point, target: right.element)
                if leftDistance == rightDistance { return left.offset < right.offset }
                return leftDistance < rightDistance
            }?
            .element.segment.id
    }

    private static func distanceFromVisibleInk(
        _ point: CGFloat,
        target: DaylineRenderTarget
    ) -> CGFloat {
        let start = target.hitStartPoints + target.visibleOffsetPoints
        let end = start + target.visibleWidthPoints
        if point < start { return start - point }
        if point > end { return point - end }
        return 0
    }

    static func markerFraction(at date: Date, in range: DaylineRange) -> Double? {
        guard date >= range.start, date < range.end else { return nil }
        return range.fraction(at: date)
    }

    static func pattern(for categoryID: UUID?) -> DaylinePatternToken {
        guard let categoryID else {
            return DaylinePatternToken(dash: [1, 2], cap: "round", isDefault: true)
        }

        let patterns: [[Double]] = [[3, 1], [1, 1], [4, 2], [2, 1, 1, 1]]
        let hash = categoryID.uuidString.utf8.reduce(UInt64(0)) { value, byte in
            (value &* 31) &+ UInt64(byte)
        }
        return DaylinePatternToken(
            dash: patterns[Int(hash % UInt64(patterns.count))],
            cap: "round",
            isDefault: false
        )
    }

    static func durationText(_ seconds: TimeInterval, localeIdentifier: String) -> String {
        let isKorean = localeIdentifier.lowercased().hasPrefix("ko")
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        guard totalSeconds > 0 else { return isKorean ? "0분" : "0 minutes" }
        guard totalSeconds >= 60 else { return isKorean ? "1분 미만" : "Under 1 minute" }

        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        if isKorean {
            if hours == 0 { return "\(minutes)분" }
            return minutes == 0 ? "\(hours)시간" : "\(hours)시간 \(minutes)분"
        }

        if hours == 0 { return "\(minutes) \(minutes == 1 ? "minute" : "minutes")" }
        if minutes == 0 { return "\(hours) \(hours == 1 ? "hour" : "hours")" }
        return "\(hours) \(hours == 1 ? "hour" : "hours") \(minutes) \(minutes == 1 ? "minute" : "minutes")"
    }

    static func headerAccessibilityLabel(_ snapshot: DayActivitySnapshot) -> String {
        "\(title), 오늘 기록 \(durationText(snapshot.totalTrackedSeconds, localeIdentifier: snapshot.localeIdentifier))"
    }

    static func segmentAccessibilityLabel(
        _ segment: DayActivitySegment,
        snapshot: DayActivitySnapshot,
        selected: Bool = false
    ) -> String {
        let label = segmentLabel(segment, range: spokenRangeLabel(
            start: segment.start,
            end: segment.end,
            snapshot: snapshot
        ), snapshot: snapshot)
        guard selected else { return label }
        let selection = snapshot.localeIdentifier.lowercased().hasPrefix("ko") ? "선택됨" : "Selected"
        return "\(label), \(selection)"
    }

    static func segmentAccessibilityIdentifier(_ id: DayActivitySegmentID) -> String {
        "dayline.segment|\(id.dayStart.timeIntervalSinceReferenceDate)|\(id.sessionID.uuidString.lowercased())|\(id.winningPieceStart.timeIntervalSinceReferenceDate)"
    }

    static func segmentDetailLabel(
        _ segment: DayActivitySegment,
        snapshot: DayActivitySnapshot
    ) -> String {
        segmentLabel(segment, range: visibleRangeLabel(
            start: segment.start,
            end: segment.end,
            snapshot: snapshot
        ), snapshot: snapshot)
    }

    static func compactSegmentDetailLabel(
        _ segment: DayActivitySegment,
        snapshot: DayActivitySnapshot
    ) -> String {
        let presentation = compactSegmentDetailPresentation(segment, snapshot: snapshot)
        return [
            presentation.category,
            presentation.timeRange,
            presentation.duration,
            presentation.status
        ].joined(separator: ", ")
    }

    static func compactSegmentDetailPresentation(
        _ segment: DayActivitySegment,
        snapshot: DayActivitySnapshot
    ) -> DaylineSegmentDetailPresentation {
        let category = segment.categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let activeState = snapshot.localeIdentifier.lowercased().hasPrefix("ko")
            ? (segment.isActive ? "활성" : "비활성")
            : (segment.isActive ? "Live" : "Past")
        return DaylineSegmentDetailPresentation(
            category: category.isEmpty ? "Default" : category,
            timeRange: visibleRangeLabel(start: segment.start, end: segment.end, snapshot: snapshot),
            duration: compactDurationText(segment.duration, localeIdentifier: snapshot.localeIdentifier),
            status: activeState
        )
    }

    static func visibleRangeLabel(start: Date, end: Date, snapshot: DayActivitySnapshot) -> String {
        timeRangeText(start: start, end: end, snapshot: snapshot)
    }

    static func spokenRangeLabel(start: Date, end: Date, snapshot: DayActivitySnapshot) -> String {
        timeRangeText(start: start, end: end, snapshot: snapshot)
    }

    private static func segmentLabel(
        _ segment: DayActivitySegment,
        range: String,
        snapshot: DayActivitySnapshot
    ) -> String {
        let category = segment.categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCategory = category.isEmpty ? "Default" : category
        let activeState = snapshot.localeIdentifier.lowercased().hasPrefix("ko")
            ? (segment.isActive ? "활성" : "비활성")
            : (segment.isActive ? "Active" : "Inactive")
        return [
            resolvedCategory,
            range,
            durationText(segment.duration, localeIdentifier: snapshot.localeIdentifier),
            activeState
        ].joined(separator: ", ")
    }

    private static func calendar(for snapshot: DayActivitySnapshot) -> Calendar {
        var calendar = Calendar(identifier: snapshot.calendarIdentifier == "iso8601" ? .iso8601 : .gregorian)
        calendar.locale = Locale(identifier: snapshot.localeIdentifier)
        calendar.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func dayLabel(for snapshot: DayActivitySnapshot) -> String {
        let calendar = calendar(for: snapshot)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: snapshot.localeIdentifier)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE M/d"
        return formatter.string(from: snapshot.dayStart)
    }

    private static func timeRangeText(
        start: Date,
        end: Date,
        snapshot: DayActivitySnapshot
    ) -> String {
        let calendar = calendar(for: snapshot)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: snapshot.localeIdentifier)
        formatter.timeZone = calendar.timeZone
        let crossedOffset = calendar.timeZone.secondsFromGMT(for: start)
            != calendar.timeZone.secondsFromGMT(for: end)
        let repeatedWallClockTime = isRepeatedWallClockTime(start, in: calendar)
            || isRepeatedWallClockTime(end, in: calendar)
        formatter.dateFormat = crossedOffset || repeatedWallClockTime ? "HH:mm XXXXX" : "HH:mm"
        return "\(formatter.string(from: start))–\(formatter.string(from: end))"
    }

    private static func isRepeatedWallClockTime(_ date: Date, in calendar: Calendar) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        guard
            let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart),
            let transition = calendar.timeZone.nextDaylightSavingTimeTransition(
                after: dayStart.addingTimeInterval(-1)
            ),
            transition < nextDayStart
        else {
            return false
        }

        let offsetBefore = calendar.timeZone.secondsFromGMT(for: transition.addingTimeInterval(-1))
        let offsetAfter = calendar.timeZone.secondsFromGMT(for: transition.addingTimeInterval(1))
        guard offsetBefore > offsetAfter else { return false }

        let repeatedDuration = TimeInterval(offsetBefore - offsetAfter)
        return date >= transition.addingTimeInterval(-repeatedDuration)
            && date < transition.addingTimeInterval(repeatedDuration)
    }
}

enum DaylineAccessibilityItem: Equatable {
    case header
    case toggle
    case segment(DayActivitySegmentID)
}

enum DaylineMotionStyle: Equatable {
    case none
    case layoutMorph
}

enum DaylineMotion {
    static func style(reduceMotion: Bool) -> DaylineMotionStyle {
        reduceMotion ? .none : .layoutMorph
    }

    static func expansionAnimation(reduceMotion: Bool) -> Animation? {
        guard style(reduceMotion: reduceMotion) == .layoutMorph else { return nil }
        return .spring(response: 0.28, dampingFraction: 0.82)
    }
}

struct DaylineSegmentDetailPresentation: Equatable {
    let category: String
    let timeRange: String
    let duration: String
    let status: String
}

enum DaylineViewControl {
    static func label(isExpanded: Bool) -> String {
        isExpanded ? "오늘만 보기" : "최근 5일 보기"
    }

    static func symbol(isExpanded: Bool) -> String {
        isExpanded ? "chevron.right" : "chevron.left"
    }
}

enum DaylineWarning {
    static func message(hasFetchError: Bool, recoveryWarningCount _: Int = 0) -> String? {
        if hasFetchError { return "Activity data may be out of date. Retry." }
        return nil
    }
}

struct DaylineInteractionState: Equatable {
    private(set) var pinnedSegmentID: DayActivitySegmentID?
    private(set) var focusedSegmentID: DayActivitySegmentID?

    func detailID(in snapshot: DayActivitySnapshot) -> DayActivitySegmentID? {
        detailID(in: [snapshot])
    }

    func detailID(in snapshots: [DayActivitySnapshot]) -> DayActivitySegmentID? {
        let ids = Set(snapshots.flatMap { $0.segments.map(\.id) })
        if let pinnedSegmentID, ids.contains(pinnedSegmentID) { return pinnedSegmentID }
        if let focusedSegmentID, ids.contains(focusedSegmentID) { return focusedSegmentID }
        return snapshots.lazy.compactMap(\.activeOrMostRecentID).first
            ?? snapshots.lazy.compactMap { $0.segments.last?.id }.first
    }

    mutating func pin(_ id: DayActivitySegmentID) {
        pinnedSegmentID = id
    }

    mutating func focus(_ id: DayActivitySegmentID?) {
        focusedSegmentID = id
    }

    mutating func resetToCurrentActivity() {
        pinnedSegmentID = nil
        focusedSegmentID = nil
    }

    mutating func reconcile(with snapshot: DayActivitySnapshot) {
        reconcile(with: [snapshot])
    }

    mutating func reconcile(with snapshots: [DayActivitySnapshot]) {
        let ids = Set(snapshots.flatMap { $0.segments.map(\.id) })
        if let pinnedSegmentID, !ids.contains(pinnedSegmentID) { self.pinnedSegmentID = nil }
        if let focusedSegmentID, !ids.contains(focusedSegmentID) { self.focusedSegmentID = nil }
    }

    func accessibilityOrder(in snapshot: DayActivitySnapshot) -> [DaylineAccessibilityItem] {
        accessibilityOrder(in: [snapshot])
    }

    func accessibilityOrder(in snapshots: [DayActivitySnapshot]) -> [DaylineAccessibilityItem] {
        [.header, .toggle] + snapshots.flatMap { $0.segments.map { .segment($0.id) } }
    }

    func keyboardOrder(in snapshot: DayActivitySnapshot) -> [DaylineAccessibilityItem] {
        keyboardOrder(in: [snapshot])
    }

    func keyboardOrder(in snapshots: [DayActivitySnapshot]) -> [DaylineAccessibilityItem] {
        [.toggle] + snapshots.flatMap { $0.segments.map { .segment($0.id) } }
    }
}

@MainActor
final class DaylineInteractionModel: ObservableObject {
    @Published private var state = DaylineInteractionState()

    var statePublisher: Published<DaylineInteractionState>.Publisher { $state }
    var pinnedSegmentID: DayActivitySegmentID? { state.pinnedSegmentID }
    var focusedSegmentID: DayActivitySegmentID? { state.focusedSegmentID }

    func detailID(in snapshots: [DayActivitySnapshot]) -> DayActivitySegmentID? {
        state.detailID(in: snapshots)
    }

    func pin(_ id: DayActivitySegmentID) {
        update { $0.pin(id) }
    }

    func focus(_ id: DayActivitySegmentID?) {
        update { $0.focus(id) }
    }

    func resetToCurrentActivity() {
        update { $0.resetToCurrentActivity() }
    }

    func reconcile(with snapshots: [DayActivitySnapshot]) {
        update { $0.reconcile(with: snapshots) }
    }

    func reconcile(with snapshot: DayActivitySnapshot) {
        update { $0.reconcile(with: snapshot) }
    }

    private func update(_ change: (inout DaylineInteractionState) -> Void) {
        var updated = state
        change(&updated)
        state = updated
    }
}

private struct DaylineHeaderAccessibilityGroup: NSViewRepresentable {
    let label: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSView) {
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel(label)
        view.setAccessibilityIdentifier("dayline.header")
    }
}

struct DaylineView: View {
    let snapshot: DayActivitySnapshot
    let windowSnapshot: DayActivityWindowSnapshot?
    let isExpanded: Bool
    let hasFetchError: Bool
    let recoveryWarningCount: Int
    let reduceMotionOverride: Bool?
    let onToggle: () -> Void
    let onRetry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var interaction: DaylineInteractionModel
    @Namespace private var expansionNamespace

    @MainActor
    init(
        snapshot: DayActivitySnapshot,
        windowSnapshot: DayActivityWindowSnapshot? = nil,
        isExpanded: Bool,
        hasFetchError: Bool = false,
        recoveryWarningCount: Int = 0,
        reduceMotionOverride: Bool? = nil,
        interactionModel: DaylineInteractionModel? = nil,
        onToggle: @escaping () -> Void = {},
        onRetry: @escaping () -> Void = {}
    ) {
        self.snapshot = snapshot
        self.windowSnapshot = windowSnapshot
        self.isExpanded = isExpanded
        self.hasFetchError = hasFetchError
        self.recoveryWarningCount = recoveryWarningCount
        self.reduceMotionOverride = reduceMotionOverride
        _interaction = ObservedObject(wrappedValue: interactionModel ?? DaylineInteractionModel())
        self.onToggle = onToggle
        self.onRetry = onRetry
    }

    var body: some View {
        Group {
            if isExpanded, let windowSnapshot {
                expandedBody(rows: DaylineContract.expandedRows(for: windowSnapshot))
                    .padding(DaylineViewMetrics.expandedInset)
                    .transition(.identity)
            } else {
                compactBody
                    .padding(SchedulerSpacing.cardInset)
                    .transition(.identity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .schedulerCardSurface()
        .onChange(of: snapshot) { _, updatedSnapshot in interaction.reconcile(with: updatedSnapshot) }
        .onChange(of: windowSnapshot) { _, updatedWindow in
            interaction.reconcile(with: updatedWindow?.days ?? [snapshot])
        }
        .onChange(of: isExpanded) { _, _ in interaction.resetToCurrentActivity() }
        .onHover { inside in
            if !inside { interaction.resetToCurrentActivity() }
        }
        .animation(DaylineMotion.expansionAnimation(reduceMotion: reduceMotionOverride ?? reduceMotion), value: isExpanded)
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            compactHeader
            DaylineLaneView(
                lane: DaylineLane(label: "", range: DaylineContract.compactRange(for: snapshot)),
                snapshot: snapshot,
                interaction: interaction
            )
            .matchedGeometryEffect(
                id: "dayline.primary-row",
                in: expansionNamespace,
                properties: .frame,
                anchor: .leading
            )
            detailRow(snapshots: [snapshot])
                .matchedGeometryEffect(
                    id: "dayline.detail",
                    in: expansionNamespace,
                    properties: .frame,
                    anchor: .leading
                )
        }
    }

    private var compactHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DaylineContract.title)
                    .font(SchedulerType.cardTitle)
                    .foregroundColor(.nsTextPrimary)
                Text(DaylineContract.durationText(snapshot.totalTrackedSeconds, localeIdentifier: snapshot.localeIdentifier))
                    .font(.system(size: DaylineViewMetrics.meaningfulTextSize))
                    .foregroundColor(.nsTextTertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(DaylineContract.headerAccessibilityLabel(snapshot))
            .accessibilitySortPriority(2)

            Spacer(minLength: 0)
        }
        .matchedGeometryEffect(
            id: "dayline.header",
            in: expansionNamespace,
            properties: .frame,
            anchor: .leading
        )
    }

    private func expandedBody(rows: [DaylineExpandedRow]) -> some View {
        let snapshots = rows.map(\.snapshot)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(DaylineContract.title)
                    .font(SchedulerType.cardTitle)
                    .foregroundColor(.nsTextPrimary)
                Text(DaylineContract.compactDurationText(
                    snapshot.totalTrackedSeconds,
                    localeIdentifier: snapshot.localeIdentifier
                ))
                    .font(.system(size: DaylineViewMetrics.meaningfulTextSize, design: .monospaced))
                    .foregroundColor(.nsTextTertiary)
                Spacer(minLength: 0)
            }
            .frame(height: DaylineViewMetrics.headerHeight)
            .matchedGeometryEffect(
                id: "dayline.header",
                in: expansionNamespace,
                properties: .frame,
                anchor: .leading
            )
            .accessibilityHidden(true)
            .overlay {
                DaylineHeaderAccessibilityGroup(
                    label: DaylineContract.headerAccessibilityLabel(snapshot)
                )
                .allowsHitTesting(false)
                .accessibilitySortPriority(2)
            }

            DaylineAxisView()
                .frame(height: DaylineViewMetrics.axisHeight)
                .transition(expansionTransition)

            if let newest = rows.first {
                DaylineExpandedRowView(row: newest, interaction: interaction)
                    .frame(height: DaylineViewMetrics.dayRowHeight)
                    .matchedGeometryEffect(
                        id: "dayline.primary-row",
                        in: expansionNamespace,
                        properties: .frame,
                        anchor: .leading
                    )
            }

            ForEach(Array(rows.dropFirst())) { row in
                DaylineExpandedRowView(row: row, interaction: interaction)
                    .frame(height: DaylineViewMetrics.dayRowHeight)
                    .transition(expansionTransition)
            }

            detailRow(snapshots: snapshots)
                .frame(height: DaylineViewMetrics.detailHeight)
                .matchedGeometryEffect(
                    id: "dayline.detail",
                    in: expansionNamespace,
                    properties: .frame,
                    anchor: .leading
                )
        }
    }

    private var expansionTransition: AnyTransition {
        guard !(reduceMotionOverride ?? reduceMotion) else { return .identity }
        return .asymmetric(
            insertion: .offset(y: -10).combined(with: .opacity),
            removal: .offset(y: -6).combined(with: .opacity)
        )
    }

    @ViewBuilder
    private func detailRow(snapshots: [DayActivitySnapshot]) -> some View {
        if hasFetchError, let warning = DaylineWarning.message(
            hasFetchError: true,
            recoveryWarningCount: recoveryWarningCount
        ) {
            Button(action: onRetry) {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(minHeight: DaylineViewMetrics.minimumActionTarget)
                    .overlay(alignment: .leading) {
                        Label("기록 새로고침", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                            .font(.system(size: DaylineViewMetrics.meaningfulTextSize, weight: .medium))
                            .foregroundColor(.daylineError)
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
            }
            .buttonStyle(.plain)
            .help(warning)
            .accessibilityLabel(warning)
            .accessibilityIdentifier("dayline.retry")
        } else if let warning = DaylineWarning.message(
            hasFetchError: false,
            recoveryWarningCount: recoveryWarningCount
        ) {
            Label(warning, systemImage: "exclamationmark.triangle")
                .font(.system(size: DaylineViewMetrics.meaningfulTextSize, weight: .medium))
                .foregroundColor(.daylineError)
                .lineLimit(1)
                .frame(minHeight: DaylineViewMetrics.minimumActionTarget)
                .accessibilityLabel(warning)
        } else if let detail = detail(in: snapshots) {
            let presentation = DaylineContract.compactSegmentDetailPresentation(
                detail.segment,
                snapshot: detail.snapshot
            )
            HStack(spacing: SchedulerSpacing.xs) {
                DaylinePatternSwatch(segment: detail.segment)

                Text(presentation.category)
                    .font(SchedulerType.bodyMedium)
                    .foregroundColor(.nsTextPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)

                Text(presentation.timeRange)
                    .font(SchedulerType.monospacedMetadata)
                    .foregroundColor(.nsTextSecondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: SchedulerSpacing.xxs)

                Text(presentation.status)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(detail.segment.isActive
                        ? Color(hex: detail.segment.categoryHex)
                        : .nsTextTertiary)
                    .padding(.horizontal, SchedulerSpacing.xs)
                    .padding(.vertical, 2)
                    .background(
                        (detail.segment.isActive
                            ? Color(hex: detail.segment.categoryHex)
                            : Color.nsBorder)
                            .opacity(0.16)
                    )
                    .clipShape(Capsule())
                    .fixedSize(horizontal: true, vertical: false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                DaylineContract.compactSegmentDetailLabel(
                    detail.segment,
                    snapshot: detail.snapshot
                )
            )
        } else {
            Text("오늘 기록 없음")
                .font(.system(size: DaylineViewMetrics.meaningfulTextSize))
                .foregroundColor(.nsTextTertiary)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
    }

    private func detail(
        in snapshots: [DayActivitySnapshot]
    ) -> (segment: DayActivitySegment, snapshot: DayActivitySnapshot)? {
        guard let id = interaction.detailID(in: snapshots) else { return nil }
        for snapshot in snapshots {
            if let segment = snapshot.segments.first(where: { $0.id == id }) {
                return (segment, snapshot)
            }
        }
        return nil
    }
}

private struct DaylineLaneView: View {
    let lane: DaylineLane
    let snapshot: DayActivitySnapshot
    @ObservedObject var interaction: DaylineInteractionModel
    @FocusState private var focusedSegmentID: DayActivitySegmentID?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DaylineTrackView(
                range: lane.range,
                snapshot: snapshot,
                showsTemporalContext: true,
                interaction: interaction,
                focusedSegmentID: $focusedSegmentID
            )
            .frame(height: DaylineViewMetrics.dayRowHeight)

            if lane.label.isEmpty {
                HStack {
                    ForEach(DaylineContract.compactTickDates(for: lane.range, snapshot: snapshot), id: \.self) { tick in
                        Text(tickLabel(tick))
                            .font(.system(size: DaylineViewMetrics.meaningfulTextSize, design: .monospaced))
                            .foregroundColor(.nsTextTertiary)
                        if tick != lane.range.end { Spacer(minLength: 0) }
                    }
                }
            }
        }
        .onChange(of: focusedSegmentID) { _, id in interaction.focus(id) }
    }

    private func tickLabel(_ date: Date) -> String {
        var calendar = Calendar(identifier: snapshot.calendarIdentifier == "iso8601" ? .iso8601 : .gregorian)
        calendar.timeZone = TimeZone(identifier: snapshot.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        return String(format: "%02d", calendar.component(.hour, from: date))
    }
}

private struct DaylineAxisView: View {
    var body: some View {
        HStack(spacing: DaylineViewMetrics.rowSpacing) {
            Color.clear.frame(width: DaylineViewMetrics.dayLabelWidth)
            HStack(spacing: 0) {
                ForEach(Array(DaylineContract.expandedAxisLabels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.system(size: DaylineViewMetrics.meaningfulTextSize, design: .monospaced))
                        .foregroundColor(.nsTextTertiary)
                    if index < DaylineContract.expandedAxisLabels.count - 1 {
                        Spacer(minLength: 0)
                    }
                }
            }
            Color.clear.frame(width: DaylineViewMetrics.dayTotalWidth)
        }
        .accessibilityHidden(true)
    }
}

private struct DaylineExpandedRowView: View {
    let row: DaylineExpandedRow
    @ObservedObject var interaction: DaylineInteractionModel
    @FocusState private var focusedSegmentID: DayActivitySegmentID?

    var body: some View {
        HStack(spacing: DaylineViewMetrics.rowSpacing) {
            Text(row.label)
                .font(.system(size: DaylineViewMetrics.meaningfulTextSize, weight: .medium))
                .foregroundColor(row.showsTemporalContext ? .nsTextPrimary : .nsTextTertiary)
                .lineLimit(1)
                .frame(width: DaylineViewMetrics.dayLabelWidth, alignment: .leading)

            DaylineTrackView(
                range: row.range,
                snapshot: row.snapshot,
                showsTemporalContext: row.showsTemporalContext,
                interaction: interaction,
                focusedSegmentID: $focusedSegmentID
            )

            Text(DaylineContract.compactDurationText(
                row.snapshot.totalTrackedSeconds,
                localeIdentifier: row.snapshot.localeIdentifier
            ))
                .font(.system(size: DaylineViewMetrics.meaningfulTextSize, design: .monospaced))
                .foregroundColor(.nsTextTertiary)
                .lineLimit(1)
                .frame(width: DaylineViewMetrics.dayTotalWidth, alignment: .trailing)
        }
        .frame(height: DaylineViewMetrics.dayRowHeight)
        .onChange(of: focusedSegmentID) { _, id in interaction.focus(id) }
    }
}

private struct DaylineTrackView: View {
    let range: DaylineRange
    let snapshot: DayActivitySnapshot
    let showsTemporalContext: Bool
    @ObservedObject var interaction: DaylineInteractionModel
    let focusedSegmentID: FocusState<DayActivitySegmentID?>.Binding

    var body: some View {
        GeometryReader { proxy in
            let nowFraction = range.fraction(at: snapshot.asOf)
            let markerFraction = showsTemporalContext
                ? DaylineContract.markerFraction(at: snapshot.asOf, in: range)
                : nil
            let targets = DaylineContract.renderTargets(
                for: snapshot.segments,
                in: range,
                trackWidth: proxy.size.width
            )
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.daylineElapsedTrack)
                    .frame(height: DaylineViewMetrics.trackHeight)
                    .accessibilityHidden(true)

                if showsTemporalContext {
                    Color.daylineFutureTrack
                        .frame(width: proxy.size.width * (1 - nowFraction), height: DaylineViewMetrics.trackHeight)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .accessibilityHidden(true)
                }

                ForEach(targets) { target in
                    DaylineBlock(
                        target: target,
                        snapshot: snapshot,
                        selected: interaction.pinnedSegmentID == target.segment.id
                            || interaction.focusedSegmentID == target.segment.id,
                        onPin: { interaction.pin(target.segment.id) },
                        onReset: { interaction.resetToCurrentActivity() }
                    )
                    .focused(focusedSegmentID, equals: target.segment.id)
                    .frame(
                        width: target.hitWidthPoints,
                        height: DaylineViewMetrics.minimumActionTarget
                    )
                    .offset(x: target.hitStartPoints)
                }

                if let markerFraction {
                    Rectangle()
                        .fill(Color.daylineNowMarker)
                        .frame(width: 1, height: DaylineViewMetrics.trackHeight + 4)
                        .offset(x: proxy.size.width * markerFraction - 0.5)
                        .accessibilityHidden(true)
                }

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(height: DaylineViewMetrics.minimumActionTarget)
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                if let id = DaylineContract.segmentID(at: value.location.x, in: targets) {
                                    interaction.pin(id)
                                }
                            }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            interaction.focus(DaylineContract.segmentID(at: location.x, in: targets))
                        case .ended:
                            interaction.focus(nil)
                        }
                    }
                    .accessibilityHidden(true)
            }
            .frame(height: DaylineViewMetrics.dayRowHeight)
        }
        .frame(height: DaylineViewMetrics.dayRowHeight)
    }
}

private struct DaylineBlock: View {
    let target: DaylineRenderTarget
    let snapshot: DayActivitySnapshot
    let selected: Bool
    let onPin: () -> Void
    let onReset: () -> Void

    private var segment: DayActivitySegment { target.segment }

    var body: some View {
        Button(action: onPin) {
            Color.clear
                .contentShape(Rectangle())
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.daylineCategory(segment.categoryHex))
                        .frame(
                            width: target.visibleWidthPoints,
                            height: DaylineViewMetrics.trackHeight
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(
                                    selected || segment.isActive ? Color.daylineSelected : Color.black.opacity(0.65),
                                    style: StrokeStyle(
                                        lineWidth: target.geometry.minimumStrokePoints,
                                        lineCap: .round,
                                        dash: DaylineContract.pattern(for: segment.categoryID).dash.map { CGFloat($0) }
                                    )
                                )
                        }
                        .offset(x: target.visibleOffsetPoints)
                        .allowsHitTesting(false)
                }
        }
        .buttonStyle(.plain)
        .frame(minHeight: DaylineViewMetrics.minimumActionTarget)
        .focusable()
        .accessibilityLabel(DaylineContract.segmentAccessibilityLabel(
            segment,
            snapshot: snapshot,
            selected: selected
        ))
        .accessibilityIdentifier(DaylineContract.segmentAccessibilityIdentifier(segment.id))
        .accessibilityValue(selected ? "Selected" : (segment.isActive ? "Active" : ""))
        .accessibilityAction(named: Text("현재 활동으로 돌아가기"), onReset)
    }
}

private struct DaylinePatternSwatch: View {
    let segment: DayActivitySegment

    var body: some View {
        Capsule()
            .stroke(
                Color.daylineCategory(segment.categoryHex),
                style: StrokeStyle(
                    lineWidth: 2,
                    lineCap: .round,
                    dash: DaylineContract.pattern(for: segment.categoryID).dash.map { CGFloat($0) }
                )
            )
            .frame(width: 20, height: 6)
            .accessibilityHidden(true)
    }
}
