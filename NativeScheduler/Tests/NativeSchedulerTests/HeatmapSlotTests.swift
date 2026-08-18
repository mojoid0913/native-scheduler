import AppKit
import SwiftUI
import XCTest
@testable import NativeScheduler

final class HeatmapSlotTests: XCTestCase {
    func testLastSlotRollsIntoNextDayBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let baseDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 12, hour: 9, minute: 0))!
        let slot = HeatmapSlot(hour: 23, row: 3)

        let (start, end) = slot.dateRange(on: baseDate, calendar: calendar)

        XCTAssertEqual(calendar.component(.day, from: start), 12)
        XCTAssertEqual(calendar.component(.hour, from: start), 23)
        XCTAssertEqual(calendar.component(.minute, from: start), 45)

        XCTAssertEqual(calendar.component(.day, from: end), 13)
        XCTAssertEqual(calendar.component(.hour, from: end), 0)
        XCTAssertEqual(calendar.component(.minute, from: end), 0)
        XCTAssertEqual(end.timeIntervalSince(start), 900, accuracy: 0.001)
    }

    func testMidHourSlotKeepsFifteenMinuteWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let baseDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 12, hour: 9, minute: 0))!
        let slot = HeatmapSlot(hour: 14, row: 1)

        let (start, end) = slot.dateRange(on: baseDate, calendar: calendar)

        XCTAssertEqual(calendar.component(.hour, from: start), 14)
        XCTAssertEqual(calendar.component(.minute, from: start), 15)
        XCTAssertEqual(calendar.component(.hour, from: end), 14)
        XCTAssertEqual(calendar.component(.minute, from: end), 30)
        XCTAssertEqual(end.timeIntervalSince(start), 900, accuracy: 0.001)
    }

    func testHeatmapUsesFourRowsPerHour() {
        XCTAssertEqual(HeatmapSlot.rowsPerHour, 4)
        XCTAssertEqual(HeatmapSlot.minutesPerSlot, 15)
        XCTAssertEqual(HeatmapSlot.all.count, 96)
        XCTAssertEqual(HeatmapSlot(hour: 14, row: 1).index, 57)
    }

    func testDaylineCompactRangeClampsAndTracksNowFraction() {
        let calendar = utcCalendar()
        let expectedHours = [(0, 0, 8, 0.0625), (12, 10, 18, 0.3125), (23, 16, 0, 0.9375)]

        for (nowHour, expectedStartHour, expectedEndHour, expectedFraction) in expectedHours {
            let snapshot = snapshot(
                calendar: calendar,
                asOf: date(calendar, 2026, 4, 12, nowHour, 30)
            )
            let range = DaylineContract.compactRange(for: snapshot)

            XCTAssertEqual(calendar.component(.hour, from: range.start), expectedStartHour)
            XCTAssertEqual(calendar.component(.minute, from: range.start), 0)
            XCTAssertEqual(calendar.component(.hour, from: range.end), expectedEndHour)
            XCTAssertEqual(range.duration, 8 * 60 * 60, accuracy: 0.001)
            XCTAssertEqual(range.fraction(at: snapshot.asOf), expectedFraction, accuracy: 0.0001)
            if nowHour == 0 {
                XCTAssertEqual(
                    DaylineContract.compactTickDates(for: range, snapshot: snapshot).map {
                        calendar.component(.hour, from: $0)
                    },
                    [0, 2, 4, 6, 8]
                )
            }
        }
    }

    @MainActor
    func testCompactDetailFitsTheLiveTwoXShellWithoutEllipsis() throws {
        let calendar = utcCalendar()
        let start = date(calendar, 2026, 4, 12, 16, 17)
        let end = date(calendar, 2026, 4, 12, 16, 19)
        let segment = segment(id: UUID(), categoryName: "Default", start: start, end: end, isActive: true)
        let snapshot = snapshot(calendar: calendar, asOf: end, segments: [segment], activeID: segment.id)
        let label = DaylineContract.compactSegmentDetailLabel(segment, snapshot: snapshot)
        let shell = CGSize(width: 220, height: 38)
        let contentWidth = shell.width - 24 - 20 - 6
        let font = NSFont.systemFont(ofSize: DaylineViewMetrics.meaningfulTextSize)
        let bounds = (label as NSString).boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )

        XCTAssertEqual(shell.width * 2, 440, accuracy: 0.001)
        XCTAssertEqual(shell.height * 2, 76, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(DaylineViewMetrics.meaningfulTextSize, 11)
        XCTAssertLessThanOrEqual(
            bounds.height,
            font.boundingRectForFont.height + 1,
            "The live 440×76 compact shell must show category, range, duration, and active state without ellipsis."
        )
        XCTAssertEqual(label, "Default, 16:17–16:19, 2m, Live")

        let root = DaylineView(snapshot: snapshot, isExpanded: false)
            .frame(width: 232, height: 120.11)
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(x: 0, y: 0, width: 232, height: 120.11)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let image = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: image)
        XCTAssertGreaterThan(image.pixelsWide, 0)
        XCTAssertGreaterThan(image.pixelsHigh, 0)
        if let output = ProcessInfo.processInfo.environment["COMPACT_DAYLINE_RENDER_OUTPUT"] {
            try XCTUnwrap(image.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: output))
        }
    }

    func testCompactSubminuteDetailFitsTheActualCollapsedPanelWidth() {
        let calendar = utcCalendar()
        let instant = date(calendar, 2026, 4, 12, 16, 54)
        let segment = segment(
            id: UUID(),
            categoryName: "Default",
            start: instant,
            end: instant.addingTimeInterval(1),
            isActive: true
        )
        let snapshot = snapshot(
            calendar: calendar,
            asOf: instant.addingTimeInterval(1),
            segments: [segment],
            activeID: segment.id
        )
        let label = DaylineContract.compactSegmentDetailLabel(segment, snapshot: snapshot)
        let layout = MainPanelLayoutMetrics(width: 776, height: 321, isDaylineExpanded: false)
        let font = NSFont.systemFont(ofSize: DaylineViewMetrics.meaningfulTextSize)
        let bounds = (label as NSString).boundingRect(
            with: CGSize(
                width: layout.rightWidth - 24 - 20 - 6,
                height: .greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )

        XCTAssertEqual(label, "Default, 16:54–16:54, <1m, Live")
        XCTAssertLessThanOrEqual(
            bounds.height,
            font.boundingRectForFont.height + 1,
            "The exact collapsed panel width must not ellipsize a live subminute detail."
        )
    }

    func testDaylineExpandedAnchorsPreserveActualDSTDayLengths() {
        let losAngeles = calendar(timeZoneID: "America/Los_Angeles")

        for (month, day, expectedHours) in [(3, 8, 23.0), (4, 12, 24.0), (11, 1, 25.0)] {
            let snapshot = snapshot(
                calendar: losAngeles,
                asOf: date(losAngeles, 2026, month, day, 12, 0)
            )
            let window = DayActivityWindowSnapshot(days: [snapshot], hasFetchError: false, recoveryWarningCount: 0)
            let row = try! XCTUnwrap(DaylineContract.expandedRows(for: window).first)

            XCTAssertEqual(row.label, "Today")
            XCTAssertEqual(row.range.start, snapshot.dayStart)
            XCTAssertEqual(row.range.end, snapshot.nextDayStart)
            XCTAssertEqual(row.range.duration, expectedHours * 60 * 60, accuracy: 0.001)
        }
    }

    func testExpandedDaylinePresentsFiveNewestFirstLocalDaysWithOneSharedAxis() {
        let calendar = utcCalendar()
        let days = (0..<5).map { offset in
            snapshot(
                calendar: calendar,
                asOf: date(calendar, 2026, 4, 12 - offset, 12, 0)
            )
        }
        let window = DayActivityWindowSnapshot(
            days: days,
            hasFetchError: false,
            recoveryWarningCount: 0
        )

        let rows = DaylineContract.expandedRows(for: window)

        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows.map(\.snapshot.dayStart), days.map(\.dayStart))
        XCTAssertEqual(rows.map(\.label), ["Today", "Sat 4/11", "Fri 4/10", "Thu 4/9", "Wed 4/8"])
        XCTAssertEqual(rows.map(\.showsTemporalContext), [true, false, false, false, false])
        XCTAssertEqual(DaylineContract.expandedAxisLabels, ["00", "06", "12", "18", "24"])
        XCTAssertTrue(rows.allSatisfy { $0.range.start == $0.snapshot.dayStart })
        XCTAssertTrue(rows.allSatisfy { $0.range.end == $0.snapshot.nextDayStart })
    }

    func testExpandedDaylineDensityAndAccessibilityOrderStayInsideTheFiveRows() {
        let calendar = utcCalendar()
        let days = (0..<5).map { offset -> DayActivitySnapshot in
            let asOf = date(calendar, 2026, 4, 12 - offset, 12, 0)
            let activity = segment(
                id: UUID(),
                start: asOf.addingTimeInterval(-60),
                end: asOf
            )
            return snapshot(calendar: calendar, asOf: asOf, segments: [activity])
        }
        let order = DaylineInteractionState().accessibilityOrder(in: days)

        XCTAssertEqual(DaylineViewMetrics.expandedInset, 4, accuracy: 0.001)
        XCTAssertEqual(DaylineViewMetrics.dayRowHeight, 20, accuracy: 0.001)
        XCTAssertEqual(DaylineViewMetrics.trackHeight, 10, accuracy: 0.001)
        XCTAssertEqual(DaylineViewMetrics.meaningfulTextSize, 11, accuracy: 0.001)
        XCTAssertEqual(DaylineViewMetrics.minimumActionTarget, 24, accuracy: 0.001)
        XCTAssertEqual(Array(order.prefix(2)), [DaylineAccessibilityItem.header, .toggle])
        XCTAssertEqual(
            Array(order.dropFirst(2)),
            days.flatMap { $0.segments.map { .segment($0.id) } }
        )
    }

    func testTodaySummaryShowsTopThreeCategoriesAndAggregatesTheRestIntoEtc() {
        let calendar = utcCalendar()
        let asOf = date(calendar, 2026, 4, 12, 12, 0)
        let totals = [500.0, 400, 300, 200, 100].enumerated().map { index, seconds in
            DayActivityCategoryTotal(
                categoryID: UUID(uuidString: String(format: "A0000000-0000-0000-0000-%012d", index + 1)),
                categoryName: "Category \(index + 1)",
                categoryHex: index == 0 ? Color.resolvedCategoryHex(nil) : "#FF922B",
                seconds: seconds
            )
        }
        let base = snapshot(calendar: calendar, asOf: asOf)
        let populated = DayActivitySnapshot(
            segments: [],
            categoryTotals: totals,
            totalTrackedSeconds: totals.reduce(0) { $0 + $1.seconds },
            activeOrMostRecentID: nil,
            asOf: base.asOf,
            dayStart: base.dayStart,
            nextDayStart: base.nextDayStart,
            calendarIdentifier: base.calendarIdentifier,
            localeIdentifier: base.localeIdentifier,
            timeZoneIdentifier: base.timeZoneIdentifier
        )

        let entries = TodayUsageSummaryProjection.compactEntries(for: populated)

        XCTAssertEqual(entries.map(\.name), ["Category 1", "Category 2", "Category 3", "Etc"])
        XCTAssertEqual(try! XCTUnwrap(entries.last).seconds, 300, accuracy: 0.001)
        XCTAssertLessThanOrEqual(entries.count, 4)
    }

    func testDaylineSegmentGeometryClipsExactlyAndUsesStrokeForShortBlocks() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let range = DaylineRange(start: start, end: start.addingTimeInterval(60 * 60))
        let categoryID = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!

        let clipped = segment(
            id: categoryID,
            start: start.addingTimeInterval(-30 * 60),
            end: start.addingTimeInterval(30 * 60)
        )
        let geometry = try! XCTUnwrap(DaylineContract.segmentGeometry(for: clipped, in: range))
        XCTAssertEqual(geometry.startFraction, 0, accuracy: 0.0001)
        XCTAssertEqual(geometry.endFraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(geometry.fillFraction, 0.5, accuracy: 0.0001)

        let oneSecond = segment(id: categoryID, start: start, end: start.addingTimeInterval(1))
        let oneSecondGeometry = try! XCTUnwrap(DaylineContract.segmentGeometry(for: oneSecond, in: range))
        XCTAssertEqual(oneSecondGeometry.fillFraction, 1 / 3600, accuracy: 0.0001)
        XCTAssertEqual(oneSecondGeometry.minimumStrokePoints, 1, accuracy: 0.0001)

        let zeroWidth = segment(id: categoryID, start: start, end: start)
        XCTAssertNil(DaylineContract.segmentGeometry(for: zeroWidth, in: range))
    }

    func testDaylineShortSegmentsKeepProportionalInkAndExactPointerSelectionAtTwentyFourPoints() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let range = DaylineRange(start: start, end: start.addingTimeInterval(24 * 60 * 60))
        func shortSegment(at hour: Int) -> DayActivitySegment {
            let segmentStart = start.addingTimeInterval(TimeInterval(hour) * 60 * 60)
            return segment(
                id: UUID(),
                start: segmentStart,
                end: segmentStart.addingTimeInterval(30 * 60)
            )
        }
        let segments = [shortSegment(at: 2), shortSegment(at: 6), shortSegment(at: 10)]

        let targets = DaylineContract.renderTargets(for: segments, in: range, trackWidth: 600)

        XCTAssertEqual(targets.count, 3)
        for target in targets {
            XCTAssertEqual(target.visibleWidthPoints, 12.5, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(target.hitWidthPoints, DaylineViewMetrics.minimumActionTarget)
            XCTAssertGreaterThanOrEqual(target.visibleOffsetPoints, 0)
            XCTAssertLessThanOrEqual(
                target.visibleOffsetPoints + target.visibleWidthPoints,
                target.hitWidthPoints + 0.001
            )
        }
        for pair in zip(targets, targets.dropFirst()) {
            XCTAssertLessThanOrEqual(
                pair.0.hitStartPoints + pair.0.hitWidthPoints,
                pair.1.hitStartPoints + 0.001
            )
        }

        let adjacent = [0, 30, 60].map { minute -> DayActivitySegment in
            let segmentStart = start.addingTimeInterval(TimeInterval(6 * 60 + minute) * 60)
            return segment(
                id: UUID(),
                start: segmentStart,
                end: segmentStart.addingTimeInterval(30 * 60)
            )
        }
        let adjacentTargets = DaylineContract.renderTargets(
            for: adjacent,
            in: range,
            trackWidth: 600
        )
        XCTAssertEqual(adjacentTargets.count, 3)
        for target in adjacentTargets {
            XCTAssertGreaterThanOrEqual(target.hitWidthPoints, DaylineViewMetrics.minimumActionTarget)
            let visibleCenter = target.hitStartPoints
                + target.visibleOffsetPoints
                + target.visibleWidthPoints / 2
            XCTAssertEqual(
                DaylineContract.segmentID(at: visibleCenter, in: adjacentTargets),
                target.segment.id
            )
        }
    }

    func testDaylineTokensAndSemanticsAreDeterministicAndComplete() {
        let losAngeles = calendar(timeZoneID: "America/Los_Angeles")
        let asOf = date(losAngeles, 2026, 11, 1, 12, 0)
        let categoryID = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
        let firstRepeatedHour = ISO8601DateFormatter().date(from: "2026-11-01T01:30:00-07:00")!
        let secondRepeatedHour = ISO8601DateFormatter().date(from: "2026-11-01T01:30:00-08:00")!
        let activity = segment(
            id: categoryID,
            categoryName: "매우 긴 집중 작업 카테고리 이름",
            start: firstRepeatedHour,
            end: secondRepeatedHour,
            isActive: true
        )
        let snapshot = snapshot(calendar: losAngeles, asOf: asOf, segments: [activity])

        XCTAssertEqual(DaylineContract.title, "Stream")
        XCTAssertEqual(DaylineContract.pattern(for: categoryID), DaylineContract.pattern(for: categoryID))
        XCTAssertNotEqual(DaylineContract.pattern(for: categoryID), DaylineContract.pattern(for: nil))
        XCTAssertTrue(DaylineContract.pattern(for: nil).isDefault)
        XCTAssertEqual(Color.resolvedCategoryHex("not-a-color"), Color.resolvedCategoryHex(nil))

        XCTAssertEqual(DaylineContract.durationText(0, localeIdentifier: "en_US"), "0 minutes")
        XCTAssertEqual(DaylineContract.durationText(0, localeIdentifier: "ko_KR"), "0분")
        XCTAssertEqual(DaylineContract.durationText(59, localeIdentifier: "en_US"), "Under 1 minute")
        XCTAssertEqual(DaylineContract.durationText(60, localeIdentifier: "en_US"), "1 minute")
        XCTAssertEqual(DaylineContract.compactDurationText(0, localeIdentifier: "en_US"), "0m")
        XCTAssertEqual(DaylineContract.compactDurationText(0, localeIdentifier: "ko_KR"), "0분")
        XCTAssertEqual(DaylineContract.compactDurationText(59, localeIdentifier: "en_US"), "<1m")
        let detail = DaylineContract.segmentAccessibilityLabel(activity, snapshot: snapshot)
        XCTAssertTrue(detail.contains("매우 긴 집중 작업 카테고리 이름"))
        XCTAssertTrue(detail.contains("-07:00"))
        XCTAssertTrue(detail.contains("-08:00"))
        XCTAssertTrue(detail.contains("Active"))
        XCTAssertTrue(
            DaylineContract.segmentAccessibilityLabel(activity, snapshot: snapshot, selected: true)
                .hasSuffix("Selected")
        )
        let defaultActivity = DayActivitySegment(
            id: DayActivitySegmentID(sessionID: categoryID, winningPieceStart: asOf),
            categoryID: nil,
            categoryName: "",
            categoryHex: Color.resolvedCategoryHex(nil),
            start: asOf,
            end: asOf.addingTimeInterval(60),
            isActive: false
        )
        XCTAssertTrue(DaylineContract.segmentAccessibilityLabel(defaultActivity, snapshot: snapshot).hasPrefix("Default, "))
        XCTAssertEqual(
            DaylineContract.headerAccessibilityLabel(snapshot),
            "Stream, 오늘 기록 1 hour"
        )
    }

    func testDaylineRepeatedFallBackHourIncludesOffsetsInVisibleAndSpokenLabels() {
        let losAngeles = calendar(timeZoneID: "America/Los_Angeles")
        let asOf = date(losAngeles, 2026, 11, 1, 12, 0)
        let categoryID = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
        let occurrences = [
            ("2026-11-01T01:10:00-07:00", "2026-11-01T01:20:00-07:00", "-07:00"),
            ("2026-11-01T01:10:00-08:00", "2026-11-01T01:20:00-08:00", "-08:00")
        ]

        for (startText, endText, expectedOffset) in occurrences {
            let activity = segment(
                id: categoryID,
                start: ISO8601DateFormatter().date(from: startText)!,
                end: ISO8601DateFormatter().date(from: endText)!
            )
            let snapshot = snapshot(calendar: losAngeles, asOf: asOf, segments: [activity])
            let visible = DaylineContract.segmentDetailLabel(activity, snapshot: snapshot)
            let spoken = DaylineContract.spokenRangeLabel(
                start: activity.start,
                end: activity.end,
                snapshot: snapshot
            )

            XCTAssertTrue(visible.contains("01:10 \(expectedOffset)"))
            XCTAssertTrue(visible.contains("01:20 \(expectedOffset)"))
            XCTAssertTrue(spoken.contains("01:10 \(expectedOffset)"))
            XCTAssertTrue(spoken.contains("01:20 \(expectedOffset)"))
        }
    }

    func testDaylineInteractionRetainsSplitIdentityAcrossLiveTickAndDropsMissingPin() {
        let calendar = utcCalendar()
        let asOf = date(calendar, 2026, 4, 12, 12, 0)
        let sessionID = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
        let first = segment(id: sessionID, start: date(calendar, 2026, 4, 12, 9, 0), end: date(calendar, 2026, 4, 12, 10, 0))
        let splitID = DayActivitySegmentID(sessionID: sessionID, winningPieceStart: date(calendar, 2026, 4, 12, 11, 0))
        let split = DayActivitySegment(
            id: splitID,
            categoryID: sessionID,
            categoryName: "Focus",
            categoryHex: "#123456",
            start: date(calendar, 2026, 4, 12, 11, 0),
            end: asOf,
            isActive: true
        )
        let currentSnapshot = snapshot(calendar: calendar, asOf: asOf, segments: [first, split], activeID: splitID)
        var state = DaylineInteractionState()

        XCTAssertEqual(state.detailID(in: currentSnapshot), splitID)
        state.pin(first.id)
        state.focus(splitID)
        XCTAssertEqual(state.detailID(in: currentSnapshot), first.id)

        let ticking = snapshot(calendar: calendar, asOf: asOf.addingTimeInterval(1), segments: [first, split])
        state.reconcile(with: ticking)
        XCTAssertEqual(state.pinnedSegmentID, first.id)
        XCTAssertEqual(state.focusedSegmentID, splitID)

        state.reconcile(with: snapshot(calendar: calendar, asOf: asOf, segments: [split]))
        XCTAssertNil(state.pinnedSegmentID)
        XCTAssertEqual(state.detailID(in: snapshot(calendar: calendar, asOf: asOf, segments: [split])), splitID)
    }

    func testDaylineAccessibilityOrderControlCopyAndMotionAreDeterministic() {
        let calendar = utcCalendar()
        let asOf = date(calendar, 2026, 4, 12, 12, 0)
        let first = segment(id: UUID(), start: date(calendar, 2026, 4, 12, 9, 0), end: date(calendar, 2026, 4, 12, 10, 0))
        let second = segment(id: UUID(), start: date(calendar, 2026, 4, 12, 10, 0), end: date(calendar, 2026, 4, 12, 11, 0))
        let populatedSnapshot = snapshot(calendar: calendar, asOf: asOf, segments: [first, second])
        let state = DaylineInteractionState()

        XCTAssertEqual(
            state.accessibilityOrder(in: populatedSnapshot),
            [.header, .toggle, .segment(first.id), .segment(second.id)]
        )
        XCTAssertEqual(state.keyboardOrder(in: populatedSnapshot), [.toggle, .segment(first.id), .segment(second.id)])
        XCTAssertEqual(DaylineViewControl.label(isExpanded: false), "최근 5일 보기")
        XCTAssertEqual(DaylineViewControl.label(isExpanded: true), "오늘만 보기")
        XCTAssertEqual(DaylineViewControl.symbol(isExpanded: false), "chevron.left")
        XCTAssertEqual(DaylineViewControl.symbol(isExpanded: true), "chevron.right")
        XCTAssertEqual(DaylineMotion.style(reduceMotion: true), .none)
        XCTAssertEqual(DaylineMotion.style(reduceMotion: false), .layoutMorph)
        XCTAssertNil(state.detailID(in: snapshot(calendar: calendar, asOf: asOf)))
    }

    func testDaylineSemanticRolesAndExpansionMotionContract() {
        XCTAssertEqual(Color.daylineElapsedTrack.hexString, "#3A3A3A")
        XCTAssertEqual(Color.daylineFutureTrack.hexString, "#252525")
        XCTAssertEqual(Color.daylineNowMarker.hexString, "#CCCCCC")
        XCTAssertEqual(Color.daylineSelected.hexString, "#EFEFEF")
        XCTAssertNil(DaylineMotion.expansionAnimation(reduceMotion: true))
        XCTAssertNotNil(DaylineMotion.expansionAnimation(reduceMotion: false))
    }

    func testDefaultCategoryBlueResolvesAcrossTimerNotchAndDaylineConsumers() {
        let defaultHex = "#4DABF7"
        let fallbackInputs: [String?] = [nil, "", " \n ", "#123", "#12GG00"]

        XCTAssertEqual(Color.nsDefaultCategory.hexString, defaultHex)
        XCTAssertEqual(Color.daylineDefaultCategory.hexString, defaultHex)
        XCTAssertEqual(Color.resolvedCategoryHex("#abcdef"), "#ABCDEF")

        for input in fallbackInputs {
            XCTAssertEqual(Color.resolvedCategoryHex(input), defaultHex)
        }

        XCTAssertEqual(TimerViewModel.resolvedThemeColorHex(nil), defaultHex)
        XCTAssertEqual(TimerView.defaultCategoryColorHex, defaultHex)
        XCTAssertEqual(NotchTimerSnapshot().categoryColorHex, defaultHex)
        XCTAssertEqual(
            NotchTimerSnapshot(categoryColorHex: Color.resolvedCategoryHex("#ff922b")).categoryColorHex,
            "#FF922B"
        )

        let defaultSegment = segment(
            id: UUID(),
            start: Date(timeIntervalSinceReferenceDate: 0),
            end: Date(timeIntervalSinceReferenceDate: 60)
        )
        let renderedDaylineColor = Color.daylineCategory(Color.resolvedCategoryHex(nil)).hexString
        XCTAssertEqual(renderedDaylineColor, defaultHex)
        XCTAssertEqual(defaultSegment.categoryHex, "#123456")

        XCTAssertEqual(Color.daylineElapsedTrack.hexString, "#3A3A3A")
        XCTAssertEqual(Color.daylineFutureTrack.hexString, "#252525")
        XCTAssertNotEqual(defaultHex, Color.daylineElapsedTrack.hexString)
        XCTAssertNotEqual(defaultHex, Color.daylineFutureTrack.hexString)

        if let outputPath = ProcessInfo.processInfo.environment["TASK_3_MATRIX_OUTPUT"] {
            let matrix: [String: String] = [
                "daylineDefault": renderedDaylineColor,
                "elapsedTrack": Color.daylineElapsedTrack.hexString,
                "futureTrack": Color.daylineFutureTrack.hexString,
                "notchDefault": NotchTimerSnapshot().categoryColorHex,
                "notchOrange": NotchTimerSnapshot(categoryColorHex: Color.resolvedCategoryHex("#ff922b")).categoryColorHex,
                "timerBorderAndChip": TimerViewModel.resolvedThemeColorHex(nil),
                "timerPicker": TimerView.defaultCategoryColorHex
            ]
            try! JSONSerialization.data(withJSONObject: matrix, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: outputPath))
        }
    }

    @MainActor
    func testNotchRingRendersDefaultAndCustomCategoryPixels() throws {
        try assertInactiveCompletionLayerLeavesNoTransparentSemanticRedInHostedPixels()
        let outputDirectory = ProcessInfo.processInfo.environment["TASK_3_RENDER_OUTPUT"]
        let cases = [("default", Color.resolvedCategoryHex(nil)), ("orange", Color.resolvedCategoryHex("#ff922b"))]
        var renderedSamples: [String: Any] = [:]

        for (name, hex) in cases {
            let image = try renderNotchRing(categoryHex: hex)
            let sample = closestPixel(to: hex, in: image)
            XCTAssertLessThan(sample.distance, 0.05, "\(name) ring must render \(hex); sampled \(sample.hex)")
            XCTAssertLessThan(sample.distance, closestPixel(to: Color.daylineElapsedTrack.hexString, in: image).distance)
            XCTAssertLessThan(sample.distance, closestPixel(to: Color.daylineFutureTrack.hexString, in: image).distance)
            renderedSamples[name] = ["hex": sample.hex, "distance": sample.distance]

            if let outputDirectory {
                let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: directory.appending(path: "\(name)-notch-ring.png"))
            }
        }

        if let outputDirectory {
            let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
            let sampling: [String: Any] = [
                "default": Color.resolvedCategoryHex(nil),
                "orange": Color.resolvedCategoryHex("#ff922b"),
                "elapsedTrack": Color.daylineElapsedTrack.hexString,
                "futureTrack": Color.daylineFutureTrack.hexString,
                "renderedSamples": renderedSamples
            ]
            let data = try JSONSerialization.data(withJSONObject: sampling, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appending(path: "pixel-sampling.json"))
        }
    }

    @MainActor
    private func assertInactiveCompletionLayerLeavesNoTransparentSemanticRedInHostedPixels() throws {
        let timerState = NotchTimerState()
        let root = AnyView(NotchView(
            windowState: NotchWindowState(),
            timerState: timerState,
            notchSize: CGSize(width: 184, height: 32),
            expandedContent: AnyView(EmptyView()),
            onQuit: {}
        ).frame(width: NotchGeometry.expandedPanelWidth, height: 53))
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(x: 0, y: 0, width: NotchGeometry.expandedPanelWidth, height: 53)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        func borderView(in view: NSView) -> NSView? {
            if String(describing: type(of: view)) == "CompletionBorderLayerView" { return view }
            return view.subviews.lazy.compactMap(borderView(in:)).first
        }
        if let nativeBorder = borderView(in: host) {
            let stroke = try XCTUnwrap(nativeBorder.layer?.sublayers?.first as? CAShapeLayer)
            XCTAssertTrue(
                stroke.isHidden || stroke.strokeColor == nil,
                "The inactive native layer must be absent, hidden, or clear its semantic-red stroke color."
            )
        }

        let image = try renderNotchRing(categoryHex: Color.resolvedCategoryHex(nil))
        var transparentRedPixels = 0
        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.alphaComponent <= 0.01,
                   color.redComponent > 0.6,
                   color.redComponent > color.greenComponent * 2,
                   color.redComponent > color.blueComponent * 2 {
                    transparentRedPixels += 1
                }
            }
        }

        XCTAssertEqual(
            transparentRedPixels,
            0,
            "An inactive completion layer must not retain semantic-red RGB beneath zero alpha."
        )
    }

    @MainActor
    func testDaylineErrorWarningAndCategorySemanticContracts() {
        let calendar = utcCalendar()
        let asOf = date(calendar, 2026, 4, 12, 12, 0)
        let errorView = DaylineView(
            snapshot: snapshot(calendar: calendar, asOf: asOf),
            isExpanded: false,
            hasFetchError: true
        )

        XCTAssertTrue(errorView.hasFetchError)
        XCTAssertNil(DaylineWarning.message(hasFetchError: false))
        XCTAssertEqual(DaylineWarning.message(hasFetchError: true), "Activity data may be out of date. Retry.")
        XCTAssertNil(DaylineWarning.message(hasFetchError: false, recoveryWarningCount: 2))
        XCTAssertEqual(Color.daylineError.hexString, "#FFA94D")
        XCTAssertEqual(Color.daylineCategory("#abcdef").hexString, "#ABCDEF")
        XCTAssertEqual(Color.daylineCategory(nil).hexString, Color.daylineDefaultCategory.hexString)
        XCTAssertEqual(Color.daylineCategory("invalid").hexString, Color.daylineDefaultCategory.hexString)
    }

    func testDaylineMarkerAppearsOnlyInTheHalfOpenLaneContainingNow() {
        let calendar = utcCalendar()
        let noon = date(calendar, 2026, 4, 12, 12, 0)
        let snapshot = snapshot(calendar: calendar, asOf: noon)
        let compact = DaylineContract.compactRange(for: snapshot)
        let expanded = DaylineContract.expandedRows(
            for: DayActivityWindowSnapshot(days: [snapshot], hasFetchError: false, recoveryWarningCount: 0)
        )

        XCTAssertEqual(
            try! XCTUnwrap(DaylineContract.markerFraction(at: noon, in: compact)),
            0.25,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            expanded.map { DaylineContract.markerFraction(at: noon, in: $0.range) != nil },
            [true]
        )

        let boundarySnapshot = DayActivitySnapshot(
            segments: [],
            categoryTotals: [],
            totalTrackedSeconds: 0,
            activeOrMostRecentID: nil,
            asOf: snapshot.nextDayStart,
            dayStart: snapshot.dayStart,
            nextDayStart: snapshot.nextDayStart,
            calendarIdentifier: snapshot.calendarIdentifier,
            localeIdentifier: snapshot.localeIdentifier,
            timeZoneIdentifier: snapshot.timeZoneIdentifier
        )
        XCTAssertTrue(
            DaylineContract.expandedRows(
                for: DayActivityWindowSnapshot(days: [boundarySnapshot], hasFetchError: false, recoveryWarningCount: 0)
            ).allSatisfy {
                DaylineContract.markerFraction(at: boundarySnapshot.asOf, in: $0.range) == nil
            }
        )
    }

    private func snapshot(
        calendar: Calendar,
        asOf: Date,
        segments: [DayActivitySegment] = [],
        activeID: DayActivitySegmentID? = nil
    ) -> DayActivitySnapshot {
        let dayStart = calendar.startOfDay(for: asOf)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let total = segments.reduce(0) { $0 + $1.duration }
        return DayActivitySnapshot(
            segments: segments,
            categoryTotals: [],
            totalTrackedSeconds: total,
            activeOrMostRecentID: activeID ?? segments.first?.id,
            asOf: asOf,
            dayStart: dayStart,
            nextDayStart: nextDayStart,
            calendarIdentifier: String(describing: calendar.identifier),
            localeIdentifier: "en_US",
            timeZoneIdentifier: calendar.timeZone.identifier
        )
    }

    private func segment(
        id: UUID,
        categoryName: String = "Focus",
        start: Date,
        end: Date,
        isActive: Bool = false
    ) -> DayActivitySegment {
        DayActivitySegment(
            id: DayActivitySegmentID(sessionID: id, winningPieceStart: start),
            categoryID: id,
            categoryName: categoryName,
            categoryHex: "#123456",
            start: start,
            end: end,
            isActive: isActive
        )
    }

    private func utcCalendar() -> Calendar {
        calendar(timeZoneID: "GMT")
    }

    private func calendar(timeZoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        return calendar
    }

    private func date(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        )!
    }

    @MainActor
    private func renderNotchRing(categoryHex: String) throws -> NSBitmapImageRep {
        let timerState = NotchTimerState()
        timerState.update(NotchTimerSnapshot(isRunning: true, progress: 0.75, categoryColorHex: categoryHex))
        let root = AnyView(NotchView(
            windowState: NotchWindowState(),
            timerState: timerState,
            notchSize: CGSize(width: 184, height: 32),
            expandedContent: AnyView(EmptyView()),
            onQuit: {}
        ).frame(width: NotchGeometry.expandedPanelWidth, height: 53))
        let host = NSHostingView(rootView: root)
        let frame = CGRect(x: 0, y: 0, width: NotchGeometry.expandedPanelWidth, height: 53)
        host.frame = frame
        host.layoutSubtreeIfNeeded()
        let renderer = ImageRenderer(content: root)
        renderer.proposedSize = ProposedViewSize(frame.size)
        renderer.scale = 2
        return NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
    }

    private func closestPixel(to hex: String, in image: NSBitmapImageRep) -> (hex: String, distance: Double) {
        let expected = NSColor(Color(hex: hex)).usingColorSpace(.sRGB)!
        var closest = (hex: "#000000", distance: Double.infinity)
        for y in 0 ..< image.pixelsHigh {
            for x in 0 ..< image.pixelsWide {
                guard let pixel = image.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let distance = max(
                    abs(pixel.redComponent - expected.redComponent),
                    abs(pixel.greenComponent - expected.greenComponent),
                    abs(pixel.blueComponent - expected.blueComponent)
                )
                if distance < closest.distance {
                    closest = (
                        String(format: "#%02X%02X%02X", Int((pixel.redComponent * 255).rounded()), Int((pixel.greenComponent * 255).rounded()), Int((pixel.blueComponent * 255).rounded())),
                        distance
                    )
                }
            }
        }
        return closest
    }
}
