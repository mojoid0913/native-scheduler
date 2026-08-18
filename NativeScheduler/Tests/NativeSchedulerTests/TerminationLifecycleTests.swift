import CoreData
import XCTest
@testable import NativeScheduler

@MainActor
final class TerminationLifecycleTests: XCTestCase {
    func testFirstRunLaunchRegistrationFailureRemainsRetryable() {
        enum RegistrationError: Error {
            case denied
        }
        var attempts = 0
        var didRegister = false

        for _ in 0..<2 {
            let outcome = LaunchAtLoginMutation.apply(
                desiredEnabled: true,
                previousEnabled: didRegister
            ) {
                attempts += 1
                throw RegistrationError.denied
            }
            didRegister = outcome.isEnabled
            XCTAssertFalse(didRegister)
            XCTAssertNotNil(outcome.errorMessage)
        }

        XCTAssertEqual(attempts, 2)
    }

    func testLaunchAtLoginMutationFailureRestoresPreviousValue() {
        enum MutationError: Error {
            case denied
        }

        for previousEnabled in [false, true] {
            let outcome = LaunchAtLoginMutation.apply(
                desiredEnabled: !previousEnabled,
                previousEnabled: previousEnabled
            ) {
                throw MutationError.denied
            }

            XCTAssertEqual(outcome.isEnabled, previousEnabled)
            XCTAssertNotNil(outcome.errorMessage)
        }
    }

    func testApplicationTerminationFinalizesBeforeLoggingAtExactQuitTime() throws {
        let harness = try makeHarness()
        harness.viewModel.start()
        harness.events.values.removeAll()
        harness.clock.now = harness.start.addingTimeInterval(7 * 60)

        AppDelegate(panelController: harness.controller).applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        XCTAssertEqual(harness.events.values, ["save", "log"])
        XCTAssertEqual(harness.log.slots.reduce(0) { $0 + Int($1.dominantMinutes) }, 7)
        XCTAssertNil(harness.viewModel.activeSessionID)
        XCTAssertFalse(harness.viewModel.canRetryFinalization)

        harness.context.reset()
        let reopened = try XCTUnwrap(try fetchSessions(in: harness.context).first)
        XCTAssertEqual(reopened.endTime, harness.clock.now)
    }

    func testApplicationTerminationRetriesOnceThenLogsOnlyDurableCheckpoint() throws {
        let harness = try makeHarness()
        harness.viewModel.start()
        harness.clock.now = harness.start.addingTimeInterval(10 * 60)
        harness.viewModel.processPersistenceTick()
        harness.events.values.removeAll()
        harness.save.failuresRemaining = 2
        harness.clock.now = harness.start.addingTimeInterval(12 * 60)

        AppDelegate(panelController: harness.controller).applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        XCTAssertEqual(harness.events.values, ["save", "save", "log"])
        XCTAssertEqual(harness.save.failuresRemaining, 0)
        XCTAssertEqual(harness.log.slots.reduce(0) { $0 + Int($1.dominantMinutes) }, 10)
        XCTAssertNil(harness.viewModel.activeSessionID)
        XCTAssertTrue(harness.viewModel.canRetryFinalization)
        XCTAssertEqual(harness.viewModel.recordingError, "Recording could not be finalized. Retry.")

        harness.context.reset()
        let reopened = try XCTUnwrap(try fetchSessions(in: harness.context).first)
        XCTAssertEqual(reopened.endTime, harness.start.addingTimeInterval(10 * 60))
    }

    func testRepeatedTerminationAfterDoubleFailureDoesNotSaveLogOrMutateErrorAgain() throws {
        let harness = try makeHarness()
        harness.viewModel.start()
        harness.clock.now = harness.start.addingTimeInterval(10 * 60)
        harness.viewModel.processPersistenceTick()
        harness.events.values.removeAll()
        harness.save.failuresRemaining = 2
        harness.clock.now = harness.start.addingTimeInterval(12 * 60)
        let delegate = AppDelegate(panelController: harness.controller)
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        let eventsAfterFirstCallback = harness.events.values
        let errorAfterFirstCallback = harness.viewModel.recordingError
        let endAfterFirstCallback = try XCTUnwrap(try fetchSessions(in: harness.context).first).endTime

        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        XCTAssertEqual(harness.events.values, eventsAfterFirstCallback)
        XCTAssertEqual(harness.viewModel.recordingError, errorAfterFirstCallback)
        XCTAssertEqual(try fetchSessions(in: harness.context).first?.endTime, endAfterFirstCallback)
        XCTAssertTrue(harness.viewModel.canRetryFinalization)
        XCTAssertNil(harness.viewModel.activeSessionID)
    }

