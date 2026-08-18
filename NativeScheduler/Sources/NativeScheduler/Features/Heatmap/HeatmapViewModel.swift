// NativeScheduler/Sources/NativeScheduler/Features/Heatmap/HeatmapViewModel.swift
@preconcurrency import Foundation
import CoreData
import Combine
import SwiftUI

@MainActor
final class HeatmapViewModel: ObservableObject {
    /// Slot array (index = hour * rowsPerHour + row). nil = no activity.
    @Published private(set) var slots: [Int: SlotInfo] = [:]

    private let stack = CoreDataStack.shared
    private let sessionFetcher: (Date, Date) -> [SessionEntity]
    private var observer: NSObjectProtocol?
    private var lastLiveSlotIndex: Int?
    private var lastLiveDayStart: Date?

    struct SlotInfo {
        let color: Color
        let categoryName: String
        let dominantMinutes: Int
    }

    init(
        sessionFetcher: ((Date, Date) -> [SessionEntity])? = nil,
        observesChanges: Bool = true
    ) {
        self.sessionFetcher = sessionFetcher ?? { [stack] slotStart, slotEnd in
            let request = NSFetchRequest<SessionEntity>(entityName: "SessionEntity")
            request.predicate = NSPredicate(
                format: "startTime < %@ AND (endTime == nil OR endTime > %@)",
                slotEnd as NSDate,
                slotStart as NSDate
            )
            return (try? stack.viewContext.fetch(request)) ?? []
        }

        reload()
        if observesChanges {
            observeChanges()
        }
    }

    // MARK: - Reload

    func reload(now: Date = Date(), calendar: Calendar = .current) {
        var newSlots: [Int: SlotInfo] = [:]

        for slot in HeatmapSlot.all {
            let (slotStart, slotEnd) = slot.dateRange(on: now, calendar: calendar)
            let sessions = sessionFetcher(slotStart, slotEnd)
            if let info = makeSlotInfo(
                sessions: sessions,
                slotStart: slotStart,
                slotEnd: slotEnd,
                capMinutes: HeatmapSlot.minutesPerSlot,
                now: now
            ) {
                newSlots[slot.index] = info
            }
        }

        slots = newSlots
        lastLiveSlotIndex = currentSlot(now: now, calendar: calendar).index
        lastLiveDayStart = calendar.startOfDay(for: now)
    }

    func refreshCurrentSlot(now: Date = Date(), calendar: Calendar = .current) {
        let dayStart = calendar.startOfDay(for: now)
        guard lastLiveDayStart == dayStart else {
            reload(now: now, calendar: calendar)
            return
        }

        let currentSlot = currentSlot(now: now, calendar: calendar)
        var indexesToRefresh = Set([currentSlot.index])
        if let lastLiveSlotIndex {
            indexesToRefresh.insert(lastLiveSlotIndex)
        }

        var newSlots = slots
        for index in indexesToRefresh {
            let slot = HeatmapSlot(hour: index / HeatmapSlot.rowsPerHour, row: index % HeatmapSlot.rowsPerHour)
            let (slotStart, slotEnd) = slot.dateRange(on: now, calendar: calendar)
            let sessions = sessionFetcher(slotStart, slotEnd)
            newSlots[index] = makeSlotInfo(
                sessions: sessions,
                slotStart: slotStart,
                slotEnd: slotEnd,
                capMinutes: HeatmapSlot.minutesPerSlot,
                now: now
            )
        }

        slots = newSlots
        lastLiveSlotIndex = currentSlot.index
    }

