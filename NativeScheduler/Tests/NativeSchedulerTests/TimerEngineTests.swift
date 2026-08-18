import XCTest
import CoreGraphics
import CoreData
import Combine
@testable import NativeScheduler

@MainActor
final class TimerEngineTests: XCTestCase {
    func testFreshCountUpPublishesZeroThenMonotonicElapsedWithoutFinishing() {
        let harness = makeHarness()
        harness.engine.mode = .countUp
        var ticks: [TimeInterval] = []
        var finishCount = 0
        harness.engine.onTick = { ticks.append($0) }
        harness.engine.onFinish = { finishCount += 1 }

        harness.engine.start()
        harness.clock.advance(by: 2.5)
        harness.factory.current.fire()

        XCTAssertEqual(ticks, [0, 2.5])
        XCTAssertEqual(harness.engine.remaining, 2.5, accuracy: 0.000_001)
        XCTAssertEqual(finishCount, 0)
        XCTAssertEqual(harness.factory.created.count, 1)
    }

    func testCountUpUsesMonotonicClockAcrossWallClockChangesAndResume() {
        let harness = makeHarness()
        harness.engine.mode = .countUp
        harness.engine.start()
        harness.clock.advanceWall(by: 10_000)
        harness.clock.advanceMonotonic(by: 3.25)
        harness.factory.current.fire()
        harness.engine.pause()

        XCTAssertEqual(harness.engine.remaining, 3.25, accuracy: 0.000_001)
        XCTAssertTrue(harness.engine.isPaused)

        harness.clock.advanceWall(by: -20_000)
        harness.clock.advanceMonotonic(by: 100)
        harness.engine.start()
        harness.clock.advanceMonotonic(by: 1.75)
        harness.factory.current.fire()

        XCTAssertEqual(harness.engine.remaining, 5, accuracy: 0.000_001)
        XCTAssertEqual(harness.factory.created.count, 2)
        XCTAssertEqual(harness.factory.activeCount, 1)
        harness.engine.reset()
        XCTAssertEqual(harness.engine.remaining, 0, accuracy: 0.000_001)
    }

    func testDurationPauseSnapshotsExactRemainingBetweenTicks() {
        let harness = makeHarness()
        harness.engine.durationSeconds = 10
        harness.engine.start()

        harness.clock.advance(by: 3.25)
        harness.engine.pause()

        XCTAssertEqual(harness.engine.remaining, 6.75, accuracy: 0.000_001)
        XCTAssertTrue(harness.engine.isPaused)
        XCTAssertEqual(harness.factory.created.count, 1)
        XCTAssertEqual(harness.factory.activeCount, 0)
    }

    func testEndTimePauseSnapshotsExactRemainingBetweenTicks() {
        let harness = makeHarness()
        harness.engine.mode = .endTime
        harness.engine.targetEndTime = harness.clock.wall.addingTimeInterval(10)
        harness.engine.start()

        harness.clock.advance(by: 3.25)
        harness.engine.pause()

        XCTAssertEqual(harness.engine.remaining, 6.75, accuracy: 0.000_001)
        XCTAssertEqual(harness.engine.durationSeconds, 10, accuracy: 0.000_001)
        XCTAssertTrue(harness.engine.isPaused)
    }

    func testRepeatedPauseResumeAccumulatesExactlyRunningTime() {
        let harness = makeHarness()
        harness.engine.durationSeconds = 10
        harness.engine.start()
        harness.clock.advance(by: 1.25)
        harness.engine.pause()
        XCTAssertEqual(harness.engine.remaining, 8.75, accuracy: 0.000_001)

        harness.clock.advance(by: 50)
        harness.engine.start()
        harness.clock.advance(by: 2.5)
        harness.engine.pause()
        XCTAssertEqual(harness.engine.remaining, 6.25, accuracy: 0.000_001)

        harness.engine.start()
        harness.clock.advance(by: 6.25)
        harness.factory.current.fire()

        XCTAssertTrue(harness.engine.isFinished)
        XCTAssertEqual(harness.factory.created.count, 3)
        XCTAssertEqual(harness.factory.activeCount, 0)
    }

    func testDurationFinishesWithExactlyOneFinishAndSound() {
        let harness = makeHarness()
        harness.engine.durationSeconds = 10
        var finishCount = 0
        harness.engine.onFinish = { finishCount += 1 }
        harness.engine.start()
        let ticker = harness.factory.current

        harness.clock.advance(by: 10)
        ticker.fire()
        ticker.fireEvenIfCancelled()
        harness.engine.finish()

        XCTAssertFalse(harness.engine.isRunning)
        XCTAssertTrue(harness.engine.isFinished)
        XCTAssertEqual(harness.engine.remaining, 0, accuracy: 0.000_001)
        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(harness.sound.count, 1)
    }

