# Deterministic Native Hover Fix — Attempt 1

## Verdict

The deterministic hover defect is fixed on the real AppKit surface: exact Quartz input at `(960,40)` expands, outside input at `(80,800)` collapses, and one full re-entry/re-exit cycle passes on the same process and owner window.

The brief's exact `1632x768` expanded-image criterion is **not met**. The actual owner-only capture is `1632x808`, matching the repository's prior real owner captures (`.omo/evidence/theme-color-single-source/expanded-progress-region.png` is also `1632x808`). The extra 40 device pixels are the existing 20-point `NotchGeometry.shadowPadding`/SwiftUI shadow in the 816x404 owner window. This attempt did not clip or remove the existing shadow merely to change evidence dimensions.

## Root cause and change

SwiftUI `.onHover` was the only collapsed expansion driver, and the deterministic CGEvent entry behind the hardware notch never reached that driver. `PassthroughHostingView` now installs a precise `.activeAlways` `NSTrackingArea` over the shared `NotchGeometry.hitRect`, preserves the 80 ms dwell and real-pointer recheck, owns enter/exit state changes, and refreshes its tracking rect when the root/expansion state refreshes. SwiftUI hover remains only for visual shadow styling, so there are no competing window-state hover drivers.

Changed production files:

- `NativeScheduler/Sources/NativeScheduler/Features/FloatingPanel/NotchWindow.swift`: native tracking area, 80 ms dwell/recheck, state entry/exit, tracking refresh.
- `NativeScheduler/Sources/NativeScheduler/Features/FloatingPanel/NotchView.swift`: removed SwiftUI window-state hover tasks; retained visual hover animation.
- `NativeScheduler/Tests/NativeSchedulerTests/NotchShellTests.swift`: one regression test verifies the native tracker is precise, `.activeAlways`, and includes local `(408,40)`.

`NotchGeometry.swift` was not changed. Full current-file patch evidence is `source-diff.patch`; the parent repository has no HEAD, so assigned files appear untracked and a conventional base diff/commit is unavailable.

## Criterion evidence

### Existing failing-first RED

- Scenario: real pre-fix owner window, helper hold at Quartz `(960,40)` for 1800 ms, capture after 500 ms.
- Invocation: `PointerHold hold 960 40 1800`; `screencapture -x -l 80632 c001-expanded.png`.
- Binary observable: pre-fix capture stayed `440x76`; three repeat enters also stayed collapsed.
- Artifacts: `../worker-initial/hover-worker-initial-manual-qa.md`, `../worker-initial/action.log`, `../worker-initial/c001-expanded.png`.

### Native tracking seam

- Scenario: construct the real `PassthroughHostingView`, install tracking areas, inspect the native area.
- Invocation: `swift test --package-path NativeScheduler --filter NotchShellTests`.
- Binary observable: 11 tests, 0 failures; `testHostingViewTracksCollapsedNativeHoverRegion` passed; existing below-notch geometry test remained green.
- Artifact: `targeted-test.log`.

### C001 exact center hover

- Scenario: fresh debug binary PID `18110`, CG owner window `80659`, Quartz `(960,40)` held 1800 ms, owner capture at 500 ms.
- Invocation: `/tmp/native-scheduler-hover-fix-attempt-1/PointerHold hold 960 40 1800`; `screencapture -x -l 80659 c001-expanded.png`.
- Binary observable: capture visibly contains the complete expanded scheduler and is `1632x808`; PID remained alive. This proves expansion but fails the brief's `1632x768` dimension literal.
- Artifacts: `c001-expanded.png`, `c001-helper-live.log`, `window-initial-live.log`, `window-after-c001-live.log`, `action.log`, `signatures.txt`.

### C002 outside exit

- Scenario: same PID/window, Quartz `(80,800)` held 1400 ms, owner capture at 500 ms.
- Invocation: `/tmp/native-scheduler-hover-fix-attempt-1/PointerHold hold 80 800 1400`; `screencapture -x -l 80659 c002-collapsed.png`.
- Binary observable: `440x76`; PID remained alive.
- Artifacts: `c002-collapsed.png`, `c002-helper.log`, `action.log`, `signatures.txt`.

### C003 re-entry viability

- Scenario: same PID/window re-entered at `(960,40)` for 1500 ms, then re-exited at `(80,800)` for 1200 ms; both captured during hold.
- Invocation: `PointerHold hold 960 40 1500`, capture after 500 ms; `PointerHold hold 80 800 1200`, capture after 500 ms.
- Binary observable: re-enter `1632x808`, re-exit `440x76`; PID remained alive. Both images were directly inspected and show the expected expanded/collapsed surfaces.
- Artifacts: `c003-reentered.png`, `c003-recollapsed.png`, `c003-reenter-helper.log`, `c003-reexit-helper.log`, `action.log`, `signatures.txt`.

### Full verification

- Scenario: complete Swift package test suite.
- Invocation: `swift test --package-path NativeScheduler`.
- Binary observable: 33 tests, 0 failures.
- Artifact: `full-test.log`.
- Scenario: debug package build.
- Invocation: `swift build --package-path NativeScheduler`.
- Binary observable: exit 0, `Build complete!`.
- Artifact: `build.log`.
- Scenario: final-marker scan.
- Invocation: `rg -n "print\\(|debugPrint|NSLog|TODO|FIXME"` over the three changed files.
- Binary observable: empty output.
- Artifact: `debug-marker-scan.txt`.

## Build identity and cleanup

- Fresh QA binary SHA-256: `4358124481925bbf403a401098b7ada12a6f7f05628240ee5cb4e41ac81c3609`.
- Only the recorded QA process was interrupted; PIDs `14577`, `16664`, and live QA PID `18110` are absent.
- The final helper logged cursor restoration to `(1722,398)`.
- `/tmp/native-scheduler-hover-fix-attempt-1` is absent.
- Artifacts: `cleanup-before.log`, `cleanup-receipt.txt`, `no-commit-status.txt`.

## Commit status

No commit was made, as required. `/Users/chan/Projects` has no `HEAD`; `no-commit-status.txt` captures the failed `rev-parse` and untracked assigned files.
