// NativeScheduler/Sources/NativeScheduler/App/NativeSchedulerApp.swift
import SwiftUI

@main
struct NativeSchedulerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No WindowGroup — all UI is managed by FloatingPanelController via NSPanel
        Settings { EmptyView() }
    }
}