    func testDelayedTickerFinishesAtConfiguredDeadline() {
        let harness = makeHarness()
        harness.engine.durationSeconds = 10
        harness.engine.start()
        let deadline = harness.clock.wall.addingTimeInterval(10)
        harness.clock.advance(by: 15)
        harness.factory.current.fire()

        XCTAssertEqual(harness.engine.lastCompletionDate, deadline)
    }

    func testCancelledStaleCallbackCannotMutateOrFinishResumedTimer() {
        let harness = makeHarness()
        harness.engine.durationSeconds = 10
        var finishCount = 0
        harness.engine.onFinish = { finishCount += 1 }
        harness.engine.start()
        let staleTicker = harness.factory.current
        harness.clock.advance(by: 3)
        harness.engine.pause()
        harness.engine.start()
        let resumedRemaining = harness.engine.remaining

        harness.clock.advance(by: 20)
        staleTicker.fireEvenIfCancelled()

        XCTAssertTrue(harness.engine.isRunning)
        XCTAssertFalse(harness.engine.isFinished)
        XCTAssertEqual(harness.engine.remaining, resumedRemaining, accuracy: 0.000_001)
        XCTAssertEqual(finishCount, 0)
        XCTAssertEqual(harness.sound.count, 0)
        XCTAssertEqual(harness.factory.activeCount, 1)
    }

    func testStopCancelsTickerAndStaleCallbackCannotMutate() {
        let harness = makeHarness()
        harness.engine.durationSeconds = 10
        harness.engine.start()
        let staleTicker = harness.factory.current
        harness.engine.stop()
        harness.clock.advance(by: 20)

        staleTicker.fireEvenIfCancelled()

        XCTAssertFalse(harness.engine.isRunning)
        XCTAssertFalse(harness.engine.isFinished)
        XCTAssertEqual(harness.engine.remaining, 10, accuracy: 0.000_001)
        XCTAssertEqual(harness.sound.count, 0)
    }

    func testEndTimeCountdownPreservesSecondsUntilTarget() {
        let harness = makeHarness()
        harness.engine.mode = .endTime
        harness.engine.targetEndTime = harness.clock.wall.addingTimeInterval(14.8)

        harness.engine.prepareEndTimeCountdown()

        XCTAssertEqual(harness.engine.remaining, 14.8, accuracy: 0.000_001)
        XCTAssertEqual(harness.engine.durationSeconds, 14.8, accuracy: 0.000_001)
    }

    func testPrepareEndTimeCountdownDoesNotClobberRunningProgress() {
        let harness = makeHarness()
        harness.engine.durationSeconds = 120
        harness.engine.start()
        harness.clock.advance(by: 5)
        harness.factory.current.fire()
        let remaining = harness.engine.remaining
        harness.engine.targetEndTime = harness.clock.wall.addingTimeInterval(-1)

        harness.engine.prepareEndTimeCountdown()

        XCTAssertTrue(harness.engine.isRunning)
        XCTAssertEqual(harness.engine.remaining, remaining, accuracy: 0.000_001)
    }

    func testPastEndTimeCompletesImmediatelyWithoutTicker() {
        let harness = makeHarness()
        var finishCount = 0
        harness.engine.mode = .endTime
        harness.engine.targetEndTime = harness.clock.wall.addingTimeInterval(-1)
        harness.engine.onFinish = { finishCount += 1 }

        harness.engine.start()

        XCTAssertFalse(harness.engine.isRunning)
        XCTAssertTrue(harness.engine.isFinished)
        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(harness.sound.count, 1)
        XCTAssertTrue(harness.factory.created.isEmpty)
    }