    func slotInfo(hour: Int, row: Int, minutesPerSlot: Int) -> SlotInfo? {
        if minutesPerSlot == HeatmapSlot.minutesPerSlot {
            return slots[hour * HeatmapSlot.rowsPerHour + row]
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let startMinutes = hour * 60 + row * minutesPerSlot
        guard
            let slotStart = calendar.date(byAdding: .minute, value: startMinutes, to: startOfDay),
            let slotEnd = calendar.date(byAdding: .minute, value: minutesPerSlot, to: slotStart)
        else {
            return nil
        }

        let request = NSFetchRequest<SessionEntity>(entityName: "SessionEntity")
        request.predicate = NSPredicate(
            format: "startTime < %@ AND (endTime == nil OR endTime > %@)",
            slotEnd as NSDate,
            slotStart as NSDate
        )
        let sessions = (try? stack.viewContext.fetch(request)) ?? []
        return makeSlotInfo(sessions: sessions, slotStart: slotStart, slotEnd: slotEnd, capMinutes: minutesPerSlot, now: Date())
    }

    private func makeSlotInfo(
        sessions: [SessionEntity],
        slotStart: Date,
        slotEnd: Date,
        capMinutes: Int,
        now: Date
    ) -> SlotInfo? {
        guard !sessions.isEmpty else { return nil }

        var tally: [(CategoryEntity?, Double)] = []

        for session in sessions {
            let start = max(session.startTime, slotStart)
            let end = min(session.endTime ?? session.startTime, slotEnd, now)
            let mins = end.timeIntervalSince(start) / 60
            if mins > 0 {
                tally.append((session.category, mins))
            }
        }

        let grouped = Dictionary(grouping: tally, by: { $0.0?.objectID })
        guard let dominant = grouped.max(by: { a, b in
            let aMin = a.value.reduce(0) { $0 + $1.1 }
            let bMin = b.value.reduce(0) { $0 + $1.1 }
            if aMin != bMin { return aMin < bMin }
            let aStart = sessions.first { $0.category?.objectID == a.key }?.startTime ?? Date.distantFuture
            let bStart = sessions.first { $0.category?.objectID == b.key }?.startTime ?? Date.distantFuture
            return aStart > bStart
        }) else {
            return nil
        }

        let totalMins = dominant.value.reduce(0) { $0 + Int($1.1) }
        let category = dominant.value.first?.0
        return SlotInfo(
            color: Color(hex: Color.resolvedCategoryHex(category?.colorHex)),
            categoryName: category?.name ?? "Default",
            dominantMinutes: min(totalMins, capMinutes)
        )
    }

    private func currentSlot(now: Date, calendar: Calendar) -> HeatmapSlot {
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let row = min(HeatmapSlot.rowsPerHour - 1, minute / HeatmapSlot.minutesPerSlot)
        return HeatmapSlot(hour: hour, row: row)
    }

    // MARK: - CoreData change observation

    private func observeChanges() {
        observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The observer is already delivered on .main (queue: .main above), so
            // MainActor.assumeIsolated is safe here. It satisfies the Swift concurrency
            // isolation checker without spinning up a new Task.
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    deinit {
        if let obs = observer { NotificationCenter.default.removeObserver(obs) }
    }
}

struct DayActivityRecord: Equatable, Sendable {
    let sessionID: UUID
    let start: Date
    let end: Date?
    let categoryID: UUID?
    let categoryName: String
    let categoryHex: String
    let isRunning: Bool

    init(
        sessionID: UUID,
        start: Date,
        end: Date?,
        categoryID: UUID?,
        categoryName: String,
        categoryHex: String,
        isRunning: Bool
    ) {
        self.sessionID = sessionID
        self.start = start
        self.end = end
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.categoryHex = categoryHex
        self.isRunning = isRunning
    }

    init(session: SessionEntity) {
        let category = session.category
        self.init(
            sessionID: session.id,
            start: session.startTime,
            end: session.endTime,
            categoryID: category?.id,
            categoryName: category?.name ?? "Default",
            categoryHex: Color.resolvedCategoryHex(category?.colorHex),
            isRunning: session.isRunning
        )
    }
}

struct DayActivitySegmentID: Hashable, Sendable {
    let sessionID: UUID
    let winningPieceStart: Date
    let dayStart: Date

    init(sessionID: UUID, winningPieceStart: Date, dayStart: Date? = nil) {
        self.sessionID = sessionID
        self.winningPieceStart = winningPieceStart
        self.dayStart = dayStart ?? Calendar.current.startOfDay(for: winningPieceStart)
    }
}

struct DayActivitySegment: Identifiable, Equatable, Sendable {
    let id: DayActivitySegmentID
    let categoryID: UUID?
    let categoryName: String
    let categoryHex: String
    let start: Date
    let end: Date
    let isActive: Bool

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct DayActivityCategoryTotal: Identifiable, Equatable, Sendable {
    let categoryID: UUID?
    let categoryName: String
    let categoryHex: String
    let seconds: TimeInterval

    var id: String { categoryID?.uuidString.lowercased() ?? "default" }
}

struct DayActivitySnapshot: Equatable, Sendable {
    let segments: [DayActivitySegment]
    let categoryTotals: [DayActivityCategoryTotal]
    let totalTrackedSeconds: TimeInterval
    let activeOrMostRecentID: DayActivitySegmentID?
    let asOf: Date
    let dayStart: Date
    let nextDayStart: Date
    let calendarIdentifier: String
    let localeIdentifier: String
    let timeZoneIdentifier: String

    static func empty(asOf: Date, calendar: Calendar, locale: Locale) -> DayActivitySnapshot {
        let dayStart = calendar.startOfDay(for: asOf)
        return empty(dayStart: dayStart, asOf: asOf, calendar: calendar, locale: locale)
    }

    static func empty(dayStart: Date, asOf: Date, calendar: Calendar, locale: Locale) -> DayActivitySnapshot {
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        return DayActivitySnapshot(
            segments: [],
            categoryTotals: [],
            totalTrackedSeconds: 0,
            activeOrMostRecentID: nil,
            asOf: asOf,
            dayStart: dayStart,
            nextDayStart: nextDayStart,
            calendarIdentifier: String(describing: calendar.identifier),
            localeIdentifier: locale.identifier,
            timeZoneIdentifier: calendar.timeZone.identifier
        )
    }
}

struct DayActivityWindowSnapshot: Equatable, Sendable {
    let days: [DayActivitySnapshot]
    let hasFetchError: Bool
    let recoveryWarningCount: Int
}

private final class DayActivityTickSubscription: @unchecked Sendable {
    private let cancellable: AnyCancellable

    init(_ cancellable: AnyCancellable) {
        self.cancellable = cancellable
    }

    func cancel() {
        cancellable.cancel()
    }
}

@MainActor
final class DayActivityStore: ObservableObject {
    @Published private(set) var snapshot: DayActivitySnapshot
    @Published private(set) var windowSnapshot: DayActivityWindowSnapshot?
    @Published private(set) var hasFetchError = false
    @Published private(set) var recoveryWarningCount = 0

    private let calendar: Calendar
    private let locale: Locale
    private let now: () -> Date
    private let recordsFetcher: (Date, Date, UUID?) throws -> [DayActivityRecord]
    private var records: [DayActivityRecord] = []
    private(set) var activeSessionID: UUID?
    private var isExpanded = false
    private var observer: NSObjectProtocol?
    private var tickSubscription: DayActivityTickSubscription?

    init(
        context: NSManagedObjectContext? = nil,
        calendar: Calendar = .current,
        locale: Locale = .current,
        now: @escaping () -> Date = Date.init,
        observesChanges: Bool = true,
        activeSessionID: UUID? = nil,
        recordsFetcher: ((Date, Date, UUID?) throws -> [DayActivityRecord])? = nil,
        tickPublisher: AnyPublisher<Date, Never>? = nil
    ) {
        let context = context ?? CoreDataStack.shared.viewContext
        self.calendar = calendar
        self.locale = locale
        self.now = now
        self.activeSessionID = activeSessionID
        self.recordsFetcher = recordsFetcher ?? { [context] dayStart, nextDayStart, activeSessionID in
            let request = NSFetchRequest<SessionEntity>(entityName: "SessionEntity")
            let overlap = NSPredicate(
                format: "startTime < %@ AND (endTime == nil OR endTime > %@)",
                nextDayStart as NSDate,
                dayStart as NSDate
            )
            request.predicate = activeSessionID.map {
                NSCompoundPredicate(orPredicateWithSubpredicates: [
                    overlap,
                    NSPredicate(format: "id == %@", $0 as NSUUID)
                ])
            } ?? overlap
            return try context.fetch(request).map(DayActivityRecord.init(session:))
        }
        snapshot = DayActivitySnapshot.empty(asOf: now(), calendar: calendar, locale: locale)
        windowSnapshot = nil
        reload()
        if observesChanges {
            observeSaves(in: context)
        }
        if observesChanges || tickPublisher != nil {
            let publisher = tickPublisher ?? Timer.publish(every: 1, on: .main, in: .common).autoconnect().eraseToAnyPublisher()
            tickSubscription = DayActivityTickSubscription(publisher.sink { [weak self] now in
                MainActor.assumeIsolated { self?.tick(now: now) }
            })
        }
    }

    func reload(now: Date? = nil) {
        let asOf = now ?? self.now()
        let todayStart = calendar.startOfDay(for: asOf)
        let fetchStart = isExpanded ? calendar.date(byAdding: .day, value: -4, to: todayStart)! : todayStart
        let fetchEnd = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        do {
            records = try recordsFetcher(fetchStart, fetchEnd, activeSessionID)
            recoveryWarningCount = records.filter { $0.end == nil && $0.sessionID != activeSessionID }.count
            let days = projectedDays(asOf: asOf)
            snapshot = days[0]
            hasFetchError = false
            windowSnapshot = isExpanded ? DayActivityWindowSnapshot(
                days: days,
                hasFetchError: false,
                recoveryWarningCount: recoveryWarningCount
            ) : nil
        } catch {
            hasFetchError = true
            if snapshot.dayStart != todayStart {
                let days = emptyDays(asOf: asOf)
                snapshot = days[0]
                recoveryWarningCount = 0
                windowSnapshot = isExpanded ? DayActivityWindowSnapshot(
                    days: days,
                    hasFetchError: true,
                    recoveryWarningCount: 0
                ) : nil
            } else if let windowSnapshot {
                self.windowSnapshot = DayActivityWindowSnapshot(
                    days: windowSnapshot.days,
                    hasFetchError: true,
                    recoveryWarningCount: windowSnapshot.recoveryWarningCount
                )
            } else if isExpanded {
                var days = emptyDays(asOf: asOf)
                days[0] = snapshot
                windowSnapshot = DayActivityWindowSnapshot(
                    days: days,
                    hasFetchError: true,
                    recoveryWarningCount: recoveryWarningCount
                )
            }
        }
    }

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        if expanded {
            reload()
        } else {
            let todayStart = snapshot.dayStart
            let nextDayStart = snapshot.nextDayStart
            records = records.filter {
                $0.sessionID == activeSessionID || ($0.start < nextDayStart && ($0.end == nil || $0.end! > todayStart))
            }
            recoveryWarningCount = records.filter { $0.end == nil && $0.sessionID != activeSessionID }.count
            windowSnapshot = nil
        }
    }

    func setActiveSessionID(_ activeSessionID: UUID?) {
        guard self.activeSessionID != activeSessionID else { return }
        self.activeSessionID = activeSessionID
        let asOf = now()
        guard calendar.startOfDay(for: asOf) == snapshot.dayStart,
              activeSessionID == nil || records.contains(where: { $0.sessionID == activeSessionID })
        else {
            reload(now: asOf)
            return
        }
        recoveryWarningCount = records.filter { $0.end == nil && $0.sessionID != activeSessionID }.count
        tick(now: asOf)
    }

    func tick(now: Date? = nil) {
        let asOf = now ?? self.now()
        if calendar.startOfDay(for: asOf) != snapshot.dayStart {
            reload(now: asOf)
            return
        }
        snapshot = Self.project(
            records,
            dayStart: snapshot.dayStart,
            asOf: asOf,
            activeSessionID: activeSessionID,
            isToday: true,
            calendar: calendar,
            locale: locale
        )
        if let windowSnapshot {
            self.windowSnapshot = DayActivityWindowSnapshot(
                days: [snapshot] + windowSnapshot.days.dropFirst(),
                hasFetchError: hasFetchError,
                recoveryWarningCount: recoveryWarningCount
            )
        }
    }

    private func projectedDays(asOf: Date) -> [DayActivitySnapshot] {
        let todayStart = calendar.startOfDay(for: asOf)
        let count = isExpanded ? 5 : 1
        return (0..<count).map { offset in
            let dayStart = calendar.date(byAdding: .day, value: -offset, to: todayStart)!
            return Self.project(
                records,
                dayStart: dayStart,
                asOf: offset == 0 ? asOf : calendar.date(byAdding: .day, value: 1, to: dayStart)!,
                activeSessionID: activeSessionID,
                isToday: offset == 0,
                calendar: calendar,
                locale: locale
            )
        }
    }

    private func emptyDays(asOf: Date) -> [DayActivitySnapshot] {
        let todayStart = calendar.startOfDay(for: asOf)
        return (0..<(isExpanded ? 5 : 1)).map { offset in
            let dayStart = calendar.date(byAdding: .day, value: -offset, to: todayStart)!
            let snapshotAsOf = offset == 0 ? asOf : calendar.date(byAdding: .day, value: 1, to: dayStart)!
            return DayActivitySnapshot.empty(dayStart: dayStart, asOf: snapshotAsOf, calendar: calendar, locale: locale)
        }
    }

    private func observeSaves(in context: NSManagedObjectContext) {
        let observedContextID = ObjectIdentifier(context)
        observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let savingContext = notification.object as? NSManagedObjectContext,
                  (ObjectIdentifier(savingContext) == observedContextID || Self.containsCategoryChanges(notification))
            else { return }
            let hasRelevantChanges = Self.isRelevantSave(notification)
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    guard hasRelevantChanges else { return }
                    self?.reload()
                }
            } else {
                Task { @MainActor [weak self, hasRelevantChanges] in
                    guard hasRelevantChanges else { return }
                    self?.reload()
                }
            }
        }
    }

    nonisolated private static func isRelevantSave(_ notification: Notification) -> Bool {
        [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey].contains { key in
            guard let objects = notification.userInfo?[key] as? Set<NSManagedObject> else { return false }
            return objects.contains { $0 is SessionEntity || $0 is CategoryEntity }
        }
    }

    nonisolated private static func containsCategoryChanges(_ notification: Notification) -> Bool {
        [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey].contains { key in
            (notification.userInfo?[key] as? Set<NSManagedObject>)?.contains { $0 is CategoryEntity } == true
        }
    }

    private struct Candidate {
        let record: DayActivityRecord
        let start: Date
        let end: Date
    }

    private struct Piece {
        let record: DayActivityRecord
        var start: Date
        var end: Date
    }

    private static func project(
        _ records: [DayActivityRecord],
        dayStart: Date,
        asOf: Date,
        activeSessionID: UUID?,
        isToday: Bool,
        calendar: Calendar,
        locale: Locale
    ) -> DayActivitySnapshot {
        let empty = DayActivitySnapshot.empty(dayStart: dayStart, asOf: asOf, calendar: calendar, locale: locale)
        let candidates = records.compactMap { record -> Candidate? in
            guard record.start < asOf else { return nil }
            if let end = record.end, end < record.start { return nil }
            let start = max(record.start, empty.dayStart)
            let authoritativeEnd = record.sessionID == activeSessionID ? asOf : (record.end ?? record.start)
            let end = min(authoritativeEnd, asOf, empty.nextDayStart)
            guard end > start else { return nil }
            return Candidate(record: record, start: start, end: end)
        }
        let boundaries = Array(Set(candidates.flatMap { [$0.start, $0.end] })).sorted()
        var pieces: [Piece] = []

        for (start, end) in zip(boundaries, boundaries.dropFirst()) where end > start {
            guard let winner = candidates.filter({ $0.start <= start && $0.end >= end }).max(by: winsBefore) else {
                continue
            }
            if var previous = pieces.last,
               previous.record.sessionID == winner.record.sessionID,
               previous.record.categoryID == winner.record.categoryID,
               previous.end == start {
                previous.end = end
                pieces[pieces.count - 1] = previous
            } else {
                pieces.append(Piece(record: winner.record, start: start, end: end))
            }
        }

        let activePiece = pieces.filter { isToday && $0.record.sessionID == activeSessionID && $0.end == asOf }.max(by: pieceBefore)
        let recentPiece = pieces.filter { $0.end <= asOf }.max(by: pieceBefore)
        let selectedID = (activePiece ?? recentPiece).map {
            DayActivitySegmentID(sessionID: $0.record.sessionID, winningPieceStart: $0.start, dayStart: dayStart)
        }
        let segments = pieces.map { piece in
            DayActivitySegment(
                id: DayActivitySegmentID(sessionID: piece.record.sessionID, winningPieceStart: piece.start, dayStart: dayStart),
                categoryID: piece.record.categoryID,
                categoryName: piece.record.categoryName,
                categoryHex: piece.record.categoryHex,
                start: piece.start,
                end: piece.end,
                isActive: isToday && piece.record.sessionID == activeSessionID && piece.end == asOf
            )
        }
        let totals = Dictionary(grouping: segments) { $0.categoryID?.uuidString.lowercased() ?? "default" }
            .values
            .map { group in
                let first = group[0]
                return DayActivityCategoryTotal(
                    categoryID: first.categoryID,
                    categoryName: first.categoryName,
                    categoryHex: first.categoryHex,
                    seconds: group.reduce(0) { $0 + $1.duration }
                )
            }
            .sorted { $0.id < $1.id }

        return DayActivitySnapshot(
            segments: segments,
            categoryTotals: totals,
            totalTrackedSeconds: segments.reduce(0) { $0 + $1.duration },
            activeOrMostRecentID: selectedID,
            asOf: asOf,
            dayStart: empty.dayStart,
            nextDayStart: empty.nextDayStart,
            calendarIdentifier: empty.calendarIdentifier,
            localeIdentifier: empty.localeIdentifier,
            timeZoneIdentifier: empty.timeZoneIdentifier
        )
    }

    private static func winsBefore(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.record.start != rhs.record.start { return lhs.record.start < rhs.record.start }
        return lhs.record.sessionID.uuidString.lowercased() < rhs.record.sessionID.uuidString.lowercased()
    }

    private static func pieceBefore(_ lhs: Piece, _ rhs: Piece) -> Bool {
        if lhs.end != rhs.end { return lhs.end < rhs.end }
        return lhs.record.sessionID.uuidString.lowercased() < rhs.record.sessionID.uuidString.lowercased()
    }

    deinit {
        tickSubscription?.cancel()
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
