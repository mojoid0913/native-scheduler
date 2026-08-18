import AppKit
import Combine
import SwiftUI

@MainActor
final class FloatingPanelController {
    private let windowState = NotchWindowState()
    private(set) var timerState: NotchTimerState
    private let timerVM: TimerViewModel
    private let context: NSManagedObjectContext
    private let now: () -> Date
    private let writeDailyLog: ([HeatmapSlotData], Date, [CategoryData]) throws -> Void
    private let fetchCategories: (NSManagedObjectContext) throws -> [CategoryEntity]
    private let fetchSessions: (
        NSManagedObjectContext,
        NSFetchRequest<SessionEntity>
    ) throws -> [SessionEntity]
    private var notchWindow: NotchWindow?
    private var cancellables = Set<AnyCancellable>()
    private var hasPreparedForTermination = false
    private(set) var dailyLogError: String?

    convenience init() {
        self.init(
            timerVM: TimerViewModel(),
            context: CoreDataStack.shared.viewContext,
            now: Date.init,
            writeDailyLog: DailyLogWriter.write
        )
    }

    init(
        timerVM: TimerViewModel,
        timerState: NotchTimerState? = nil,
        context: NSManagedObjectContext,
        now: @escaping () -> Date,
        writeDailyLog: @escaping ([HeatmapSlotData], Date, [CategoryData]) throws -> Void,
        fetchCategories: @escaping (NSManagedObjectContext) throws -> [CategoryEntity] = {
            context in
            let request = NSFetchRequest<CategoryEntity>(entityName: "CategoryEntity")
            request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
            return try context.fetch(request)
        },
        fetchSessions: @escaping (
            NSManagedObjectContext,
            NSFetchRequest<SessionEntity>
        ) throws -> [SessionEntity] = { context, request in
            try context.fetch(request)
        }
    ) {
        self.timerVM = timerVM
        self.timerState = timerState ?? NotchTimerState()
        self.context = context
        self.now = now
        self.writeDailyLog = writeDailyLog
        self.fetchCategories = fetchCategories
        self.fetchSessions = fetchSessions
    }

    func setup() {
        configureTimerMonitoring()
        let mainPanelView = MainPanelView(timerVM: timerVM)

        let window = NotchWindow(
            windowState: windowState,
            timerState: timerState,
            expandedContent: AnyView(mainPanelView),
            onQuit: { NSApplication.shared.terminate(nil) }
        )
        window.updateForCurrentScreen()
        notchWindow = window
    }

    func configureTimerMonitoring() {
        guard cancellables.isEmpty else { return }

        timerVM.onTimerFinished = { [weak self] in
            guard let self else { return }
            publishTimerSnapshot()
            timerState.triggerCompletionEffect()
            notchWindow?.refreshPresentedContent()
        }

        timerState.$completionEffect
            .dropFirst()
            .filter { !$0.isActive }
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.notchWindow?.refreshPresentedContent()
                }
            }
            .store(in: &cancellables)

        publishTimerSnapshot()
        timerVM.engine.$remaining
            .combineLatest(
                timerVM.engine.$isRunning,
                timerVM.engine.$sessionTotal,
                timerVM.engine.$mode
            )
            .combineLatest(timerVM.$selectedCategory)
            .sink { [weak self] timer, category in
                guard let self else { return }
                let (remaining, isRunning, sessionTotal, mode) = timer
                timerState.update(
                    NotchTimerSnapshot(
                        isRunning: isRunning,
                        progress: TimerProgress.fraction(
                            remaining: remaining,
                            sessionTotal: sessionTotal,
                            isRunning: isRunning
                        ),
                        categoryColorHex: TimerViewModel.resolvedThemeColorHex(
                            category?.colorHex
                        ),
                        mode: mode
                    )
                )
            }
            .store(in: &cancellables)
    }

    private func publishTimerSnapshot() {
        let engine = timerVM.engine
        timerState.update(
            NotchTimerSnapshot(
                isRunning: engine.isRunning,
                progress: TimerProgress.fraction(
                    remaining: engine.remaining,
                    sessionTotal: engine.sessionTotal,
                    isRunning: engine.isRunning
                ),
                categoryColorHex: timerVM.themeColorHex,
                mode: engine.mode
            )
        )
    }

    func runSmokeTimer(mode: TimerMode, duration: TimeInterval) {
        timerVM.configureSmokeTimer(mode: mode, duration: duration)
        timerVM.start()
    }

    func prepareForTermination() {
        guard !hasPreparedForTermination else { return }
        hasPreparedForTermination = true
        timerVM.stop()
        if timerVM.canRetryFinalization {
            timerVM.retryFinalization()
        }
        do {
            try flushDailyLog()
            dailyLogError = nil
        } catch {
            dailyLogError = error.localizedDescription
            print("[DailyLog] Termination flush failed: \(error)")
        }
    }

    func flushDailyLog(for date: Date? = nil) throws {
        let logDate = date ?? now()
        let cats = try fetchCategories(context)
        let catMap = Dictionary(uniqueKeysWithValues: cats.enumerated().map { (i, cat) in
            (cat.objectID, UInt8(i + 1))
        })

        var slotsData: [HeatmapSlotData] = []
        for slot in HeatmapSlot.all {
            let (slotStart, slotEnd) = slot.dateRange(on: logDate, calendar: .current)
            let request = NSFetchRequest<SessionEntity>(entityName: "SessionEntity")
            request.predicate = NSPredicate(
                format: "startTime < %@ AND (endTime == nil OR endTime > %@)",
                slotEnd as NSDate,
                slotStart as NSDate
            )
            let sessions = try fetchSessions(context, request)
            guard !sessions.isEmpty else { continue }

            var tally: [(objectID: NSManagedObjectID?, mins: Double)] = []
            for session in sessions {
                let start = max(session.startTime, slotStart)
                let end = min(session.endTime ?? session.startTime, slotEnd)
                let mins = end.timeIntervalSince(start) / 60
                if mins > 0 {
                    tally.append((session.category?.objectID, mins))
                }
            }

            let grouped = Dictionary(grouping: tally, by: { $0.objectID })
            if let best = grouped.max(by: {
                $0.value.reduce(0, { $0 + $1.mins }) < $1.value.reduce(0, { $0 + $1.mins })
            }) {
                let catIdx = best.key.flatMap { catMap[$0] } ?? 0
                let domMins = UInt8(min(HeatmapSlot.minutesPerSlot, Int(best.value.reduce(0) { $0 + $1.mins })))
                slotsData.append(HeatmapSlotData(index: slot.index, categoryIndex: catIdx, dominantMinutes: domMins))
            }
        }

        let catData = cats.compactMap { cat -> CategoryData? in
            guard let idx = catMap[cat.objectID] else { return nil }
            return CategoryData(index: idx, colorHex: String(cat.colorHex.dropFirst()), name: cat.name)
        }

        try writeDailyLog(slotsData, logDate, catData)
    }
}
