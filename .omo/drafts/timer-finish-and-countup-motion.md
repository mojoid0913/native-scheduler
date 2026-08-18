---
slug: timer-finish-and-countup-motion
status: reviewed
intent: clear
review_required: true
plan_path: .omo/plans/timer-finish-and-countup-motion.md
plan_sha256: bed7ee32685a41d15439f30dee7e92920f4d0a7e4f6731fc77c884895145cd6f
review_round_id: 1
review_round_limit: 5
pending-action: execute .omo/plans/timer-finish-and-countup-motion.md through ULW G008
review:
  momus:
    status: approved
    workspace_root: /Users/chan/Projects/native_schedular
    runtime_home: /opt/homebrew/lib/node_modules/omo-ai/plugin
    target: .omo/plans/timer-finish-and-countup-motion.md
    round_id: 1
    plan_sha256: bed7ee32685a41d15439f30dee7e92920f4d0a7e4f6731fc77c884895145cd6f
    launch_id: st_01a0144e
    session: timer-motion-plan-momus
    result: approved
approach: "Keep TimerEngine and persistence untouched; promote completion feedback and timer activity kind into NotchTimerState, render one outer-shell completion border in NotchView for both collapsed and expanded geometry, and replace the meaningless zero-progress Count Up ring with a category-colored breathing stopwatch mark. Specify every timing and Reduce Motion rule in DESIGN.md first, implement test-first with an injected completion-effect sleeper, then verify the real Release surface with deterministic state tests and fresh screen recordings."
---

# Draft: timer-finish-and-countup-motion

## Components (topology ledger)
<!-- Lock the SHAPE before depth. One row per top-level component that can succeed or fail independently. -->
<!-- id | outcome (one line) | status: active|deferred | evidence path -->
| id | outcome | status | evidence path |
|---|---|---|---|
| C1 | Automatic Duration/End Time completion owns one restartable three-second visual-effect lifecycle outside TimerEngine. | active | `NativeScheduler/Sources/NativeScheduler/Features/Timer/TimerEngine.swift:145-201`; `TimerViewModel.swift:249-269`; `FloatingPanelController.swift:72-99` |
| C2 | While collapsed, the completion effect outlines only the camera-attached idle shell. | active | `NativeScheduler/Sources/NativeScheduler/Features/FloatingPanel/NotchView.swift:22-127`; `NotchGeometry.swift:5-64` |
| C3 | While expanded, the same live effect outlines the complete `816x384` outer shell and retargets if expansion changes mid-effect. | active | `NativeScheduler/Sources/NativeScheduler/Features/FloatingPanel/NotchView.swift:62-127`; `NotchGeometry.swift:11-18`; `NotchWindow.swift:161-223` |
| C4 | Running Count Up shows a meaningful category-colored breathing stopwatch mark in the collapsed shell instead of an empty determinate ring. | active | `NotchTimerState.swift:4-24`; `FloatingPanelController.swift:82-99`; `TimerView.swift:495-507`; `ManagedObjects.swift:145-159` |
| C5 | Reduced Motion, deterministic timing tests, hosted geometry/AX checks, and fresh real-app video prove behavior without timing luck or normal-profile mutation. | active | `DESIGN.md:163-176`; `NotchShellTests.swift:1160-1250`; `TimerEngineTests.swift:9-212` |

