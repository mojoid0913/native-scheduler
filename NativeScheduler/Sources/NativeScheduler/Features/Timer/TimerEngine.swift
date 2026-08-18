// NativeScheduler/Sources/NativeScheduler/Features/Timer/TimerEngine.swift
import AppKit
import Foundation
import Combine

@MainActor
protocol TimerEngineTicker: AnyObject {
    func cancel()
}

@MainActor
private final class DispatchTimerEngineTicker: TimerEngineTicker {
    private var source: DispatchSourceTimer?

    init(
        interval: DispatchTimeInterval,
        leeway: DispatchTimeInterval,
        action: @escaping @MainActor () -> Void
    ) {
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now(), repeating: interval, leeway: leeway)
        source.setEventHandler {
            MainActor.assumeIsolated {
                action()
            }
        }
        self.source = source
        source.resume()
    }

    func cancel() {
        source?.cancel()
        source = nil
    }

    deinit { source?.cancel() }
}

// MARK: - TimerEngine

@MainActor
final class TimerEngine: ObservableObject {
    // Published state
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var isFinished: Bool = false
    @Published private(set) var sessionTotal: TimeInterval = 0

    // Configuration
    @Published var mode: TimerMode = .duration
    @Published var durationSeconds: TimeInterval = 25 * 60  // default 25 min
    @Published var targetEndTime: Date = Date().addingTimeInterval(25 * 60)

    private var ticker: TimerEngineTicker?
    private let wallClock: () -> Date
    private let monotonicClock: () -> TimeInterval
    private let tickerFactory: (@escaping @MainActor () -> Void) -> TimerEngineTicker
    private let soundPlayer: @MainActor () -> Void
    private var countdownDeadline: Date?
    private var countUpBaseElapsed: TimeInterval = 0
    private var countUpStartedMonotonic: TimeInterval?
    private var tickerGeneration: UInt64 = 0

    // Callbacks
    var onTick: (@MainActor (TimeInterval) -> Void)?
    var onFinish: (@MainActor () -> Void)?
    private(set) var lastCompletionDate: Date?

    init(
        tickInterval: DispatchTimeInterval = .seconds(1),
        leeway: DispatchTimeInterval = .milliseconds(100),
        wallClock: @escaping () -> Date = Date.init,
        monotonicClock: @escaping () -> TimeInterval = {
            TimeInterval(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
        },
        tickerFactory: ((@escaping @MainActor () -> Void) -> TimerEngineTicker)? = nil,
        soundPlayer: @escaping @MainActor () -> Void = TimerEngine.playCompletionSound
    ) {
        self.wallClock = wallClock
        self.monotonicClock = monotonicClock
        self.tickerFactory = tickerFactory ?? { action in
            DispatchTimerEngineTicker(interval: tickInterval, leeway: leeway, action: action)
        }
        self.soundPlayer = soundPlayer
    }

    // MARK: - Controls

    func start(now: Date? = nil) {
        guard !isRunning else { return }
        let timestamp = now ?? wallClock()
        isFinished = false
        let wasPaused = isPaused
        isPaused = false

        if mode == .countUp {
            startCountUp(resuming: wasPaused)
            return
        }

        if mode == .endTime && !wasPaused {
            prepareEndTimeCountdown(now: timestamp)
        }
        let total = max(0, remaining > 0 ? remaining : durationSeconds)

        guard total > 0 else {
            finish()
            return
        }

        countdownDeadline = timestamp.addingTimeInterval(total)
        remaining = total
        sessionTotal = total
        isRunning = true
        installTicker { [weak self] in
            self?.updateCountdown()
        }
    }

    func pause(now: Date? = nil) {
        guard isRunning else { return }
        if mode == .countUp {
            updateCountUpElapsed(at: monotonicClock())
        } else if let countdownDeadline {
            remaining = max(0, countdownDeadline.timeIntervalSince(now ?? wallClock()))
        }

        cancelTicker()
        countdownDeadline = nil
        countUpStartedMonotonic = nil
        isRunning = false
        isPaused = mode == .countUp || remaining > 0

        if mode != .countUp, remaining <= 0 {
            finish()
        }
    }

    func stop() {
        cancelTicker()
        countdownDeadline = nil
        countUpStartedMonotonic = nil
        countUpBaseElapsed = 0
        isRunning = false
        isPaused = false
        isFinished = false
        sessionTotal = 0
        remaining = mode == .countUp ? 0 : durationSeconds
    }

    func reset() {
        stop()
    }

    func prepareEndTimeCountdown(now: Date? = nil) {
        guard !isRunning, !isPaused else { return }
        let total = endTimeCountdownSeconds(now: now ?? wallClock())
        durationSeconds = total
        remaining = total
        sessionTotal = 0
    }

    // MARK: - Private

    private func startCountUp(resuming: Bool) {
        countUpBaseElapsed = resuming ? remaining : 0
        remaining = countUpBaseElapsed
        sessionTotal = 0
        countUpStartedMonotonic = monotonicClock()
        isRunning = true
        onTick?(remaining)
        installTicker { [weak self] in
            guard let self else { return }
            self.updateCountUpElapsed(at: self.monotonicClock())
            self.onTick?(self.remaining)
        }
    }

    private func updateCountdown() {
        guard let countdownDeadline else { return }
        let left = max(0, countdownDeadline.timeIntervalSince(wallClock()))
        remaining = left
        onTick?(left)
        if left <= 0 {
            finish(at: countdownDeadline)
        }
    }

    private func updateCountUpElapsed(at monotonicNow: TimeInterval) {
        guard let countUpStartedMonotonic else { return }
        remaining = countUpBaseElapsed + monotonicNow - countUpStartedMonotonic
    }

    private func installTicker(action: @escaping @MainActor () -> Void) {
        tickerGeneration &+= 1
        let generation = tickerGeneration
        ticker = tickerFactory { [weak self] in
            guard let self, self.isRunning, self.tickerGeneration == generation else { return }
            action()
        }
    }

    private func cancelTicker() {
        tickerGeneration &+= 1
        ticker?.cancel()
        ticker = nil
    }

    func finish() {
        finish(at: nil)
    }

    func finish(at completionDate: Date?) {
        guard !isFinished else { return }
        cancelTicker()
        countdownDeadline = nil
        countUpStartedMonotonic = nil
        isRunning = false
        isPaused = false
        isFinished = true
        remaining = 0
        sessionTotal = 0
        soundPlayer()
        lastCompletionDate = completionDate
        onFinish?()
    }

    private func endTimeCountdownSeconds(now: Date) -> TimeInterval {
        max(0, targetEndTime.timeIntervalSince(now))
    }

    private static func playCompletionSound() {
        if let ping = NSSound(named: .init("Ping")) {
            ping.play()
        } else {
            NSSound.beep()
        }
    }
}

// MARK: - Formatting

extension TimeInterval {
    var countdownDisplayString: String {
        let remaining = max(0, self)
        if remaining >= 3600 {
            let total = Int(remaining)
            let h = total / 3600
            let m = (total % 3600) / 60
            return String(format: "%02d:%02d", h, m)
        }

        let total = remaining > 0 ? max(1, Int(remaining)) : 0
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// Compact label for the always-visible chevron strip.
    /// Examples: "25m", "1h3m", "<1m". Returns nil when ≤ 0.
    var chevronString: String? {
        let total = Int(max(0, self))
        guard total > 0 else { return nil }
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return m > 0 ? "\(h)h\(m)m" : "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }
}
