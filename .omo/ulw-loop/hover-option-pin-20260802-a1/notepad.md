# NativeScheduler option-pin ULW notepad

- Session: `hover-option-pin-20260802-a1`
- Goal: keep the expanded notch open while a category/settings option surface is active; restore normal pointer-exit collapse after dismissal/selection.
- Design contract: preserve existing dimensions, palette, motion, accessibility labels; this is interaction-state only.
- Initial evidence: `TimerView` posts `.nativeSchedulerInteractionLockChanged` for the category popover (`TimerView.swift:268-278`), but `NotchWindow` has no observer. Both `PassthroughHostingView.mouseExited` (`NotchWindow.swift:70-74`) and the global monitor (`NotchWindow.swift:193-200`) collapse unconditionally.
- Open hypotheses: H1 missing shared interaction-pin is root cause; H2 SwiftUI popover is a separate window outside notch frame; H3 mouse-exit/global monitor races the presentation state; H4 running bundle may be stale.
- No production edits yet.
- Live RED: category popover is separate owner window 998 at y=327...639 while parent window 166 ends at y=404. Moving into the popover makes it disappear and collapses the parent before selection. Captures: current attempt `manualQa/red-popover-open.png`, `red-collapsed-before-selection.png`.
- Confirmed root: emitted interaction-lock state is unconsumed; both native `mouseExited` and outside-frame monitor collapse directly.
- TDD toggle: PIN unlocked exit passed; lock-aware test RED failed at `XCTAssertTrue`; shared-state GREEN passed targeted and full 35/35. Settings now locks before presentation and releases on disappear.
- Fresh Xcode bundle build/provenance is in progress; old PID 90771 is now stale relative to source.
- Xcode strict-concurrency RED: manual `NSObjectProtocol` observer/deinit failed (`NotchWindowState.swift:16,27`). Retrying with existing Combine subscription pattern; no unsafe annotation or leaked observer.
- Combine `.receive(on:)` compiled but introduced a real queued-lock race; regression test caught it. Final retry uses synchronous Bool sink under the main-actor invariant, not a test wait.
- Final native QA PASS on PID 60540 exact OptionPin bundle: popover held outside parent 1.2s; Resting selection read back; selection/dismiss releases collapse; Settings sheet remains usable and releases on close; ordinary hover unchanged. Initial QA S3/S6 fail labels were superseded by longer-wait/read-back root evidence.
- Final reviews: visual A PASS, visual B PASS, code review CLEAN/APPROVE, independent QA PASS, aggregate gate APPROVE with C001/C002/C003 = 3/3 PASS. Gate artifacts: current attempt `G001-omo-ulw-loop-gate-review.md` and `quality-gate.json`.
- Cleanup: no temp helper remains; invalid/leaky screenshots and debug journal moved recoverably to task-specific Trash folders; correct PID 60540 intentionally remains running collapsed for user inspection.