## Open assumptions (announced defaults)
<!-- Record any default you adopt instead of asking, so the user can veto it at the gate. -->
<!-- assumption | adopted default | rationale | reversible? -->
| assumption | adopted default | rationale | reversible? |
|---|---|---|---|
| “한 3초간” | Exactly `3.0s`: three one-second opacity pulses, then no residual border. | Matches the requested duration while remaining below a harsh strobe cadence. | yes |
| “빨간색 테두리” | Named completion-alert token mapped to the existing semantic error red; `2pt` inner shell stroke, opacity-only animation. | Preserves the design system and avoids raw ad-hoc color or scale bounce. | yes |
| “카메라 위” | The real collapsed `NotchShape` (`idleShellWidth x notchHeight+1`), not the invisible `816x404` host window and not a Timer card. | This is the only rendered camera-attached surface before expansion. | yes |
| “확장됐을 때 전체 테두리” | The outer `NotchShape` at `816x384`, not internal Tasks/Stream/Timer cards. | One source of truth naturally follows collapse/expand geometry. | yes |
| Expand/collapse during the three seconds | Preserve the original deadline and smoothly retarget the same border; do not restart the clock. | The alert is one event while shell geometry is presentation state. | yes |
| Duplicate completion while active | Cancel the prior sequence and restart a fresh three seconds using a generation token. | Deterministic under smoke/replay paths. | yes |
| Count Up “logo” | Reuse the existing `stopwatch` SF Symbol already assigned to `TimerMode.countUp`; no product-logo asset exists in the repository. | Maintains mode vocabulary and avoids inventing a brand asset. | yes |
| Count Up active motion | Category-colored stopwatch breathes `scale 0.94↔1.04` and `opacity 0.72↔1.0` on a `1.6s` ease-in-out loop; no rotation or fake progress. | Adapts Impeccable AnimatedBadge loading feedback without implying a known completion percentage. | yes |
| Paused/idle Count Up | No looping motion; preserve existing collapsed-shell idle behavior. | Paused time is not actively being measured. | yes |
| Reduce Motion | Completion stays as one static red border for three seconds; Count Up stays as one static, fully visible stopwatch mark. | `DESIGN.md` requires pulses/springs to stop while static state remains legible. | yes |
| Test strategy | TDD for state and rendering contracts, followed by agent-driven Release visual QA; no fixed sleeps in tests. | The change is behavioral and timing-sensitive. | no |
| Budget / dependency / packaging | No paid service, npm install, new Swift dependency, persisted schema, target change, or packaging change. | Existing SwiftUI/AppKit/macOS 14 APIs suffice; Impeccable is guidance only. | yes |
| Audience / scale | Current macOS notch user, one local floating window, current accessibility contract. | Repository and brief define the operating surface. | yes |

## Findings (cited - path:lines)
- `TimerEngine.finish(at:)` already guarantees one finish callback, cancels the ticker, records the configured deadline, and never auto-finishes Count Up (`TimerEngine.swift:145-201`). Timer and persistence semantics must stay unchanged.
- `TimerViewModel` finalizes the active session before forwarding `onTimerFinished`, and `FloatingPanelController` converts that callback into `NotchTimerState.triggerCompletionPulse()` (`TimerViewModel.swift:249-269`; `FloatingPanelController.swift:72-99`).
- The existing completion animation is a `1.06` whole-shell spring scale that resets after `0.28s`, is local to `NotchView`, and does not honor Reduce Motion (`NotchView.swift:108-127`). Replace it rather than layering another effect.
- Collapsed and expanded shells share one `growingPanel` clipped by one `NotchShape`. Its frame is the camera-attached idle shell before expansion and `816x384` after expansion (`NotchView.swift:22-107`; `NotchGeometry.swift:11-64`). One outer overlay serves both geometries.
- `NotchWindow` replaces the SwiftUI root when expansion changes (`NotchWindow.swift:161-223`), so the three-second phase cannot live only in transient `NotchView @State`; it belongs in retained `NotchTimerState`.
- `NotchTimerSnapshot` carries only `isRunning`, determinate `progress`, and category color. `TimerProgress.fraction` returns zero whenever `sessionTotal == 0`, always true for Count Up (`NotchTimerState.swift:4-15`; `TimerEngine.swift:122-138`).
- The collapsed shell still allocates the 44pt indicator area while running, but Count Up renders a zero-trim ring. The snapshot needs explicit activity kind so `NotchView` selects determinate ring versus Count Up mark (`NotchView.swift:22-34,78-91,131-151`; `NotchGeometry.swift:5-7,50-64`).
- The project already maps Count Up to SF Symbol `stopwatch` in `TimerView`; no PNG/PDF/asset-catalog logo files exist. Reusing it is the least speculative interpretation of “logo” (`TimerView.swift:495-507`).
- Impeccable `/animate` requires purposeful state feedback, no decorative bounce/elastic motion, short eased opacity/transform changes, and Reduced Motion fallback. AnimatedBadge uses a `1.6s` scale/opacity pulse; Dynamic Island keeps shell state outside transient content; Loader replaces transforms with static/opacity state under Reduce Motion.
- The installed frontend interaction contract independently requires state-meaningful motion, interruptibility, easings for opacity/color, and fresh motion recordings (`frontend/references/design/interaction-skill.md`).
- The repository has no Git `HEAD`; its parent sees this project as untracked. Executors must not use Git history as a baseline, revert unrelated files, or create commits without authorization.
- Architect advisory failed before analysis because the configured Anthropic account has insufficient credit. Direct tracing, the explore lane, official Impeccable sources, and the active Ultrabrain detail lane cover the decision surface.
- Ultrabrain independently confirmed that animation anchors must live outside view-local state, expiry/cancellation must be generation-safe, shell geometry must remain fixed, the outer shell must never scale, and tests need manual clocks/schedulers. Those recommendations are adopted.
- Ultrabrain’s `0.72s` lifetime, Timer-card overlay, 28% orbit, persistent paused rail, and wake-reconciliation expansion are rejected: the first two directly contradict the requested three-second outer border, the orbit moves an arc rather than the requested logo, and the latter items expand scope beyond active measurement feedback.