    func testDailyLogTreatsLegacyNilEndAsZeroWithoutMutatingRawRow() throws {
        let harness = try makeHarness()
        let session = SessionEntity.create(
            startTime: harness.start,
            mode: .duration,
            category: nil,
            in: harness.context
        )
        try harness.context.save()
        let before = RawSession(session)
        harness.clock.now = harness.start.addingTimeInterval(10 * 60)

        try harness.controller.flushDailyLog()

        XCTAssertTrue(harness.log.slots.isEmpty)
        XCTAssertEqual(RawSession(session), before)
        XCTAssertFalse(harness.context.hasChanges)
    }

    func testMidnightRolloverTargetsTheCompletedCalendarDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let midnight = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2027,
            month: 3,
            day: 15
        )))

        let completedDate = try XCTUnwrap(
            DailyLogRollover.completedDate(before: midnight, calendar: calendar)
        )

        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: completedDate),
            DateComponents(year: 2027, month: 3, day: 14)
        )
    }

    func testDailyLogFetchFailurePreservesExistingLogAndSkipsWriter() throws {
        enum FetchFailure: Error {
            case injected
        }
        let harness = try makeHarness(fetchSessions: { _, _ in
            throw FetchFailure.injected
        })
        let existingLog = Data("existing-log".utf8)
        var retainedLog = existingLog
        harness.log.onWrite = {
            retainedLog = Data()
        }

        XCTAssertThrowsError(try harness.controller.flushDailyLog(for: harness.start))
        XCTAssertEqual(retainedLog, existingLog)
        XCTAssertFalse(harness.events.values.contains("log"))
    }

    func testDailyLogRoundTripPreservesUncategorizedOccupiedSlot() throws {
        let harness = try makeHarness()
        let encoded = DailyLogWriter.encode(
            slots: [
                HeatmapSlotData(index: 7, categoryIndex: 0, dominantMinutes: 5)
            ],
            date: harness.start,
            categories: []
        )

        let decoded = try XCTUnwrap(DailyLogWriter.decode(encoded))

        XCTAssertEqual(decoded[7]?.categoryIndex, 0)
        XCTAssertEqual(decoded[7]?.dominantMinutes, 5)
    }

    private struct Harness {
        let start: Date
        let context: NSManagedObjectContext
        let clock: TestClock
        let events: EventLog
        let save: SaveSpy
        let log: LogSpy
        let viewModel: TimerViewModel
        let controller: FloatingPanelController
    }

    private struct RawSession: Equatable {
        let id: UUID
        let startTime: Date
        let endTime: Date?
        let timerMode: String
        let categoryID: NSManagedObjectID?

        init(_ session: SessionEntity) {
            id = session.id
            startTime = session.startTime
            endTime = session.endTime
            timerMode = session.timerMode
            categoryID = session.category?.objectID
        }
    }

    private final class TestClock {
        var now: Date
        init(now: Date) { self.now = now }
    }

    private final class EventLog {
        var values: [String] = []
    }

    private final class SaveSpy {
        enum Failure: Error { case injected }

        let events: EventLog
        var failuresRemaining = 0

        init(events: EventLog) {
            self.events = events
        }

        func save(_ context: NSManagedObjectContext) throws {
            events.values.append("save")
            if failuresRemaining > 0 {
                failuresRemaining -= 1
                throw Failure.injected
            }
            if context.hasChanges { try context.save() }
        }
    }

    private final class LogSpy {
        let events: EventLog
        var slots: [HeatmapSlotData] = []
        var onWrite: () -> Void = {}

        init(events: EventLog) {
            self.events = events
        }

        func write(slots: [HeatmapSlotData], date: Date, categories: [CategoryData]) {
            events.values.append("log")
            self.slots = slots
            onWrite()
        }
    }

    private func makeHarness(
        fetchSessions: @escaping (
            NSManagedObjectContext,
            NSFetchRequest<SessionEntity>
        ) throws -> [SessionEntity] = { context, request in
            try context.fetch(request)
        }
    ) throws -> Harness {
        let container = NSPersistentContainer(name: "TerminationLifecycleTests", managedObjectModel: CoreDataStack.model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2027,
            month: 1,
            day: 15,
            hour: 8
        )))
        let clock = TestClock(now: start)
        let events = EventLog()
        let save = SaveSpy(events: events)
        let log = LogSpy(events: events)
        let engine = TimerEngine(tickInterval: .seconds(3_600), soundPlayer: {})
        engine.durationSeconds = 60 * 60
        let viewModel = TimerViewModel(
            engine: engine,
            context: container.viewContext,
            now: { clock.now },
            save: save.save
        )
        let controller = FloatingPanelController(
            timerVM: viewModel,
            context: container.viewContext,
            now: { clock.now },
            writeDailyLog: log.write,
            fetchSessions: fetchSessions
        )
        return Harness(
            start: start,
            context: container.viewContext,
            clock: clock,
            events: events,
            save: save,
            log: log,
            viewModel: viewModel,
            controller: controller
        )
    }

    private func fetchSessions(in context: NSManagedObjectContext) throws -> [SessionEntity] {
        try context.fetch(NSFetchRequest<SessionEntity>(entityName: "SessionEntity"))
    }
}