    func testProductionDispatchTickerInstallsAndCancelsInIsolatedProcess() throws {
        let childEnvironmentKey = "NATIVE_SCHEDULER_PRODUCTION_TIMER_TICKER_CHILD"
        if ProcessInfo.processInfo.environment[childEnvironmentKey] != "1" {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = [
                "-XCTest",
                "NativeSchedulerTests.TimerEngineTests/testProductionDispatchTickerInstallsAndCancelsInIsolatedProcess",
                Bundle(for: TimerEngineTests.self).bundlePath
            ]
            var environment = ProcessInfo.processInfo.environment
            environment[childEnvironmentKey] = "1"
            process.environment = environment
            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error
            let terminated = expectation(description: "production Timer ticker child exits")
            process.terminationHandler = { _ in terminated.fulfill() }

            try process.run()
            wait(for: [terminated], timeout: 30)

            let standardOutput = String(
                decoding: output.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            let standardError = String(
                decoding: error.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
            XCTAssertEqual(process.terminationStatus, 0, standardOutput + standardError)
            return
        }

        let engine = TimerEngine(
            tickInterval: .seconds(3_600),
            leeway: .milliseconds(10),
            soundPlayer: {}
        )
        engine.mode = .countUp
        engine.start()
        XCTAssertTrue(engine.isRunning)
        engine.pause()
        XCTAssertTrue(engine.isPaused)
    }

    private struct Harness {
        let clock: ManualClock
        let factory: ManualTickerFactory
        let sound: SoundSpy
        let engine: TimerEngine
    }

    private final class ManualClock {
        var wall = Date(timeIntervalSince1970: 1_800_000_000)
        var monotonic: TimeInterval = 1_000

        func advance(by interval: TimeInterval) {
            advanceWall(by: interval)
            advanceMonotonic(by: interval)
        }

        func advanceWall(by interval: TimeInterval) {
            wall = wall.addingTimeInterval(interval)
        }

        func advanceMonotonic(by interval: TimeInterval) {
            monotonic += interval
        }
    }

    @MainActor
    private final class ManualTicker: TimerEngineTicker {
        private let action: @MainActor () -> Void
        private(set) var isCancelled = false

        init(action: @escaping @MainActor () -> Void) {
            self.action = action
        }

        func cancel() { isCancelled = true }
        func fire() {
            guard !isCancelled else { return }
            action()
        }
        func fireEvenIfCancelled() { action() }
    }

    @MainActor
    private final class ManualTickerFactory {
        private(set) var created: [ManualTicker] = []
        var current: ManualTicker { created[created.count - 1] }
        var activeCount: Int { created.filter { !$0.isCancelled }.count }

        func make(action: @escaping @MainActor () -> Void) -> TimerEngineTicker {
            let ticker = ManualTicker(action: action)
            created.append(ticker)
            return ticker
        }
    }

    private final class SoundSpy {
        var count = 0
        func play() { count += 1 }
    }

    private func makeHarness() -> Harness {
        let clock = ManualClock()
        let factory = ManualTickerFactory()
        let sound = SoundSpy()
        let engine = TimerEngine(
            wallClock: { clock.wall },
            monotonicClock: { clock.monotonic },
            tickerFactory: factory.make,
            soundPlayer: sound.play
        )
        return Harness(clock: clock, factory: factory, sound: sound, engine: engine)
    }
}

@MainActor
final class TimerViewModelPersistenceTests: XCTestCase {
    func testCountUpStartToStopPersistsExactlyOneExactSegment() throws {
        let harness = try makeHarness()
        harness.viewModel.engine.mode = .countUp

        harness.viewModel.start()
        harness.clock.now = harness.start.addingTimeInterval(7)
        harness.viewModel.pause()

        let sessions = try fetchSessions(in: harness.context)
        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(session.timerMode, TimerMode.countUp.rawValue)
        XCTAssertEqual(session.startTime, harness.start)
        XCTAssertEqual(session.endTime, harness.clock.now)
        XCTAssertEqual(harness.save.saveCount, 2)
    }

    func testCountUpResumeContinuesElapsedAndCreatesNextPersistedSegment() throws {
        let harness = try makeHarness()
        harness.viewModel.engine.mode = .countUp
        harness.viewModel.start()
        harness.clock.now = harness.start.addingTimeInterval(5)
        harness.viewModel.pause()
        let pausedElapsed = harness.viewModel.engine.remaining

        harness.clock.now = harness.start.addingTimeInterval(20)
        harness.viewModel.start()
        XCTAssertEqual(harness.viewModel.engine.remaining, pausedElapsed, accuracy: 0.001)
        harness.clock.now = harness.start.addingTimeInterval(24)
        harness.viewModel.pause()

        let sessions = try fetchSessions(in: harness.context).sorted { $0.startTime < $1.startTime }
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.map(\.timerMode), ["countUp", "countUp"])
        XCTAssertEqual(sessions[0].endTime?.timeIntervalSince(sessions[0].startTime), 5)
        XCTAssertEqual(sessions[1].endTime?.timeIntervalSince(sessions[1].startTime), 4)
    }

    func testCountUpDefaultParsesThroughTimerModeRawValue() throws {
        let defaults = UserDefaults.standard
        let previousMode = defaults.object(forKey: "defaultTimerMode")
        defer {
            if let previousMode { defaults.set(previousMode, forKey: "defaultTimerMode") }
            else { defaults.removeObject(forKey: "defaultTimerMode") }
        }
        defaults.set(TimerMode.countUp.rawValue, forKey: "defaultTimerMode")

        let harness = try makeHarness()

        XCTAssertEqual(harness.viewModel.engine.mode, .countUp)
        XCTAssertEqual(harness.viewModel.engine.remaining, 0, accuracy: 0.001)
    }

    func testStartAndPausePersistOneRealSession() throws {
        let harness = try makeHarness()

        harness.viewModel.start()
        harness.clock.now = harness.clock.now.addingTimeInterval(7)
        harness.viewModel.pause()

        let session = try XCTUnwrap(try fetchSessions(in: harness.context).first)
        XCTAssertEqual(session.startTime, harness.start)
        XCTAssertEqual(session.endTime, harness.clock.now)
        XCTAssertEqual(harness.save.saveCount, 2)
        XCTAssertTrue(harness.viewModel.engine.isPaused)
    }

    func testStartPublishesAuthorityOnlyAfterDurableZeroLengthRow() throws {
        let harness = try makeHarness()

        harness.viewModel.start()

        let session = try XCTUnwrap(try fetchSessions(in: harness.context).first)
        XCTAssertEqual(session.startTime, harness.start)
        XCTAssertEqual(session.endTime, harness.start)
        XCTAssertEqual(harness.viewModel.activeSessionID, session.id)
        XCTAssertNil(harness.viewModel.recordingError)
        XCTAssertEqual(harness.save.saveCount, 1)
    }

    func testEndTimeStartUsesInjectedInstantForValidationAndPersistence() throws {
        let harness = try makeHarness()
        harness.viewModel.engine.mode = .endTime
        harness.viewModel.engine.targetEndTime = harness.start.addingTimeInterval(60)

        harness.viewModel.start()

        let session = try XCTUnwrap(try fetchSessions(in: harness.context).first)
        XCTAssertEqual(harness.viewModel.engine.sessionTotal, 60, accuracy: 0.001)
        XCTAssertEqual(session.startTime, harness.start)
        XCTAssertEqual(session.endTime, harness.start)
        XCTAssertEqual(harness.viewModel.activeSessionID, session.id)
    }

    func testDelayedAutomaticFinishPersistsConfiguredDeadline() throws {
        let harness = try makeHarness()
        harness.viewModel.engine.durationSeconds = 10
        harness.viewModel.start()
        let deadline = harness.start.addingTimeInterval(10)
        harness.clock.now = harness.start.addingTimeInterval(15)

        harness.viewModel.engine.finish(at: deadline)

        let session = try XCTUnwrap(try fetchSessions(in: harness.context).first)
        XCTAssertEqual(session.endTime, deadline)
        XCTAssertGreaterThan(harness.clock.now, deadline)
    }

    func testStartFailureStopsEngineAndPublishesNoAuthority() throws {
        let harness = try makeHarness()
        harness.save.failNext = true

        harness.viewModel.start()

        XCTAssertFalse(harness.viewModel.engine.isRunning)
        XCTAssertNil(harness.viewModel.activeSessionID)
        XCTAssertNotNil(harness.viewModel.recordingError)
        XCTAssertTrue(try fetchSessions(in: harness.context).isEmpty)
    }

    func testCheckpointOccursAtTenSecondsButNotNinePointNine() throws {
        let harness = try makeHarness()
        harness.viewModel.start()

        harness.clock.now = harness.start.addingTimeInterval(9.9)
        harness.viewModel.processPersistenceTick()
        XCTAssertEqual(harness.save.saveCount, 1)

        harness.clock.now = harness.start.addingTimeInterval(10)
        harness.viewModel.processPersistenceTick()

        XCTAssertEqual(harness.save.saveCount, 2)
        XCTAssertEqual(try fetchSessions(in: harness.context).first?.endTime, harness.clock.now)
    }

    func testThirtyOneSecondRunHasOnlyThreeCheckpointSaves() throws {
        let harness = try makeHarness()
        harness.viewModel.start()

        for second in 1...31 {
            harness.clock.now = harness.start.addingTimeInterval(TimeInterval(second))
            harness.viewModel.processPersistenceTick()
        }

        XCTAssertEqual(harness.save.saveCount, 4)
        XCTAssertEqual(try fetchSessions(in: harness.context).first?.endTime, harness.start.addingTimeInterval(30))
    }

    func testPauseResumeExcludesPausedTimeAndRepeatedFinalizationIsIdempotent() throws {
        let harness = try makeHarness()
        harness.viewModel.start()
        harness.clock.now = harness.start.addingTimeInterval(5)

        harness.viewModel.pause()
        harness.viewModel.pause()
        harness.clock.now = harness.start.addingTimeInterval(20)
        harness.viewModel.start()
        harness.clock.now = harness.start.addingTimeInterval(24)
        harness.viewModel.stop()
        harness.viewModel.stop()

        let sessions = try fetchSessions(in: harness.context).sorted { $0.startTime < $1.startTime }
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].endTime?.timeIntervalSince(sessions[0].startTime), 5)
        XCTAssertEqual(sessions[1].endTime?.timeIntervalSince(sessions[1].startTime), 4)
        XCTAssertEqual(harness.save.saveCount, 4)
        XCTAssertNil(harness.viewModel.activeSessionID)
    }

    func testStopResetSmokeAndFinishUseExactCapturedFinalTime() throws {
        for transition in FinalTransition.allCases {
            let harness = try makeHarness()
            harness.viewModel.start()
            harness.clock.now = harness.start.addingTimeInterval(6)

            switch transition {
            case .stop: harness.viewModel.stop()
            case .reset: harness.viewModel.reset()
            case .smoke: harness.viewModel.configureSmokeTimer(mode: .duration, duration: 2)
            case .finish: harness.viewModel.engine.finish()
            }

            let session = try XCTUnwrap(try fetchSessions(in: harness.context).first)
            XCTAssertEqual(session.endTime, harness.clock.now, transition.rawValue)
            XCTAssertNil(harness.viewModel.activeSessionID, transition.rawValue)
            XCTAssertEqual(harness.save.saveCount, 2, transition.rawValue)
        }
    }

    func testCheckpointFailureKeepsAuthorityAndRetriesAtNextThreshold() throws {
        let harness = try makeHarness()
        harness.viewModel.start()
        let sessionID = try XCTUnwrap(harness.viewModel.activeSessionID)
        harness.save.failNext = true
        harness.clock.now = harness.start.addingTimeInterval(10)

        harness.viewModel.processPersistenceTick()

        XCTAssertTrue(harness.viewModel.engine.isRunning)
        XCTAssertEqual(harness.viewModel.activeSessionID, sessionID)
        XCTAssertEqual(try fetchSessions(in: harness.context).first?.endTime, harness.start)

        harness.clock.now = harness.start.addingTimeInterval(20)
        harness.viewModel.processPersistenceTick()
        XCTAssertEqual(try fetchSessions(in: harness.context).first?.endTime, harness.clock.now)
        XCTAssertEqual(harness.save.saveCount, 3)
    }

    func testFinalSaveFailureClearsAuthorityAndCanRetryExactBoundary() throws {
        let harness = try makeHarness()
        harness.viewModel.start()
        harness.clock.now = harness.start.addingTimeInterval(8)
        harness.save.failNext = true

        harness.viewModel.pause()

        XCTAssertNil(harness.viewModel.activeSessionID)
        XCTAssertTrue(harness.viewModel.canRetryFinalization)
        XCTAssertEqual(try fetchSessions(in: harness.context).first?.endTime, harness.start)

        harness.viewModel.retryFinalization()
        XCTAssertFalse(harness.viewModel.canRetryFinalization)
        XCTAssertEqual(try fetchSessions(in: harness.context).first?.endTime, harness.clock.now)
        XCTAssertEqual(harness.save.saveCount, 3)
    }

    func testExistingIdleViewModelRefreshesChangedTimerDefaults() throws {
        let defaults = UserDefaults.standard
        let previousDuration = defaults.object(forKey: "defaultTimerDuration")
        let previousMode = defaults.object(forKey: "defaultTimerMode")
        defer {
            if let previousDuration { defaults.set(previousDuration, forKey: "defaultTimerDuration") }
            else { defaults.removeObject(forKey: "defaultTimerDuration") }
            if let previousMode { defaults.set(previousMode, forKey: "defaultTimerMode") }
            else { defaults.removeObject(forKey: "defaultTimerMode") }
        }
        defaults.set(25, forKey: "defaultTimerDuration")
        defaults.set("duration", forKey: "defaultTimerMode")
        let harness = try makeHarness()

        defaults.set(45, forKey: "defaultTimerDuration")
        defaults.set("endTime", forKey: "defaultTimerMode")
        harness.viewModel.refreshSettings()

        XCTAssertEqual(harness.viewModel.engine.durationSeconds, 45 * 60)
        XCTAssertEqual(harness.viewModel.engine.mode, .endTime)
        XCTAssertFalse(harness.viewModel.engine.isRunning)
        XCTAssertFalse(harness.viewModel.engine.isPaused)
    }

    func testSettingsRefreshDoesNotClobberRunningOrPausedTimerAuthority() throws {
        let defaults = UserDefaults.standard
        let previousDuration = defaults.object(forKey: "defaultTimerDuration")
        let previousMode = defaults.object(forKey: "defaultTimerMode")
        defer {
            if let previousDuration { defaults.set(previousDuration, forKey: "defaultTimerDuration") }
            else { defaults.removeObject(forKey: "defaultTimerDuration") }
            if let previousMode { defaults.set(previousMode, forKey: "defaultTimerMode") }
            else { defaults.removeObject(forKey: "defaultTimerMode") }
        }
        defaults.set(25, forKey: "defaultTimerDuration")
        defaults.set("duration", forKey: "defaultTimerMode")
        let harness = try makeHarness()
        harness.viewModel.engine.durationSeconds = 10 * 60
        harness.viewModel.start()
        let runningTotal = harness.viewModel.engine.sessionTotal
        let runningDuration = harness.viewModel.engine.durationSeconds
        let runningMode = harness.viewModel.engine.mode

        defaults.set(55, forKey: "defaultTimerDuration")
        defaults.set("endTime", forKey: "defaultTimerMode")
        harness.viewModel.refreshSettings()

        XCTAssertTrue(harness.viewModel.engine.isRunning)
        XCTAssertEqual(harness.viewModel.engine.sessionTotal, runningTotal, accuracy: 0.001)
        XCTAssertEqual(harness.viewModel.engine.durationSeconds, runningDuration)
        XCTAssertEqual(harness.viewModel.engine.mode, runningMode)

        harness.viewModel.pause()
        let pausedRemaining = harness.viewModel.engine.remaining
        harness.viewModel.refreshSettings()

        XCTAssertTrue(harness.viewModel.engine.isPaused)
        XCTAssertEqual(harness.viewModel.engine.remaining, pausedRemaining, accuracy: 0.001)
        XCTAssertEqual(harness.viewModel.engine.durationSeconds, runningDuration)
        XCTAssertEqual(harness.viewModel.engine.mode, runningMode)
    }

    func testLoadCategoriesClearsDeletedSelectedCategory() throws {
        let harness = try makeHarness()
        let category = CategoryEntity.create(name: "Temporary", colorHex: "#4DABF7", sortOrder: 0, in: harness.context)
        try harness.context.save()
        harness.viewModel.loadCategories()
        harness.viewModel.selectedCategory = category

        harness.context.delete(category)
        try harness.context.save()
        harness.viewModel.loadCategories()

        XCTAssertTrue(harness.viewModel.categories.isEmpty)
        XCTAssertNil(harness.viewModel.selectedCategory)
    }

    func testCategorySwitchUsesOneTimestampAndOneSave() throws {
        let harness = try makeHarness()
        let category = CategoryEntity.create(name: "New", colorHex: "#FFA94D", sortOrder: 0, in: harness.context)
        try harness.context.save()
        harness.viewModel.start()
        let savesBeforeSwitch = harness.save.saveCount
        harness.clock.now = harness.start.addingTimeInterval(12)

        harness.viewModel.changeCategory(to: category)

        let sessions = try fetchSessions(in: harness.context).sorted { $0.startTime < $1.startTime }
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].endTime, harness.clock.now)
        XCTAssertEqual(sessions[1].startTime, harness.clock.now)
        XCTAssertEqual(sessions[1].endTime, harness.clock.now)
        XCTAssertEqual(harness.viewModel.activeSessionID, sessions[1].id)
        XCTAssertEqual(harness.viewModel.selectedCategory, category)
        XCTAssertEqual(harness.save.saveCount, savesBeforeSwitch + 1)
    }

    func testCategorySaveFailureRollsBackReplacementAndRetainsAuthority() throws {
        let harness = try makeHarness()
        let original = CategoryEntity.create(name: "Old", colorHex: "#4DABF7", sortOrder: 0, in: harness.context)
        let replacement = CategoryEntity.create(name: "New", colorHex: "#FFA94D", sortOrder: 1, in: harness.context)
        try harness.context.save()
        harness.viewModel.selectedCategory = original
        harness.viewModel.start()
        let originalAuthority = try XCTUnwrap(harness.viewModel.activeSessionID)
        harness.clock.now = harness.start.addingTimeInterval(12)
        harness.save.failNext = true

        harness.viewModel.changeCategory(to: replacement)

        let sessions = try fetchSessions(in: harness.context)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].id, originalAuthority)
        XCTAssertEqual(sessions[0].endTime, harness.start)
        XCTAssertEqual(harness.viewModel.activeSessionID, originalAuthority)
        XCTAssertEqual(harness.viewModel.selectedCategory, original)
        XCTAssertNotNil(harness.viewModel.recordingError)
    }

    func testTwentyFiveSecondRunPauseResumeCategorySwitchAndStopHasExactRows() throws {
        let harness = try makeHarness()
        let category = CategoryEntity.create(name: "Focus", colorHex: "#FFA94D", sortOrder: 0, in: harness.context)
        try harness.context.save()

        harness.viewModel.start()
        for second in 1...25 {
            harness.clock.now = harness.start.addingTimeInterval(TimeInterval(second))
            harness.viewModel.processPersistenceTick()
        }
        harness.viewModel.pause()
        harness.clock.now = harness.start.addingTimeInterval(30)
        harness.viewModel.start()
        harness.clock.now = harness.start.addingTimeInterval(42)
        harness.viewModel.processPersistenceTick()
        harness.viewModel.changeCategory(to: category)
        harness.clock.now = harness.start.addingTimeInterval(45)
        harness.viewModel.stop()

        let sessions = try fetchSessions(in: harness.context).sorted { $0.startTime < $1.startTime }
        XCTAssertEqual(sessions.count, 3)
        XCTAssertEqual(sessions.map(\.startTime), [
            harness.start,
            harness.start.addingTimeInterval(30),
            harness.start.addingTimeInterval(42)
        ])
        XCTAssertEqual(sessions.compactMap(\.endTime), [
            harness.start.addingTimeInterval(25),
            harness.start.addingTimeInterval(42),
            harness.start.addingTimeInterval(45)
        ])
        XCTAssertEqual(sessions.map { $0.category?.id }, [nil, nil, category.id])
        XCTAssertEqual(harness.save.saveCount, 8)
        XCTAssertEqual(sessions.reduce(0) { $0 + ($1.endTime?.timeIntervalSince($1.startTime) ?? 0) }, 40)
    }

    private enum FinalTransition: String, CaseIterable {
        case stop, reset, smoke, finish
    }

    private struct Harness {
        let start: Date
        let context: NSManagedObjectContext
        let clock: TestClock
        let save: SaveSpy
        let viewModel: TimerViewModel
    }

    private final class TestClock {
        var now: Date
        init(now: Date) { self.now = now }
    }

    private final class SaveSpy {
        enum Failure: Error { case injected }
        var saveCount = 0
        var failNext = false

        func save(_ context: NSManagedObjectContext) throws {
            saveCount += 1
            if failNext {
                failNext = false
                throw Failure.injected
            }
            if context.hasChanges { try context.save() }
        }
    }

    private func makeHarness() throws -> Harness {
        let container = NSPersistentContainer(name: "TimerViewModelTests", managedObjectModel: CoreDataStack.model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = TestClock(now: start)
        let save = SaveSpy()
        let engine = TimerEngine(tickInterval: .seconds(3_600), soundPlayer: {})
        let viewModel = TimerViewModel(
            engine: engine,
            context: container.viewContext,
            now: { clock.now },
            save: save.save
        )
        return Harness(start: start, context: container.viewContext, clock: clock, save: save, viewModel: viewModel)
    }

    private func fetchSessions(in context: NSManagedObjectContext) throws -> [SessionEntity] {
        try context.fetch(NSFetchRequest<SessionEntity>(entityName: "SessionEntity"))
    }
}