## Decisions (with rationale)
- Keep completion ownership after persistence finalization: `TimerViewModel` stays authoritative, `FloatingPanelController` triggers visual state, and `NotchTimerState` owns its cancellable three-second lifecycle.
- Replace `completionPulse: Int` plus `NotchView.pulseScale` with published completion-effect generation, active state, and phase. Inject the sleeper/scheduler into `NotchTimerState` so tests manually release each 500ms phase without wall-clock waiting.
- Model six 500ms phase advances: immediate bright border, alternating dim/bright opacity, and inactive at the sixth advance (`3.0s`). Use a generation guard so cancelled/stale tasks cannot mutate a restarted effect.
- Draw exactly one red `NotchShape` overlay inside `growingPanel`. It inherits current frame and animated corner radii; it never overlays `MainPanelView`, `TimerView`, or internal cards.
- Keep the completion deadline in `NotchTimerState` across root replacement. Expand/collapse changes geometry only.
- Extend the notch snapshot with explicit activity (`idle`, determinate countdown, active Count Up) instead of overloading zero progress. Preserve `TimerProgress.fraction` for Duration and End Time.
- Render Count Up as the existing `stopwatch` symbol using category color and restrained breathing transform/opacity. Do not rotate it, show infinity, fake percentage, or partially filled progress.
- Under Reduce Motion, disable both loops but retain a solid completion border for the remaining three-second state and a static stopwatch for active Count Up.
- Keep visual marks decorative to AX while exposing collapsed status as “Count Up timer running”; preserve existing sound, values, controls, and labels.
- Update `DESIGN.md` before production code with named tokens, exact timing, geometry ownership, interruption, and Reduce Motion endpoints.
- Preserve normal-profile data and the sole verified app process until an implementation worker intentionally builds and relaunches the final verified Release.

## Scope IN
- `DESIGN.md` motion/accessibility contract for the completion border and Count Up collapsed activity mark.
- `NotchTimerState.swift` activity-kind snapshot and restartable completion-effect state.
- `FloatingPanelController.swift` mapping from timer mode/running state and finish callback into notch presentation state.
- `NotchView.swift` outer completion border and collapsed Count Up stopwatch mark.
- Deterministic unit/hosted tests in `NotchShellTests.swift`, with existing `TimerEngineTests.swift` retained as engine/persistence regression boundary.
- Fresh clean build, full Swift tests, changed-file LSP diagnostics, exact Release app QA, normal/Reduce Motion recordings, artifact/process binding, and ULW evidence refresh.

## Scope OUT (Must NOT have)
- No changes to `TimerEngine` math, finish semantics, persistence, Core Data schema, Timer controls, Dayline/Stream, Todo, Settings, or shell dimensions.
- No internal Timer-card border, full-screen overlay, border around the invisible host window, or stroke around its 20pt shadow padding.
- No completion scale bounce, elastic easing, blur, layout jitter, or more than three visual flashes in three seconds.
- No fake Count Up progress, percentage, rotating ring, new product logo/asset, or perpetual animation outside active Count Up.
- No new dependency, `npx impeccable install`, web framework, paid service, analytics, setting, preference, or persisted option.
- No fixed sleeps/poll loops in tests, timing-luck assertion, or weakened/deleted existing test.
- No Git commit, reset, checkout, or revert unless separately authorized.

## Open questions
None. “Logo” resolves reversibly to the repository’s existing Count Up `stopwatch` mark; the user can veto this default at the gate.

## Approval gate
status: awaiting-approval
<!-- When exploration is exhausted and unknowns are answered, set status: awaiting-approval. -->
<!-- That durable record is the loop guard: on a later turn read it and resume at the gate instead of re-running exploration. -->
Approach ready for owner approval. The next action is `write and review .omo/plans/timer-finish-and-countup-motion.md`. Approval authorizes plan creation, Metis gap analysis, and MOMUS review only; it does not authorize product-code implementation.
