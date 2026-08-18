import AppKit

/// Borderless panel that can still participate in the key window chain.
/// SwiftUI inputs inside the expanded panel need this to accept focus.
final class FocusablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