final class TimerProgressTests: XCTestCase {
    func testProgressIsClampedAndRequiresRunningTimer() {
        XCTAssertEqual(TimerProgress.fraction(remaining: 30, sessionTotal: 60, isRunning: true), 0.5, accuracy: 0.001)
        XCTAssertEqual(TimerProgress.fraction(remaining: -10, sessionTotal: 60, isRunning: true), 1, accuracy: 0.001)
        XCTAssertEqual(TimerProgress.fraction(remaining: 90, sessionTotal: 60, isRunning: true), 0, accuracy: 0.001)
        XCTAssertEqual(TimerProgress.fraction(remaining: 30, sessionTotal: 60, isRunning: false), 0, accuracy: 0.001)
        XCTAssertEqual(TimerProgress.fraction(remaining: 30, sessionTotal: 0, isRunning: true), 0, accuracy: 0.001)
    }
}

final class TimerFormattingTests: XCTestCase {
    func testCountdownDisplaySwitchesFromHoursMinutesToMinutesSeconds() {
        XCTAssertEqual(TimeInterval(60 * 60 + 5).countdownDisplayString, "01:00")
        XCTAssertEqual(TimeInterval(2 * 60 * 60 - 0.2).countdownDisplayString, "01:59")
        XCTAssertEqual(TimeInterval(59 * 60 + 59).countdownDisplayString, "59:59")
        XCTAssertEqual(TimeInterval(0.4).countdownDisplayString, "00:01")
        XCTAssertEqual(TimeInterval(0).countdownDisplayString, "00:00")
        XCTAssertEqual(TimeInterval(16 * 60 + 1).countdownDisplayString, "16:01")
        XCTAssertEqual(TimeInterval(60 * 60 + 16 * 60 + 15).countdownDisplayString, "01:16")
    }
}

