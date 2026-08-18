import AppKit
import CoreData
import Combine
import SwiftUI
import XCTest
@testable import NativeScheduler

@MainActor
final class HeatmapLiveTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        try super.setUpWithError()

        container = NSPersistentContainer(name: "NativeScheduler", managedObjectModel: CoreDataStack.model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        context = container.viewContext
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    func testNilEndSessionDoesNotGrowOnLiveRefresh() throws {
        let calendar = Self.calendar
        let slotStart = try Self.date(hour: 14, minute: 0, calendar: calendar)
        let initialNow = try Self.date(hour: 14, minute: 7, calendar: calendar)
        let laterNow = try Self.date(hour: 14, minute: 12, calendar: calendar)
        let category = CategoryEntity.create(name: "Study", colorHex: "#FFA94D", sortOrder: 0, in: context)
        _ = SessionEntity.create(startTime: slotStart, mode: .duration, category: category, in: context)

        let vm = HeatmapViewModel(sessionFetcher: sessionFetcher, observesChanges: false)

        vm.reload(now: initialNow, calendar: calendar)

        let currentIndex = HeatmapSlot(hour: 14, row: 0).index
        let futureIndex = HeatmapSlot(hour: 14, row: 1).index
        XCTAssertNil(vm.slots[currentIndex])
        XCTAssertNil(vm.slots[futureIndex])

        vm.refreshCurrentSlot(now: laterNow, calendar: calendar)

        XCTAssertNil(vm.slots[currentIndex])
        XCTAssertNil(vm.slots[futureIndex])
    }

    func testClosedSessionDurationDoesNotGrowOnLiveRefresh() throws {
        let calendar = Self.calendar
        let slotStart = try Self.date(hour: 14, minute: 0, calendar: calendar)
        let closedAt = try Self.date(hour: 14, minute: 5, calendar: calendar)
        let initialNow = try Self.date(hour: 14, minute: 7, calendar: calendar)
        let laterNow = try Self.date(hour: 14, minute: 12, calendar: calendar)
        let category = CategoryEntity.create(name: "Study", colorHex: "#FFA94D", sortOrder: 0, in: context)
        let session = SessionEntity.create(startTime: slotStart, mode: .duration, category: category, in: context)
        session.endTime = closedAt

        let vm = HeatmapViewModel(sessionFetcher: sessionFetcher, observesChanges: false)

        vm.reload(now: initialNow, calendar: calendar)
        let currentIndex = HeatmapSlot(hour: 14, row: 0).index
        XCTAssertEqual(try XCTUnwrap(vm.slots[currentIndex]).dominantMinutes, 5)

        vm.refreshCurrentSlot(now: laterNow, calendar: calendar)

        let refreshedInfo = try XCTUnwrap(vm.slots[currentIndex])
        XCTAssertEqual(refreshedInfo.categoryName, "Study")
        XCTAssertEqual(refreshedInfo.color.hexString, "#FFA94D")
        XCTAssertEqual(refreshedInfo.dominantMinutes, 5)
        XCTAssertNil(vm.slots[HeatmapSlot(hour: 14, row: 1).index])
    }

    func testCrossingMidnightClearsPreviousDaySlots() throws {
        let calendar = Self.calendar
        let sessionStart = try Self.date(day: 12, hour: 10, minute: 0, calendar: calendar)
        let sessionEnd = try Self.date(day: 12, hour: 10, minute: 10, calendar: calendar)
        let beforeMidnight = try Self.date(day: 12, hour: 23, minute: 59, calendar: calendar)
        let afterMidnight = try Self.date(day: 13, hour: 0, minute: 1, calendar: calendar)
        let category = CategoryEntity.create(name: "Study", colorHex: "#FFA94D", sortOrder: 0, in: context)
        let session = SessionEntity.create(startTime: sessionStart, mode: .duration, category: category, in: context)
        session.endTime = sessionEnd

        let vm = HeatmapViewModel(sessionFetcher: sessionFetcher, observesChanges: false)

        vm.reload(now: beforeMidnight, calendar: calendar)
        XCTAssertNotNil(vm.slots[HeatmapSlot(hour: 10, row: 0).index])

        vm.refreshCurrentSlot(now: afterMidnight, calendar: calendar)

        XCTAssertTrue(vm.slots.isEmpty)
    }

    func testDayActivityStoreFetchesOnceAndTicksWithoutRefetching() throws {
        let calendar = Self.calendar
        let clock = TestClock(try Self.date(hour: 10, minute: 10, calendar: calendar))
        let record = makeRecord(
            start: try Self.date(hour: 10, minute: 0, calendar: calendar),
            end: nil
        )
        let probe = ActivityFetchProbe(records: [record])
        let store = makeStore(calendar: calendar, clock: clock, probe: probe, activeSessionID: record.sessionID)

        let firstID = try XCTUnwrap(store.snapshot.segments.first?.id)
        XCTAssertEqual(probe.calls, 1)
        XCTAssertEqual(store.snapshot.totalTrackedSeconds, 10 * 60, accuracy: 0.001)

        clock.now = try Self.date(hour: 10, minute: 15, calendar: calendar)
        store.tick()

        XCTAssertEqual(probe.calls, 1)
        XCTAssertEqual(store.snapshot.segments.first?.id, firstID)
        XCTAssertEqual(store.snapshot.totalTrackedSeconds, 15 * 60, accuracy: 0.001)

        clock.now = try Self.date(day: 13, hour: 0, minute: 1, calendar: calendar)
        store.tick()
        XCTAssertEqual(probe.calls, 2)
        XCTAssertEqual(store.snapshot.segments.first?.start, calendar.startOfDay(for: clock.now))
        XCTAssertEqual(store.snapshot.totalTrackedSeconds, 60, accuracy: 0.001)
    }

    func testDayActivityStoreOwnsInjectedTickLifecycle() throws {
        let calendar = Self.calendar
        let initialNow = try Self.date(hour: 10, minute: 10, calendar: calendar)
        let laterNow = try Self.date(hour: 10, minute: 15, calendar: calendar)
        let subject = PassthroughSubject<Date, Never>()
        var subscriptions = 0
        var cancellations = 0
        let publisher = subject
            .handleEvents(
                receiveSubscription: { _ in subscriptions += 1 },
                receiveCancel: { cancellations += 1 }
            )
            .eraseToAnyPublisher()
        let probe = ActivityFetchProbe(records: [makeRecord(
            start: try Self.date(hour: 10, minute: 0, calendar: calendar),
            end: nil
        )])
        var store: DayActivityStore? = DayActivityStore(
            context: context,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            now: { initialNow },
            observesChanges: false,
            activeSessionID: probe.records[0].sessionID,
            recordsFetcher: probe.fetch,
            tickPublisher: publisher
        )

        XCTAssertEqual(subscriptions, 1)
        let firstID = try XCTUnwrap(store?.snapshot.segments.first?.id)
        subject.send(laterNow)

        XCTAssertEqual(probe.calls, 1)
        XCTAssertEqual(store?.snapshot.segments.first?.id, firstID)
        XCTAssertEqual(try XCTUnwrap(store?.snapshot.totalTrackedSeconds), 15 * 60, accuracy: 0.001)

        store = nil
        XCTAssertEqual(cancellations, 1)
    }

    func testDayActivityStoreNormalizesOverlapsAndKeepsSplitSegmentIDsUnique() throws {
        let calendar = Self.calendar
        let clock = TestClock(try Self.date(hour: 12, minute: 0, calendar: calendar))
        let first = makeRecord(
            id: "00000000-0000-0000-0000-000000000001",
            start: try Self.date(hour: 9, minute: 0, calendar: calendar),
            end: try Self.date(hour: 11, minute: 0, calendar: calendar),
            categoryName: "First"
        )
        let later = makeRecord(
            id: "00000000-0000-0000-0000-000000000002",
            start: try Self.date(hour: 9, minute: 30, calendar: calendar),
            end: try Self.date(hour: 10, minute: 0, calendar: calendar),
            categoryName: "Later"
        )
        let equalStartWinner = makeRecord(
            id: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF",
            start: try Self.date(hour: 10, minute: 0, calendar: calendar),
            end: try Self.date(hour: 10, minute: 30, calendar: calendar),
            categoryName: "Winner"
        )
        let store = makeStore(
            calendar: calendar,
            clock: clock,
            probe: ActivityFetchProbe(records: [first, later, equalStartWinner])
        )

        XCTAssertEqual(store.snapshot.segments.map(\.categoryName), ["First", "Later", "Winner", "First"])
        let durations: [TimeInterval] = store.snapshot.segments.map(\.duration)
        XCTAssertEqual(durations, [1_800, 1_800, 1_800, 1_800])
        XCTAssertEqual(Set(store.snapshot.segments.map(\.id)).count, 4)
        XCTAssertEqual(store.snapshot.totalTrackedSeconds, 2 * 60 * 60, accuracy: 0.001)
        XCTAssertEqual(store.snapshot.categoryTotals.reduce(0) { $0 + $1.seconds }, store.snapshot.totalTrackedSeconds, accuracy: 0.001)
    }

    func testDayActivityStoreFiltersInvalidFutureAndClipsAcrossMidnight() throws {
        let calendar = Self.calendar
        let clock = TestClock(try Self.date(day: 12, hour: 1, minute: 0, calendar: calendar))
        let crossMidnight = makeRecord(
            start: try Self.date(day: 11, hour: 23, minute: 30, calendar: calendar),
            end: try Self.date(day: 12, hour: 0, minute: 30, calendar: calendar)
        )
        let invalid = makeRecord(
            start: try Self.date(hour: 0, minute: 45, calendar: calendar),
            end: try Self.date(hour: 0, minute: 40, calendar: calendar)
        )
        let future = makeRecord(
            start: try Self.date(hour: 2, minute: 0, calendar: calendar),
            end: try Self.date(hour: 3, minute: 0, calendar: calendar)
        )
        let store = makeStore(
            calendar: calendar,
            clock: clock,
            probe: ActivityFetchProbe(records: [crossMidnight, invalid, future])
        )

        XCTAssertEqual(store.snapshot.segments.count, 1)
        XCTAssertEqual(store.snapshot.segments[0].duration, 30 * 60, accuracy: 0.001)
        XCTAssertEqual(store.snapshot.activeOrMostRecentID, store.snapshot.segments[0].id)
    }

    func testDayActivityStorePreservesSameDaySnapshotOnFailureButClearsAtRollover() throws {
        let calendar = Self.calendar
        let clock = TestClock(try Self.date(hour: 10, minute: 0, calendar: calendar))
        let probe = ActivityFetchProbe(records: [makeRecord(
            start: try Self.date(hour: 9, minute: 0, calendar: calendar),
            end: try Self.date(hour: 9, minute: 30, calendar: calendar)
        )])
        let store = makeStore(calendar: calendar, clock: clock, probe: probe)
        let lastGood = store.snapshot

        probe.error = ActivityFetchProbe.Error.failed
        store.reload()
        XCTAssertTrue(store.hasFetchError)
        XCTAssertEqual(store.snapshot, lastGood)

        clock.now = try Self.date(day: 13, hour: 0, minute: 1, calendar: calendar)
        store.tick()
        XCTAssertTrue(store.hasFetchError)
        XCTAssertTrue(store.snapshot.segments.isEmpty)
        XCTAssertEqual(store.snapshot.dayStart, calendar.startOfDay(for: clock.now))

        probe.error = nil
        probe.records = []
        store.reload()
        XCTAssertFalse(store.hasFetchError)
    }

    func testDayActivityStoreReloadsOnceForRelevantSaveAndNotForTodoSave() throws {
        let calendar = Self.calendar
        let clock = TestClock(try Self.date(hour: 10, minute: 0, calendar: calendar))
        let probe = ActivityFetchProbe(records: [])
        let store = DayActivityStore(
            context: context,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            now: { clock.now },
            observesChanges: true,
            recordsFetcher: probe.fetch
        )
        XCTAssertEqual(probe.calls, 1)
        store.setExpanded(true)
        XCTAssertEqual(probe.calls, 2)

        _ = TodoEntity.create(title: "Ignore", priority: 0, in: context)
        try context.save()
        XCTAssertEqual(probe.calls, 2)

        _ = CategoryEntity.create(name: "Study", colorHex: "#FFA94D", sortOrder: 0, in: context)
        try context.save()
        XCTAssertEqual(probe.calls, 3)

        let category = try XCTUnwrap(CategoryEntity.fetchAll(in: context).first)
        _ = SessionEntity.create(
            startTime: try Self.date(hour: 9, minute: 0, calendar: calendar),
            mode: .duration,
            category: category,
            in: context
        )
        try context.save()
        XCTAssertEqual(probe.calls, 4)
        _ = store
    }

    func testSettingsContextCategorySavePublishesOneDaylineReloadAndTodoSavePublishesNone() async throws {
        let settingsContext = CoreDataStack.makeIsolatedMainContext(
            persistentStoreCoordinator: container.persistentStoreCoordinator,
            name: "NativeScheduler.settings.test"
        )
        _ = CategoryEntity.create(name: "Study", colorHex: "#FFA94D", sortOrder: 0, in: context)
        try context.save()
        let probe = ActivityFetchProbe(records: [])
        let store = DayActivityStore(context: context, observesChanges: true, recordsFetcher: probe.fetch)
        let publication = expectation(description: "Dayline reload after settings category save")
        var publications = 0
        let cancellable = store.$snapshot.sink { _ in
            publications += 1
            if publications == 2 { publication.fulfill() }
        }

        let settingsCategory = try XCTUnwrap(CategoryEntity.fetchAll(in: settingsContext).first)
        settingsCategory.name = "Renamed"
        try settingsContext.save()
        await fulfillment(of: [publication], timeout: 1)
        XCTAssertEqual(probe.calls, 2)

        _ = TodoEntity.create(title: "Unrelated", priority: 0, in: settingsContext)
        try settingsContext.save()
        XCTAssertEqual(publications, 2)
        withExtendedLifetime(cancellable) {}
    }

    func testDayActivityStoreCapturesCalendarLocaleAndDSTDayLength() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let spring = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))
        let fall = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)))
        let probe = ActivityFetchProbe(records: [])
        let clock = TestClock(spring)
        let store = makeStore(calendar: calendar, clock: clock, probe: probe, locale: Locale(identifier: "ko_KR"))

        XCTAssertEqual(store.snapshot.nextDayStart.timeIntervalSince(store.snapshot.dayStart), 23 * 60 * 60, accuracy: 0.001)
        XCTAssertEqual(store.snapshot.localeIdentifier, "ko_KR")
        XCTAssertEqual(store.snapshot.timeZoneIdentifier, "America/Los_Angeles")

        clock.now = fall
        store.tick()
        XCTAssertEqual(store.snapshot.nextDayStart.timeIntervalSince(store.snapshot.dayStart), 25 * 60 * 60, accuracy: 0.001)
    }

    func testDayActivityStoreExpandsOnceIntoFiveNewestFirstLocalDaysAndCollapsesWithoutFetching() throws {
        let calendar = Self.calendar
        let clock = TestClock(try Self.date(hour: 12, minute: 0, calendar: calendar))
        let probe = ActivityFetchProbe(records: [
            makeRecord(start: try Self.date(day: 8, hour: 9, minute: 0, calendar: calendar), end: try Self.date(day: 8, hour: 10, minute: 0, calendar: calendar)),
            makeRecord(id: "00000000-0000-0000-0000-000000000002", start: try Self.date(day: 10, hour: 9, minute: 0, calendar: calendar), end: try Self.date(day: 10, hour: 10, minute: 0, calendar: calendar)),
            makeRecord(id: "00000000-0000-0000-0000-000000000003", start: try Self.date(day: 12, hour: 9, minute: 0, calendar: calendar), end: try Self.date(day: 12, hour: 10, minute: 0, calendar: calendar))
        ])
        let store = makeStore(calendar: calendar, clock: clock, probe: probe)

        XCTAssertNil(store.windowSnapshot)
        XCTAssertEqual(probe.calls, 1)
        XCTAssertEqual(probe.requests[0].start, calendar.startOfDay(for: clock.now))

        store.setExpanded(true)

        let window = try XCTUnwrap(store.windowSnapshot)
        XCTAssertEqual(probe.calls, 2)
        XCTAssertEqual(window.days.count, 5)
        XCTAssertEqual(window.days.map(\.dayStart), (0..<5).map { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: clock.now))! })
        XCTAssertEqual(window.days.map(\.totalTrackedSeconds), [3_600, 0, 3_600, 0, 3_600])
        XCTAssertEqual(probe.requests[1].start, calendar.date(byAdding: .day, value: -4, to: calendar.startOfDay(for: clock.now)))
        XCTAssertEqual(probe.requests[1].end, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: clock.now)))

        store.setExpanded(false)
        XCTAssertNil(store.windowSnapshot)
        XCTAssertEqual(probe.calls, 2)
        XCTAssertEqual(store.snapshot.dayStart, calendar.startOfDay(for: clock.now))
    }

    func testExpandedTickChangesOnlyTodayAndRolloverFetchesOnce() throws {
        let calendar = Self.calendar
        let activeID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let clock = TestClock(try Self.date(hour: 23, minute: 58, calendar: calendar))
        let probe = ActivityFetchProbe(records: [makeRecord(
            id: activeID.uuidString,
            start: try Self.date(day: 11, hour: 23, minute: 30, calendar: calendar),
            end: try Self.date(day: 11, hour: 23, minute: 30, calendar: calendar)
        )])
        let store = makeStore(calendar: calendar, clock: clock, probe: probe, activeSessionID: activeID)
        store.setExpanded(true)
        let before = try XCTUnwrap(store.windowSnapshot)
        let historical = Array(before.days.dropFirst())
        let historicalIDs = historical.flatMap { $0.segments.map(\.id) }

        clock.now = try Self.date(hour: 23, minute: 59, calendar: calendar)
        store.tick()
        let ticked = try XCTUnwrap(store.windowSnapshot)
        XCTAssertEqual(probe.calls, 2)
        XCTAssertEqual(Array(ticked.days.dropFirst()), historical)
        XCTAssertEqual(ticked.days.dropFirst().flatMap { $0.segments.map(\.id) }, historicalIDs)
        XCTAssertEqual(ticked.days[0].totalTrackedSeconds, before.days[0].totalTrackedSeconds + 60, accuracy: 0.001)

        clock.now = try Self.date(day: 13, hour: 0, minute: 1, calendar: calendar)
        store.tick()
        XCTAssertEqual(probe.calls, 3)
        XCTAssertEqual(store.windowSnapshot?.days.first?.dayStart, calendar.startOfDay(for: clock.now))
    }

    func testActiveAuthorityProjectsCheckpointAcrossMidnightAndNilWithoutAuthorityWarnsWithoutMutation() throws {
        let calendar = Self.calendar
        let activeID = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
        let clock = TestClock(try Self.date(day: 12, hour: 0, minute: 30, calendar: calendar))
        let checkpoint = try Self.date(day: 11, hour: 23, minute: 45, calendar: calendar)
        let legacyStart = try Self.date(day: 12, hour: 0, minute: 10, calendar: calendar)
        let legacy = makeRecord(id: "00000000-0000-0000-0000-000000000006", start: legacyStart, end: nil)
        let probe = ActivityFetchProbe(records: [
            makeRecord(id: activeID.uuidString, start: try Self.date(day: 11, hour: 23, minute: 30, calendar: calendar), end: checkpoint),
            legacy
        ])
        let store = makeStore(calendar: calendar, clock: clock, probe: probe, activeSessionID: activeID)
        store.setExpanded(true)
        let days = try XCTUnwrap(store.windowSnapshot).days

        XCTAssertEqual(days[0].totalTrackedSeconds, 30 * 60, accuracy: 0.001)
        XCTAssertEqual(days[1].totalTrackedSeconds, 30 * 60, accuracy: 0.001)
        XCTAssertEqual(days[0].segments.first?.id.dayStart, days[0].dayStart)
        XCTAssertEqual(days[1].segments.first?.id.dayStart, days[1].dayStart)
        XCTAssertNotEqual(days[0].segments.first?.id, days[1].segments.first?.id)
        XCTAssertEqual(store.recoveryWarningCount, 1)
        XCTAssertEqual(probe.records.last, legacy)
        XCTAssertEqual(probe.requests.last?.activeSessionID, activeID)
    }

    func testDefaultFetchIncludesActiveCheckpointByIDAcrossMidnight() throws {
        let calendar = Self.calendar
        let now = try Self.date(day: 13, hour: 0, minute: 1, calendar: calendar)
        let session = SessionEntity.create(
            startTime: try Self.date(day: 12, hour: 23, minute: 30, calendar: calendar),
            mode: .duration,
            category: nil,
            in: context
        )
        session.endTime = session.startTime
        try context.save()

        let store = DayActivityStore(
            context: context,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            now: { now },
            observesChanges: false,
            activeSessionID: session.id
        )

        XCTAssertEqual(store.snapshot.totalTrackedSeconds, 60, accuracy: 0.001)
        XCTAssertEqual(store.snapshot.segments.first?.id.sessionID, session.id)
        XCTAssertTrue(store.snapshot.segments.first?.isActive == true)
    }

    func testExpandedFailureRetentionExactRolloverFallbackAndRecovery() throws {
        let calendar = Self.calendar
        let clock = TestClock(try Self.date(hour: 12, minute: 0, calendar: calendar))
        let probe = ActivityFetchProbe(records: [makeRecord(start: try Self.date(hour: 9, minute: 0, calendar: calendar), end: try Self.date(hour: 10, minute: 0, calendar: calendar))])
        let store = makeStore(calendar: calendar, clock: clock, probe: probe)
        store.setExpanded(true)
        let lastGood = try XCTUnwrap(store.windowSnapshot)

        probe.error = ActivityFetchProbe.Error.failed
        store.reload()
        XCTAssertEqual(store.windowSnapshot?.days, lastGood.days)
        XCTAssertTrue(store.hasFetchError)

        clock.now = try Self.date(day: 13, hour: 0, minute: 1, calendar: calendar)
        store.tick()
        let fallback = try XCTUnwrap(store.windowSnapshot)
        XCTAssertEqual(fallback.days.count, 5)
        XCTAssertEqual(fallback.days.map(\.dayStart), (0..<5).map { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: clock.now))! })
        XCTAssertTrue(fallback.days.allSatisfy(\.segments.isEmpty))

        probe.error = nil
        probe.records = []
        store.reload()
        XCTAssertFalse(store.hasFetchError)
        XCTAssertEqual(store.recoveryWarningCount, 0)
    }

    func testExpansionFailureRetainsTodayAndStillPublishesFiveExactDates() throws {
        let calendar = Self.calendar
        let clock = TestClock(try Self.date(hour: 12, minute: 0, calendar: calendar))
        let probe = ActivityFetchProbe(records: [makeRecord(
            start: try Self.date(hour: 9, minute: 0, calendar: calendar),
            end: try Self.date(hour: 10, minute: 0, calendar: calendar)
        )])
        let store = makeStore(calendar: calendar, clock: clock, probe: probe)
        let today = store.snapshot

        probe.error = ActivityFetchProbe.Error.failed
        store.setExpanded(true)

        let window = try XCTUnwrap(store.windowSnapshot)
        XCTAssertTrue(window.hasFetchError)
        XCTAssertEqual(window.days.count, 5)
        XCTAssertEqual(window.days[0], today)
        XCTAssertTrue(window.days.dropFirst().allSatisfy(\.segments.isEmpty))
    }

    func testExpandedWindowUsesCalendarArithmeticForSpringAndFallDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        for components in [
            DateComponents(year: 2026, month: 3, day: 10, hour: 12),
            DateComponents(year: 2026, month: 11, day: 3, hour: 12)
        ] {
            let clock = TestClock(try XCTUnwrap(calendar.date(from: components)))
            let store = makeStore(calendar: calendar, clock: clock, probe: ActivityFetchProbe(records: []))
            store.setExpanded(true)
            let lengths = try XCTUnwrap(store.windowSnapshot).days.map { $0.nextDayStart.timeIntervalSince($0.dayStart) / 3_600 }
            XCTAssertTrue(lengths.contains(components.month == 3 ? 23 : 25))
        }
    }

    func testManualFiveDayFixtureEmitsDatesTotalsAndFetchCounts() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 0, minute: 30)))
        let activeID = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!
        let clock = TestClock(now)
        let probe = ActivityFetchProbe(records: [
            makeRecord(
                id: activeID.uuidString,
                start: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 23, minute: 30))),
                end: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 23, minute: 30)))
            ),
            makeRecord(
                id: "00000000-0000-0000-0000-000000000008",
                start: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1, minute: 30))),
                end: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 3, minute: 30)))
            ),
            makeRecord(
                id: "00000000-0000-0000-0000-000000000009",
                start: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 9))),
                end: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 10)))
            )
        ])
        let store = makeStore(calendar: calendar, clock: clock, probe: probe, activeSessionID: activeID)
        store.setExpanded(true)
        let days = try XCTUnwrap(store.windowSnapshot).days
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        let artifact: [String: Any] = [
            "dates": days.map { formatter.string(from: $0.dayStart) },
            "totals": days.map(\.totalTrackedSeconds),
            "dayHours": days.map { $0.nextDayStart.timeIntervalSince($0.dayStart) / 3_600 },
            "segmentCounts": days.map { $0.segments.count },
            "fetchCount": probe.calls,
            "activeIDForwarded": probe.requests.last?.activeSessionID == activeID
        ]
        let data = try JSONSerialization.data(withJSONObject: artifact, options: [.sortedKeys])
        print("TASK6_MANUAL_JSON=" + String(decoding: data, as: UTF8.self))

        XCTAssertEqual(days.count, 5)
        XCTAssertEqual(days.map(\.totalTrackedSeconds), [1_800, 1_800, 3_600, 0, 3_600])
        XCTAssertTrue(days.map { $0.nextDayStart.timeIntervalSince($0.dayStart) / 3_600 }.contains(23))
        XCTAssertEqual(probe.calls, 2)
    }

    func testTimerViewModelAndMainPanelDriveOneDayActivityStoreThroughLivePauseResumeCategoryCrashAndLegacyRows() throws {
        let calendar = Self.calendar
        let start = Date().addingTimeInterval(86_400)
        let clock = TestClock(start)
        let study = CategoryEntity.create(name: "Study", colorHex: "#FFA94D", sortOrder: 0, in: context)
        let breakCategory = CategoryEntity.create(name: "Break", colorHex: "#4DABF7", sortOrder: 1, in: context)
        try context.save()
        let save = SaveSpy()
        let engine = TimerEngine(tickInterval: .seconds(3_600), soundPlayer: {})
        let timerVM = TimerViewModel(
            engine: engine,
            context: context,
            now: { clock.now },
            save: save.save
        )
        timerVM.selectedCategory = study
        let fetch = ContextActivityFetchProbe(context: context)
        let ticks = PassthroughSubject<Date, Never>()
        let store = DayActivityStore(
            context: context,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            now: { clock.now },
            observesChanges: true,
            recordsFetcher: fetch.fetch,
            tickPublisher: ticks.eraseToAnyPublisher()
        )
        let host = NSHostingView(
            rootView: AnyView(MainPanelView(timerVM: timerVM, dayActivityStore: store))
        )
        host.frame = CGRect(x: 0, y: 0, width: 776, height: 321)
        let window = NSWindow(
            contentRect: CGRect(x: -10_000, y: -10_000, width: 776, height: 321),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer {
            timerVM.stop()
            host.rootView = AnyView(EmptyView())
            host.layoutSubtreeIfNeeded()
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        XCTAssertNil(store.windowSnapshot)
        XCTAssertEqual(fetch.calls, 1, "Opening the outer panel must fetch today only")

        timerVM.start()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let firstSessionID = try XCTUnwrap(timerVM.activeSessionID)
        XCTAssertEqual(store.activeSessionID, firstSessionID)

        for second in 1...12 {
            clock.now = start.addingTimeInterval(TimeInterval(second))
            let beforePersistence = fetch.calls
            timerVM.processPersistenceTick()
            XCTAssertEqual(fetch.calls, beforePersistence + (second == 10 ? 1 : 0))
            let beforeTick = fetch.calls
            ticks.send(clock.now)
            XCTAssertEqual(fetch.calls, beforeTick, "Projection ticks must never fetch")
            XCTAssertEqual(store.snapshot.totalTrackedSeconds, TimeInterval(second), accuracy: 0.001)
        }
        XCTAssertEqual(save.saveCount, 2, "Start plus one 10-second checkpoint")

        timerVM.pause()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        XCTAssertNil(store.activeSessionID)
        XCTAssertEqual(store.snapshot.totalTrackedSeconds, 12, accuracy: 0.001)
        let frozenFetches = fetch.calls
        clock.now = start.addingTimeInterval(19)
        ticks.send(clock.now)
        XCTAssertEqual(fetch.calls, frozenFetches)
        XCTAssertEqual(store.snapshot.totalTrackedSeconds, 12, accuracy: 0.001)

        clock.now = start.addingTimeInterval(20)
        timerVM.start()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        for second in 21...22 {
            clock.now = start.addingTimeInterval(TimeInterval(second))
            timerVM.processPersistenceTick()
            ticks.send(clock.now)
        }
        XCTAssertEqual(store.snapshot.totalTrackedSeconds, 14, accuracy: 0.001)

        let savesBeforeCategorySwitch = save.saveCount
        timerVM.changeCategory(to: breakCategory)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let switchedSessions = try fetchSessions().sorted { $0.startTime < $1.startTime }
        XCTAssertEqual(switchedSessions.count, 3)
        XCTAssertEqual(switchedSessions[1].endTime, switchedSessions[2].startTime)
        XCTAssertEqual(switchedSessions[2].startTime, switchedSessions[2].endTime)
        XCTAssertEqual(timerVM.activeSessionID, switchedSessions[2].id)
        XCTAssertEqual(store.activeSessionID, switchedSessions[2].id)
        XCTAssertEqual(save.saveCount, savesBeforeCategorySwitch + 1)

        for second in 23...25 {
            clock.now = start.addingTimeInterval(TimeInterval(second))
            timerVM.processPersistenceTick()
            ticks.send(clock.now)
        }
        XCTAssertEqual(store.snapshot.totalTrackedSeconds, 17, accuracy: 0.001)
        let categoryTotals = Dictionary(uniqueKeysWithValues: store.snapshot.categoryTotals.map { ($0.categoryName, $0.seconds) })
        XCTAssertEqual(categoryTotals["Study"], 14)
        XCTAssertEqual(categoryTotals["Break"], 3)

        let beforeExpansion = fetch.calls
        store.setExpanded(true)
        XCTAssertEqual(fetch.calls, beforeExpansion + 1)
        XCTAssertEqual(store.windowSnapshot?.days.count, 5)
        XCTAssertEqual(store.windowSnapshot?.days.first, store.snapshot)

        store.setExpanded(false)
        XCTAssertNil(store.windowSnapshot)
        XCTAssertEqual(fetch.calls, beforeExpansion + 1, "Collapse must release history without fetching")

        store.setExpanded(true)
        XCTAssertEqual(fetch.calls, beforeExpansion + 2, "Re-expansion performs one range fetch")

        let relaunchFetch = ContextActivityFetchProbe(context: context)
        let relaunchedStore = DayActivityStore(
            context: context,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            now: { clock.now },
            observesChanges: false,
            recordsFetcher: relaunchFetch.fetch
        )
        XCTAssertEqual(relaunchedStore.snapshot.totalTrackedSeconds, 14, accuracy: 0.001)
        XCTAssertEqual(relaunchFetch.calls, 1)

        let legacy = SessionEntity.create(
            startTime: start.addingTimeInterval(24),
            mode: .duration,
            category: breakCategory,
            in: context
        )
        try context.save()
        store.setActiveSessionID(nil)
        let frozenTotal = store.snapshot.totalTrackedSeconds
        clock.now = start.addingTimeInterval(40)
        ticks.send(clock.now)

        XCTAssertNil(legacy.endTime)
        XCTAssertEqual(store.recoveryWarningCount, 1)
        XCTAssertEqual(store.snapshot.totalTrackedSeconds, frozenTotal, accuracy: 0.001)

        let publication: [String: Any] = [
            "liveAt12": 12,
            "pausedAt19": 12,
            "liveAfterCategorySwitch": 17,
            "relaunchDurableTotal": relaunchedStore.snapshot.totalTrackedSeconds,
            "checkpointSaves": 1,
            "historyDays": store.windowSnapshot?.days.count ?? 0,
            "legacyWarningCount": store.recoveryWarningCount,
            "legacyEndRemainsNil": legacy.endTime == nil
        ]
        let data = try JSONSerialization.data(withJSONObject: publication, options: [.sortedKeys])
        print("TASK7_PUBLICATION_JSON=" + String(decoding: data, as: UTF8.self))
    }

    func testSixtyOneSecondTimerLifecycleKeepsRelevantFetchesWithinSaveBound() throws {
        let calendar = Self.calendar
        let start = try Self.date(hour: 9, minute: 0, calendar: calendar)
        let clock = TestClock(start)
        let study = CategoryEntity.create(name: "Study", colorHex: "#FFA94D", sortOrder: 0, in: context)
        let breakCategory = CategoryEntity.create(name: "Break", colorHex: "#4DABF7", sortOrder: 1, in: context)
        try context.save()
        let save = SaveSpy()
        let timerVM = TimerViewModel(
            engine: TimerEngine(tickInterval: .seconds(3_600), soundPlayer: {}),
            context: context,
            now: { clock.now },
            save: save.save
        )
        timerVM.selectedCategory = study
        let fetch = ContextActivityFetchProbe(context: context)
        let store = DayActivityStore(
            context: context,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            now: { clock.now },
            observesChanges: true,
            recordsFetcher: fetch.fetch
        )
        let initialFetches = fetch.calls
        let authority = timerVM.$activeSessionID.sink { store.setActiveSessionID($0) }
        var tickFetches = 0

        timerVM.start()
        for second in 1...61 {
            clock.now = start.addingTimeInterval(TimeInterval(second))
            let beforePersistenceFetches = fetch.calls
            let beforeSaves = save.saveCount
            timerVM.processPersistenceTick()
            XCTAssertEqual(fetch.calls - beforePersistenceFetches, save.saveCount - beforeSaves)
            let beforeTickFetches = fetch.calls
            store.tick()
            tickFetches += fetch.calls - beforeTickFetches
            XCTAssertEqual(fetch.calls, beforeTickFetches, "Projection ticks must not fetch")
            if second == 30 {
                timerVM.changeCategory(to: breakCategory)
            }
        }
        timerVM.stop()

        XCTAssertEqual(save.saveCount, 9)
        XCTAssertLessThanOrEqual(fetch.calls - initialFetches, save.saveCount)
        XCTAssertEqual(store.snapshot.totalTrackedSeconds, 61, accuracy: 0.001)
        XCTAssertNil(store.activeSessionID)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: store.snapshot.categoryTotals.map { ($0.categoryName, $0.seconds) })["Study"], 30)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: store.snapshot.categoryTotals.map { ($0.categoryName, $0.seconds) })["Break"], 31)
        let resource: [String: Any] = [
            "seconds": 61,
            "saveCount": save.saveCount,
            "relevantFetches": fetch.calls - initialFetches,
            "tickFetches": tickFetches,
            "authorityFetchChurn": fetch.calls - initialFetches - save.saveCount,
            "trackedSeconds": store.snapshot.totalTrackedSeconds
        ]
        print("TASK9_RESOURCE_JSON=" + String(decoding: try JSONSerialization.data(withJSONObject: resource, options: [.sortedKeys]), as: UTF8.self))
        withExtendedLifetime(authority) {}
    }

    func testActiveAuthorityReprojectsCachedRecordAndFetchesOnlyWhenMissingAcrossMidnight() throws {
        let calendar = Self.calendar
        let clock = TestClock(try Self.date(hour: 10, minute: 1, calendar: calendar))
        let cached = makeRecord(
            id: "00000000-0000-0000-0000-000000000010",
            start: try Self.date(hour: 10, minute: 0, calendar: calendar),
            end: try Self.date(hour: 10, minute: 0, calendar: calendar)
        )
        let probe = ActivityFetchProbe(records: [cached])
        let store = makeStore(calendar: calendar, clock: clock, probe: probe)

        store.setActiveSessionID(cached.sessionID)
        XCTAssertEqual(probe.calls, 1, "A cached checkpoint must reproject without a duplicate fetch")
        XCTAssertEqual(store.snapshot.totalTrackedSeconds, 60, accuracy: 0.001)

        store.setActiveSessionID(nil)
        XCTAssertEqual(probe.calls, 1)
        XCTAssertEqual(store.snapshot.totalTrackedSeconds, 0, accuracy: 0.001)

        let missingID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        store.setActiveSessionID(missingID)
        XCTAssertEqual(probe.calls, 2, "A missing active row must preserve the active-ID OR fetch")

        let crossMidnight = SessionEntity.create(
            startTime: try Self.date(day: 11, hour: 23, minute: 30, calendar: calendar),
            mode: .duration,
            category: nil,
            in: context
        )
        crossMidnight.endTime = crossMidnight.startTime
        try context.save()
        clock.now = try Self.date(day: 12, hour: 0, minute: 1, calendar: calendar)
        let contextProbe = ContextActivityFetchProbe(context: context)
        let attached = DayActivityStore(
            context: context,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            now: { clock.now },
            observesChanges: false,
            recordsFetcher: contextProbe.fetch
        )
        XCTAssertEqual(contextProbe.calls, 1)
        attached.setActiveSessionID(crossMidnight.id)
        XCTAssertEqual(contextProbe.calls, 2)
        XCTAssertEqual(attached.snapshot.totalTrackedSeconds, 60, accuracy: 0.001)
    }

    func testDayActivityStoreMergesOnlyAdjacentWinningPiecesWithMatchingIdentity() throws {
        let calendar = Self.calendar
        let clock = TestClock(try Self.date(hour: 10, minute: 0, calendar: calendar))
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let first = makeRecord(
            id: sessionID.uuidString,
            start: try Self.date(hour: 9, minute: 0, calendar: calendar),
            end: try Self.date(hour: 9, minute: 30, calendar: calendar)
        )
        let adjacentMatch = makeRecord(
            id: sessionID.uuidString,
            start: try Self.date(hour: 9, minute: 30, calendar: calendar),
            end: try Self.date(hour: 10, minute: 0, calendar: calendar)
        )
        let merged = makeStore(
            calendar: calendar,
            clock: clock,
            probe: ActivityFetchProbe(records: [first, adjacentMatch])
        )
        XCTAssertEqual(merged.snapshot.segments.count, 1)
        XCTAssertEqual(merged.snapshot.segments[0].duration, 60 * 60, accuracy: 0.001)

        let differentSession = makeRecord(
            id: "00000000-0000-0000-0000-000000000002",
            start: try Self.date(hour: 9, minute: 30, calendar: calendar),
            end: try Self.date(hour: 10, minute: 0, calendar: calendar)
        )
        let separate = makeStore(
            calendar: calendar,
            clock: clock,
            probe: ActivityFetchProbe(records: [first, differentSession])
        )
        XCTAssertEqual(separate.snapshot.segments.count, 2)
        XCTAssertEqual(separate.snapshot.segments.map(\.duration), [1_800, 1_800])
    }

    func testDayActivityStorePrefersActiveOpenWinnerThenGreatestUUIDForEqualEndFallback() throws {
        let calendar = Self.calendar
        let clock = TestClock(try Self.date(hour: 10, minute: 0, calendar: calendar))
        let recent = makeRecord(
            id: "00000000-0000-0000-0000-000000000001",
            start: try Self.date(hour: 9, minute: 0, calendar: calendar),
            end: try Self.date(hour: 9, minute: 30, calendar: calendar)
        )
        let active = makeRecord(
            id: "00000000-0000-0000-0000-000000000002",
            start: try Self.date(hour: 9, minute: 45, calendar: calendar),
            end: nil
        )
        let activeStore = makeStore(
            calendar: calendar,
            clock: clock,
            probe: ActivityFetchProbe(records: [recent, active]),
            activeSessionID: active.sessionID
        )
        XCTAssertEqual(activeStore.snapshot.activeOrMostRecentID?.sessionID, active.sessionID)
        XCTAssertTrue(activeStore.snapshot.segments.contains { $0.isActive && $0.id.sessionID == active.sessionID })

        let lowerUUID = makeRecord(
            id: "00000000-0000-0000-0000-000000000001",
            start: try Self.date(hour: 9, minute: 0, calendar: calendar),
            end: try Self.date(hour: 9, minute: 30, calendar: calendar)
        )
        let greaterUUID = makeRecord(
            id: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF",
            start: try Self.date(hour: 9, minute: 0, calendar: calendar),
            end: try Self.date(hour: 9, minute: 30, calendar: calendar)
        )
        let fallbackStore = makeStore(
            calendar: calendar,
            clock: clock,
            probe: ActivityFetchProbe(records: [lowerUUID, greaterUUID])
        )
        XCTAssertEqual(fallbackStore.snapshot.segments.count, 1)
        XCTAssertEqual(fallbackStore.snapshot.activeOrMostRecentID?.sessionID, greaterUUID.sessionID)
    }

    func testTodayUsageSummaryProjectionKeepsExactSnapshotTotalsAndFivePlusEtc() throws {
        let totals = (0..<6).map { index in
            DayActivityCategoryTotal(
                categoryID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                categoryName: "Category \(index + 1)",
                categoryHex: "#123456",
                seconds: TimeInterval((6 - index) * 61)
            )
        }
        let totalSeconds = totals.reduce(0) { $0 + $1.seconds }
        let snapshot = usageSnapshot(totals: totals, totalSeconds: totalSeconds, localeIdentifier: "en_US")

        XCTAssertTrue(TodayUsageSummaryProjection.entries(for: usageSnapshot(totals: [], totalSeconds: 0, localeIdentifier: "en_US")).isEmpty)
        XCTAssertEqual(TodayUsageSummaryProjection.entries(for: snapshot).map(\.name), totals.map(\.categoryName))
        let visible = TodayUsageSummaryProjection.visibleEntries(for: snapshot)
        XCTAssertEqual(visible.count, 6)
        XCTAssertEqual(visible.last?.name, "Etc")
        XCTAssertEqual(
            try! XCTUnwrap(visible.last?.seconds),
            try! XCTUnwrap(totals.last?.seconds),
            accuracy: 0.001
        )
        XCTAssertEqual(visible.reduce(0) { $0 + $1.seconds }, snapshot.totalTrackedSeconds, accuracy: 0.001)
        XCTAssertEqual(TodayUsageSummaryProjection.percentageText(visible[0]), "29%")
    }

    func testTodayUsageSummaryProjectionUsesSnapshotLocaleDefaultAndLiveGrowth() throws {
        let defaultTotal = DayActivityCategoryTotal(
            categoryID: nil,
            categoryName: "",
            categoryHex: Color.nsDefaultSlot.hexString,
            seconds: 59
        )
        let defaultSnapshot = usageSnapshot(totals: [defaultTotal], totalSeconds: 59, localeIdentifier: "en_US")
        let defaultEntry = try XCTUnwrap(TodayUsageSummaryProjection.entries(for: defaultSnapshot).first)
        XCTAssertEqual(defaultEntry.name, "Default")
        XCTAssertEqual(defaultEntry.seconds, 59, accuracy: 0.001)

        let activeID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let first = DayActivityCategoryTotal(categoryID: activeID, categoryName: "Active", categoryHex: "#ABCDEF", seconds: 60)
        let grown = DayActivityCategoryTotal(categoryID: activeID, categoryName: "Active", categoryHex: "#ABCDEF", seconds: 61)
        XCTAssertEqual(TodayUsageSummaryProjection.entries(for: usageSnapshot(totals: [grown], totalSeconds: 61, localeIdentifier: "en_US")).first?.seconds, 61)
        XCTAssertEqual(TodayUsageSummaryProjection.durationText(first.seconds, localeIdentifier: "en_US"), "1 minute")

        let english = usageSnapshot(
            totals: [
                DayActivityCategoryTotal(categoryID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, categoryName: "b", categoryHex: "#111111", seconds: 60),
                DayActivityCategoryTotal(categoryID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, categoryName: "A", categoryHex: "#222222", seconds: 60)
            ],
            totalSeconds: 120,
            localeIdentifier: "en_US"
        )
        let korean = usageSnapshot(
            totals: [
                DayActivityCategoryTotal(categoryID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, categoryName: "나", categoryHex: "#111111", seconds: 60),
                DayActivityCategoryTotal(categoryID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, categoryName: "가", categoryHex: "#222222", seconds: 60)
            ],
            totalSeconds: 120,
            localeIdentifier: "ko_KR"
        )
        XCTAssertEqual(TodayUsageSummaryProjection.entries(for: english).map(\.name), ["A", "b"])
        XCTAssertEqual(TodayUsageSummaryProjection.entries(for: korean).map(\.name), ["가", "나"])
    }

    private func makeStore(
        calendar: Calendar,
        clock: TestClock,
        probe: ActivityFetchProbe,
        locale: Locale = Locale(identifier: "en_US_POSIX"),
        activeSessionID: UUID? = nil
    ) -> DayActivityStore {
        DayActivityStore(
            context: context,
            calendar: calendar,
            locale: locale,
            now: { clock.now },
            observesChanges: false,
            activeSessionID: activeSessionID,
            recordsFetcher: probe.fetch
        )
    }

    private func makeRecord(
        id: String = "00000000-0000-0000-0000-0000000000AA",
        start: Date,
        end: Date?,
        categoryName: String = "Study"
    ) -> DayActivityRecord {
        DayActivityRecord(
            sessionID: UUID(uuidString: id)!,
            start: start,
            end: end,
            categoryID: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB"),
            categoryName: categoryName,
            categoryHex: "#FFA94D",
            isRunning: end == nil
        )
    }

    private final class TestClock {
        var now: Date

        init(_ now: Date) {
            self.now = now
        }
    }

    private final class ActivityFetchProbe {
        enum Error: Swift.Error {
            case failed
        }

        var calls = 0
        var records: [DayActivityRecord]
        var error: Swift.Error?
        var requests: [(start: Date, end: Date, activeSessionID: UUID?)] = []

        init(records: [DayActivityRecord]) {
            self.records = records
        }

        func fetch(_ start: Date, _ end: Date, _ activeSessionID: UUID?) throws -> [DayActivityRecord] {
            calls += 1
            requests.append((start, end, activeSessionID))
            if let error { throw error }
            return records
        }
    }

    private final class ContextActivityFetchProbe {
        private let context: NSManagedObjectContext
        var calls = 0

        init(context: NSManagedObjectContext) {
            self.context = context
        }

        func fetch(_ start: Date, _ end: Date, _ activeSessionID: UUID?) throws -> [DayActivityRecord] {
            calls += 1
            let request = NSFetchRequest<SessionEntity>(entityName: "SessionEntity")
            let overlap = NSPredicate(
                format: "startTime < %@ AND (endTime == nil OR endTime > %@)",
                end as NSDate,
                start as NSDate
            )
            request.predicate = activeSessionID.map {
                NSCompoundPredicate(orPredicateWithSubpredicates: [
                    overlap,
                    NSPredicate(format: "id == %@", $0 as NSUUID)
                ])
            } ?? overlap
            return try context.fetch(request).map(DayActivityRecord.init(session:))
        }
    }

    private final class SaveSpy {
        var saveCount = 0

        func save(_ context: NSManagedObjectContext) throws {
            saveCount += 1
            if context.hasChanges { try context.save() }
        }
    }

    private func fetchSessions() throws -> [SessionEntity] {
        try context.fetch(NSFetchRequest<SessionEntity>(entityName: "SessionEntity"))
    }

    private var sessionFetcher: (Date, Date) -> [SessionEntity] {
        { [context] slotStart, slotEnd in
            let request = NSFetchRequest<SessionEntity>(entityName: "SessionEntity")
            request.predicate = NSPredicate(
                format: "startTime < %@ AND (endTime == nil OR endTime > %@)",
                slotEnd as NSDate,
                slotStart as NSDate
            )
            return (try? context?.fetch(request)) ?? []
        }
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func date(day: Int = 12, hour: Int, minute: Int, calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 4, day: day, hour: hour, minute: minute)))
    }

    private func usageSnapshot(
        totals: [DayActivityCategoryTotal],
        totalSeconds: TimeInterval,
        localeIdentifier: String
    ) -> DayActivitySnapshot {
        let calendar = Self.calendar
        let asOf = try! Self.date(hour: 12, minute: 0, calendar: calendar)
        let dayStart = calendar.startOfDay(for: asOf)
        return DayActivitySnapshot(
            segments: [],
            categoryTotals: totals,
            totalTrackedSeconds: totalSeconds,
            activeOrMostRecentID: nil,
            asOf: asOf,
            dayStart: dayStart,
            nextDayStart: calendar.date(byAdding: .day, value: 1, to: dayStart)!,
            calendarIdentifier: String(describing: calendar.identifier),
            localeIdentifier: localeIdentifier,
            timeZoneIdentifier: calendar.timeZone.identifier
        )
    }
}
