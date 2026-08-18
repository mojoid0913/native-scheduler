// NativeScheduler/Sources/NativeScheduler/App/AppDelegate.swift
import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let panelController: FloatingPanelController

    override convenience init() {
        self.init(panelController: FloatingPanelController())
    }

    init(panelController: FloatingPanelController) {
        self.panelController = panelController
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock and Cmd+Tab (Info.plist also sets LSUIElement)
        NSApp.setActivationPolicy(.accessory)

        // Register launch-at-login if first run. Smoke runs should not mutate
        // user login-item state.
        let alreadyRegistered = UserDefaults.standard.bool(forKey: "didRegisterLaunchAtLogin")
        if !isSmokeRun, !alreadyRegistered {
            let outcome = LaunchAtLoginMutation.apply(
                desiredEnabled: true,
                previousEnabled: false
            ) {
                try SMAppService.mainApp.register()
            }
            if outcome.isEnabled {
                UserDefaults.standard.set(true, forKey: "didRegisterLaunchAtLogin")
            } else if let errorMessage = outcome.errorMessage {
                print("[LaunchAtLogin] Initial registration failed; retry remains enabled: \(errorMessage)")
            }
        }

        panelController.setup()
        runSmokeHarnessIfRequested()

        // Flush log at midnight
        scheduleMidnightFlush()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // keep running when all windows are closed
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController.prepareForTermination()
    }

    // MARK: - Midnight log flush

    private func scheduleMidnightFlush() {
        let cal = Calendar.current
        guard let midnight = cal.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else { return }

        let interval = midnight.timeIntervalSinceNow
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + interval) { [weak self] in
            DispatchQueue.main.async {
                if let completedDate = DailyLogRollover.completedDate(
                    before: midnight,
                    calendar: cal
                ) {
                    do {
                        try self?.panelController.flushDailyLog(for: completedDate)
                    } catch {
                        print("[DailyLog] Midnight flush failed: \(error)")
                    }
                }
                self?.scheduleMidnightFlush()
            }
        }
    }

    private var isSmokeRun: Bool {
        ProcessInfo.processInfo.environment["NATIVE_SCHEDULER_SMOKE_AUTOSTART"] == "1"
    }

    private func runSmokeHarnessIfRequested() {
        guard isSmokeRun else { return }

        let env = ProcessInfo.processInfo.environment
        let mode: TimerMode = env["NATIVE_SCHEDULER_SMOKE_MODE"] == TimerMode.duration.rawValue
            ? .duration
            : .endTime
        let duration = TimeInterval(env["NATIVE_SCHEDULER_SMOKE_SECONDS"] ?? "") ?? 2
        let quitAfter = TimeInterval(env["NATIVE_SCHEDULER_SMOKE_QUIT_AFTER"] ?? "") ?? max(4, duration + 2)

        panelController.runSmokeTimer(mode: mode, duration: duration)

        DispatchQueue.main.asyncAfter(deadline: .now() + quitAfter) {
            NSApplication.shared.terminate(nil)
        }
    }
}

enum DailyLogRollover {
    static func completedDate(before midnight: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .second, value: -1, to: midnight)
    }
}