final class EndTimeCaretResolverTests: XCTestCase {
    func testColonBridgeClickChoosesNearestVisualSide() {
        let positions: [CGFloat] = [9, 27, 39.5, 52, 70]

        let beforeColon = EndTimeCaretResolver.selection(at: 34.5, positions: positions)
        let afterColon = EndTimeCaretResolver.selection(at: 44.5, positions: positions)

        XCTAssertEqual(beforeColon, EndTimeCaretResolver.Selection(position: 2, colonSide: .before))
        XCTAssertEqual(afterColon, EndTimeCaretResolver.Selection(position: 2, colonSide: .after))
    }

    func testAutomaticHourCompletionCanPlaceCaretNearMinuteInput() {
        let positions: [CGFloat] = [9, 27, 39.5, 52, 70]

        let beforeX = EndTimeCaretResolver.caretX(for: 2, colonSide: .before, positions: positions)
        let afterX = EndTimeCaretResolver.caretX(for: 2, colonSide: .after, positions: positions)

        XCTAssertLessThan(beforeX, positions[2])
        XCTAssertGreaterThan(afterX, positions[2])
    }
}

final class EndTimeResolverTests: XCTestCase {
    func testEarlierClockTimeResolvesToTomorrow() throws {
        let calendar = testCalendar
        let now = try makeDate(year: 2026, month: 4, day: 26, hour: 22, minute: 10, second: 0, calendar: calendar)

        let resolved = try XCTUnwrap(EndTimeResolver.resolve("02:20", now: now, calendar: calendar))

        XCTAssertEqual(resolved.timeIntervalSince(now), 4 * 60 * 60 + 10 * 60, accuracy: 0.001)
    }

