import Combine
import SwiftUI

@MainActor
final class NotchWindowState: ObservableObject {
    @Published var isExpanded: Bool = false
    private var isExternalInteractionLocked = false
    private var isShellMenuInteractionActive = false
    private var interactionLockCancellable: AnyCancellable?

    init() {
        interactionLockCancellable = NotificationCenter.default
            .publisher(for: .nativeSchedulerInteractionLockChanged)
            .compactMap { $0.object as? Bool }
            .sink { [weak self] isLocked in
                MainActor.assumeIsolated {
                    self?.isExternalInteractionLocked = isLocked
                }
            }
    }

    func beginShellMenuInteraction() {
        isShellMenuInteractionActive = true
    }

    func endShellMenuInteraction() {
        isShellMenuInteractionActive = false
    }

    func collapseForPointerExit() {
        guard !isExternalInteractionLocked, !isShellMenuInteractionActive else { return }
        isExpanded = false
    }
}
