// NativeScheduler/Sources/NativeScheduler/Features/FloatingPanel/ToggleChevronView.swift
import SwiftUI

struct ToggleChevronView: View {
    let isExpanded: Bool
    let onToggle: () -> Void
    let onRightClick: () -> Void
    /// Compact remaining-time label shown when the timer is running.
    /// e.g. "25m", "1h3m", "<1m". nil = timer idle (label hidden).
    var timerDisplay: String? = nil

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.nsChevron)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(.spring(duration: 0.25), value: isExpanded)

                if let display = timerDisplay {
                    Text(display)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.nsChevron.opacity(0.65))
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: timerDisplay)
                }
            }
            // Fill the full panel so the hit target is generous (macOS HIG ≥ 22pt min)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Panel is 120 × 28pt — matches spec "Width: ~120pt, height: status-bar height"
        .frame(width: 120, height: 28)
        .background(Color.black.opacity(0.01))
        .accessibilityLabel(isExpanded ? "Close panel" : "Open panel")
        .contextMenu {
            Button("Quit NativeScheduler") {
                onRightClick()
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