    func testMidnightResolvesToNearestUpcomingMidnight() throws {
        let calendar = testCalendar
        let now = try makeDate(year: 2026, month: 4, day: 26, hour: 22, minute: 10, second: 0, calendar: calendar)

        let zero = try XCTUnwrap(EndTimeResolver.resolve("00:00", now: now, calendar: calendar))
        let twentyFour = try XCTUnwrap(EndTimeResolver.resolve("24:00", now: now, calendar: calendar))

        XCTAssertEqual(zero.timeIntervalSince(now), 1 * 60 * 60 + 50 * 60, accuracy: 0.001)
        XCTAssertEqual(twentyFour.timeIntervalSince(now), 1 * 60 * 60 + 50 * 60, accuracy: 0.001)
    }

    func testOnlyTwentyFourHundredIsAccepted() throws {
        let calendar = testCalendar
        let now = try makeDate(year: 2026, month: 4, day: 26, hour: 22, minute: 10, second: 0, calendar: calendar)

        XCTAssertNotNil(EndTimeResolver.resolve("24:00", now: now, calendar: calendar))
        XCTAssertNil(EndTimeResolver.resolve("24:01", now: now, calendar: calendar))
    }

    func testCurrentMinuteIsInvalidButLaterMinuteTodayIsValid() throws {
        let calendar = testCalendar
        let now = try makeDate(year: 2026, month: 4, day: 26, hour: 22, minute: 10, second: 35, calendar: calendar)

        let current = try XCTUnwrap(EndTimeResolver.resolve("22:10", now: now, calendar: calendar))
        let later = try XCTUnwrap(EndTimeResolver.resolve("22:11", now: now, calendar: calendar))

        XCTAssertTrue(EndTimeResolver.isCurrentMinute(current, now: now, calendar: calendar))
        XCTAssertFalse(EndTimeResolver.isCurrentMinute(later, now: now, calendar: calendar))
        XCTAssertGreaterThan(later, now)
    }

    private var testCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )))
    }
}
