import Foundation
import CoreData
import Combine
import SwiftUI

@MainActor
final class TimerViewModel: ObservableObject {
    @Published var engine: TimerEngine
    @Published var selectedCategory: CategoryEntity?
    @Published var categories: [CategoryEntity] = []
    @Published private(set) var activeSessionID: UUID?
    @Published private(set) var recordingError: String?

    private let context: NSManagedObjectContext
    private let now: () -> Date
    private let saveContext: (NSManagedObjectContext) throws -> Void
    private var currentSession: SessionEntity?
    private var pendingFinalization: (session: SessionEntity, end: Date)?
    private var cancellables = Set<AnyCancellable>()
    private var nextCheckpointElapsed: TimeInterval = 10
    private var allowsSubMinuteDuration = false

    var onTimerFinished: (() -> Void)?
    var canRetryFinalization: Bool { pendingFinalization != nil }

    nonisolated static func resolvedThemeColorHex(_ categoryColorHex: String?) -> String {
        Color.resolvedCategoryHex(categoryColorHex)
    }

    var themeColorHex: String {
        Self.resolvedThemeColorHex(selectedCategory?.colorHex)
    }

    convenience init() {
        let clock: () -> Date = Date.init
        self.init(
            engine: TimerEngine(wallClock: clock),
            context: CoreDataStack.shared.viewContext,
            now: clock,
            save: { context in
                if context.hasChanges { try context.save() }
            }
        )
    }

    init(
        engine: TimerEngine,
        context: NSManagedObjectContext,
        now: @escaping () -> Date,
        save: @escaping (NSManagedObjectContext) throws -> Void
    ) {
        self.engine = engine
        self.context = context
        self.now = now
        self.saveContext = save
        refreshSettings()
        forwardEngineChanges()
        setupEngineCallbacks()
    }

    private func applyDefaultTimerSettings() {
        let defaults = UserDefaults.standard
        let storedMinutes = defaults.integer(forKey: "defaultTimerDuration")
        if storedMinutes > 0 {
            engine.durationSeconds = TimeInterval(min(60, max(5, storedMinutes)) * 60)
        }
        if let rawMode = defaults.string(forKey: "defaultTimerMode"),
           let mode = TimerMode(rawValue: rawMode) {
            engine.mode = mode
        }
        engine.reset()
    }

    func refreshSettings() {
        loadCategories()
        guard !engine.isRunning, !engine.isPaused else { return }
        applyDefaultTimerSettings()
    }

    func loadCategories() {
        categories = CategoryEntity.fetchAll(in: context)
        if let selectedCategory,
           !categories.contains(where: { $0.objectID == selectedCategory.objectID }) {
            self.selectedCategory = nil
        }
    }

    @discardableResult
    func addCategory(name: String, colorHex: String) -> CategoryEntity? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, categories.count < 12 else { return nil }

        let category = CategoryEntity.create(
            name: trimmedName,
            colorHex: colorHex,
            sortOrder: Int32(categories.count),
            in: context
        )
        do {
            try saveContext(context)
            loadCategories()
            return category
        } catch {
            context.delete(category)
            recordingError = "Category could not be saved."
            return nil
        }
    }

    func start() {
        guard !engine.isRunning, pendingFinalization == nil else { return }

        if engine.mode == .duration, !allowsSubMinuteDuration {
            let minutes = min(60, max(5, Int(round(engine.durationSeconds / 60))))
            engine.durationSeconds = TimeInterval(minutes * 60)
        }

        let timestamp = now()
        engine.start(now: timestamp)
        guard engine.isRunning else { return }

        let session = SessionEntity.create(
            startTime: timestamp,
            mode: engine.mode,
            category: selectedCategory,
            in: context
        )
        session.endTime = timestamp
        do {
            try saveContext(context)
            currentSession = session
            activeSessionID = session.id
            nextCheckpointElapsed = 10
            recordingError = nil
        } catch {
            context.delete(session)
            context.processPendingChanges()
            engine.stop()
            recordingError = "Recording could not be started."
        }
    }

    func pause() {
        let timestamp = now()
        engine.pause(now: timestamp)
        finalizeCurrentSession(at: timestamp)
    }

    func stop() {
        let timestamp = now()
        engine.stop()
        finalizeCurrentSession(at: timestamp)
    }

    func reset() {
        let timestamp = now()
        engine.reset()
        finalizeCurrentSession(at: timestamp)
    }

    func configureSmokeTimer(mode: TimerMode, duration: TimeInterval) {
        let timestamp = now()
        engine.stop()
        finalizeCurrentSession(at: timestamp)
        allowsSubMinuteDuration = true
        engine.mode = mode
        switch mode {
        case .duration:
            engine.durationSeconds = max(0.1, duration)
        case .endTime:
            engine.targetEndTime = timestamp.addingTimeInterval(max(0.1, duration))
        case .countUp:
            break
        }
        engine.reset()
    }

    func changeCategory(to category: CategoryEntity?) {
        guard engine.isRunning, let session = currentSession else {
            selectedCategory = category
            return
        }
        guard category?.objectID != selectedCategory?.objectID else { return }

        let timestamp = now()
        let previousEnd = session.endTime
        let replacement = SessionEntity.create(
            startTime: timestamp,
            mode: engine.mode,
            category: category,
            in: context
        )
        replacement.endTime = timestamp
        session.endTime = timestamp
        do {
            try saveContext(context)
            selectedCategory = category
            currentSession = replacement
            activeSessionID = replacement.id
            nextCheckpointElapsed = 10
            recordingError = nil
        } catch {
            session.endTime = previousEnd
            context.delete(replacement)
            context.processPendingChanges()
            recordingError = "Category change could not be saved."
        }
    }

    func processPersistenceTick() {
        guard engine.isRunning, let session = currentSession, activeSessionID == session.id else { return }
        let timestamp = now()
        let elapsed = timestamp.timeIntervalSince(session.startTime)
        guard elapsed >= nextCheckpointElapsed else { return }

        let previousEnd = session.endTime
        session.endTime = timestamp
        do {
            try saveContext(context)
            recordingError = nil
        } catch {
            session.endTime = previousEnd
            recordingError = "Recording checkpoint could not be saved."
        }
        nextCheckpointElapsed = (floor(elapsed / 10) + 1) * 10
    }

    func retryFinalization() {
        guard let pendingFinalization else { return }
        let previousEnd = pendingFinalization.session.endTime
        pendingFinalization.session.endTime = pendingFinalization.end
        do {
            try saveContext(context)
            self.pendingFinalization = nil
            recordingError = nil
        } catch {
            pendingFinalization.session.endTime = previousEnd
            recordingError = "Recording could not be finalized. Retry."
        }
    }

    private func forwardEngineChanges() {
        engine.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    private func setupEngineCallbacks() {
        engine.onTick = { [weak self] _ in self?.processPersistenceTick() }
        engine.onFinish = { [weak self] in
            guard let self, self.activeSessionID != nil else { return }
            let timestamp = self.engine.lastCompletionDate ?? self.now()
            self.finalizeCurrentSession(at: timestamp)
            self.onTimerFinished?()
        }
    }

    private func finalizeCurrentSession(at timestamp: Date) {
        guard let session = currentSession, activeSessionID == session.id else { return }
        let previousEnd = session.endTime
        currentSession = nil
        activeSessionID = nil
        session.endTime = timestamp
        do {
            try saveContext(context)
            recordingError = nil
        } catch {
            session.endTime = previousEnd
            pendingFinalization = (session, timestamp)
            recordingError = "Recording could not be finalized. Retry."
        }
    }
}
