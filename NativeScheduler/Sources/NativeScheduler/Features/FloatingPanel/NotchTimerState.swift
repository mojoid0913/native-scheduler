import Foundation
import os
import SwiftUI

enum NotchTimerActivity: Equatable {
    case idle
    case determinateCountdown(progress: Double)
    case activeCountUp
}

struct NotchTimerSnapshot: Equatable {
    var activity: NotchTimerActivity = .idle
    var categoryColorHex = Color.resolvedCategoryHex(nil)

    init(
        activity: NotchTimerActivity = .idle,
        categoryColorHex: String = Color.resolvedCategoryHex(nil)
    ) {
        self.activity = activity
        self.categoryColorHex = categoryColorHex
    }

    init(
        isRunning: Bool,
        progress: Double,
        categoryColorHex: String,
        mode: TimerMode = .duration
    ) {
        if !isRunning {
            activity = .idle
        } else if mode == .countUp {
            activity = .activeCountUp
        } else {
            activity = .determinateCountdown(progress: max(0, min(progress, 1)))
        }
        self.categoryColorHex = categoryColorHex
    }

    var isRunning: Bool {
        activity != .idle
    }

    var progress: Double {
        guard case let .determinateCountdown(progress) = activity else { return 0 }
        return progress
    }

    var accessibilityStatus: String {
        switch activity {
        case .idle:
            return "Idle"
        case .determinateCountdown:
            return "Countdown running"
        case .activeCountUp:
            return "Count Up running"
        }
    }
}

enum TimerProgress {
    static func fraction(remaining: TimeInterval, sessionTotal: TimeInterval, isRunning: Bool) -> Double {
        guard isRunning, sessionTotal > 0 else { return 0 }
        return max(0, min(1, 1 - (remaining / sessionTotal)))
    }
}

struct NotchCompletionEffect: Equatable {
    let generation: UInt64
    let opacity: Double?
    let startedAt: Date?

    var isActive: Bool { opacity != nil }

    func renderedOpacity(at date: Date, reduceMotion: Bool) -> Double {
        guard isActive, let startedAt else { return 0 }
        guard !reduceMotion else { return 1 }

        let elapsed = max(0, date.timeIntervalSince(startedAt))
        guard elapsed < 3 else { return 0 }
        let endpoints = [1.0, 0.25, 1.0, 0.25, 1.0, 0.25, 0.0]
        let segment = min(5, Int(elapsed / 0.5))
        let linearProgress = (elapsed - (Double(segment) * 0.5)) / 0.5
        let easedProgress = (1 - cos(.pi * linearProgress)) / 2
        return endpoints[segment]
            + ((endpoints[segment + 1] - endpoints[segment]) * easedProgress)
    }

    static let inactive = NotchCompletionEffect(
        generation: 0,
        opacity: nil,
        startedAt: nil
    )
}

protocol NotchScheduledAction: AnyObject, Sendable {
    func cancel()
}

private final class TaskNotchScheduledAction: NotchScheduledAction {
    private let task: OSAllocatedUnfairLock<Task<Void, Never>?>

    init(task: Task<Void, Never>) {
        self.task = OSAllocatedUnfairLock(initialState: task)
    }

    func cancel() {
        let task = task.withLock { task in
            defer { task = nil }
            return task
        }
        task?.cancel()
    }

    deinit {
        cancel()
    }
}

struct NotchCountUpBreathing {
    struct Presentation: Equatable {
        let scale: Double
        let opacity: Double
    }

    static let halfCycle: TimeInterval = 0.8
    static let fullCycle: TimeInterval = 1.6

    static func presentation(elapsed: TimeInterval, reduceMotion: Bool) -> Presentation {
        guard !reduceMotion else { return Presentation(scale: 1, opacity: 1) }

        let cyclePosition = max(0, elapsed).truncatingRemainder(dividingBy: fullCycle)
        if cyclePosition == 0 {
            return Presentation(scale: 0.94, opacity: 0.72)
        }
        if cyclePosition == halfCycle {
            return Presentation(scale: 1.04, opacity: 1)
        }

        let linearProgress: Double
        if cyclePosition < halfCycle {
            linearProgress = cyclePosition / halfCycle
        } else {
            linearProgress = 1 - ((cyclePosition - halfCycle) / halfCycle)
        }
        let easedProgress = (1 - cos(.pi * linearProgress)) / 2
        return Presentation(
            scale: 0.94 + (0.10 * easedProgress),
            opacity: 0.72 + (0.28 * easedProgress)
        )
    }
}

@MainActor
final class NotchTimerState: ObservableObject {
    typealias CompletionPhaseScheduler = @MainActor @Sendable (
        _ delay: TimeInterval,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> NotchScheduledAction

    @Published private(set) var snapshot = NotchTimerSnapshot()
    @Published private(set) var completionEffect = NotchCompletionEffect.inactive

    private let scheduleCompletionPhase: CompletionPhaseScheduler
    private let now: () -> Date
    private var completionActions: [NotchScheduledAction] = []
    private var nextCompletionGeneration: UInt64 = 0
    private(set) var countUpBreathingStartedAt: Date?

    convenience init() {
        self.init(
            scheduleCompletionPhase: { delay, action in
                NotchTimerState.scheduleOnMainQueue(after: delay, action: action)
            },
            now: Date.init
        )
    }

    init(
        scheduleCompletionPhase: @escaping CompletionPhaseScheduler,
        now: @escaping () -> Date = Date.init
    ) {
        self.scheduleCompletionPhase = scheduleCompletionPhase
        self.now = now
    }

    func update(_ snapshot: NotchTimerSnapshot) {
        let wasCountUpActive = self.snapshot.activity == .activeCountUp
        let isCountUpActive = snapshot.activity == .activeCountUp
        self.snapshot = snapshot

        if isCountUpActive && !wasCountUpActive {
            countUpBreathingStartedAt = now()
        } else if !isCountUpActive {
            countUpBreathingStartedAt = nil
        }
    }

    func countUpBreathingElapsed(at date: Date) -> TimeInterval {
        guard let countUpBreathingStartedAt else { return 0 }
        return max(0, date.timeIntervalSince(countUpBreathingStartedAt))
    }

    func triggerCompletionEffect() {
        completionActions.forEach { $0.cancel() }
        completionActions.removeAll()

        nextCompletionGeneration &+= 1
        let generation = nextCompletionGeneration
        let startedAt = now()
        completionEffect = NotchCompletionEffect(
            generation: generation,
            opacity: 1,
            startedAt: startedAt
        )

        let phases: [(delay: TimeInterval, opacity: Double?)] = [
            (0.5, 0.25),
            (1.0, 1),
            (1.5, 0.25),
            (2.0, 1),
            (2.5, 0.25),
            (3.0, nil)
        ]
        completionActions = phases.map { phase in
            scheduleCompletionPhase(phase.delay) { [weak self] in
                guard let self, self.completionEffect.generation == generation else { return }
                self.completionEffect = NotchCompletionEffect(
                    generation: generation,
                    opacity: phase.opacity,
                    startedAt: startedAt
                )
                if phase.opacity == nil {
                    self.completionActions.forEach { $0.cancel() }
                    self.completionActions.removeAll()
                }
            }
        }
    }

    deinit {
        completionActions.forEach { $0.cancel() }
    }

    private static func scheduleOnMainQueue(
        after delay: TimeInterval,
        action: @escaping @MainActor @Sendable () -> Void
    ) -> NotchScheduledAction {
        let task = Task { @MainActor in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(max(0, delay) * 1_000_000_000)
                )
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            action()
        }
        return TaskNotchScheduledAction(task: task)
    }
}
