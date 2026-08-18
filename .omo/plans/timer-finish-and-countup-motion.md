# timer-finish-and-countup-motion - Work Plan

## TL;DR (For humans)
<!-- Fill this LAST, after the detailed plan below is written, so it summarizes the REAL plan. -->
<!-- Plain English for a non-engineer: NO file paths, NO todo numbers, NO wave/agent/tool names. -->

**What you'll get:** When a countdown ends, the camera-attached notch flashes a red outline for exactly three seconds; if the panel is open, that same alert follows the complete outer panel. A running Count Up timer gets a living stopwatch mark instead of an empty progress circle.

**Why this approach:** The timer engine and saved sessions remain untouched. One retained presentation state drives both shell sizes, so opening or closing the panel cannot restart or lose the alert.

**What it will NOT do:** It will not add a full-screen alert, decorate an internal Timer card, invent fake Count Up progress, change timer math or saved data, or install a new dependency.

**Effort:** Medium
**Risk:** Medium - timing state must survive SwiftUI root replacement and remain deterministic under Reduce Motion.
**Decisions to sanity-check:** Three one-second red opacity pulses; a 2pt outer-shell stroke; a category-colored stopwatch breathing at 1.6 seconds; static equivalents under Reduce Motion.

Your next move: Execute through the existing durable ULW loop after Metis and MOMUS approve this plan. Full execution detail follows below.

---

> TL;DR (machine): Medium-risk SwiftUI/AppKit presentation-state change delivering a generation-safe 3.0s completion border and an active Count Up stopwatch mark without touching TimerEngine or persistence.

## Scope
### Must have
- Replace the existing `0.28s` whole-shell completion scale with a restartable `3.0s` red outer-shell border.
- Draw the border around the rendered camera-attached `NotchShape` while collapsed and the complete `816x384` outer `NotchShape` while expanded.
- Preserve the original completion deadline while expansion/collapse retargets the border geometry.
- Show exactly three one-second opacity pulses: opacity `1.0` at `t=0.0`, `0.25` at `0.5`, `1.0` at `1.0`, `0.25` at `1.5`, `1.0` at `2.0`, `0.25` at `2.5`, and remove at exactly `3.0`, using 0.5s `easeInOut` transitions; use a solid red border for the same lifetime under Reduce Motion.
- Replace the Count Up zero-progress ring with the existing `stopwatch` mode symbol using the selected category color.
- Animate only active Count Up with a full `1.6s` opacity/scale breathing round trip: 0.8s to scale `1.04`/opacity `1.0`, then 0.8s to scale `0.94`/opacity `0.72`; render a static symbol under Reduce Motion.
- Keep effect state outside view-local `@State`, cancel stale scheduled phases by generation, and expose deterministic scheduler seams.
- Keep an active completion effect through start, stop, reset, pause, category change, mode switch, and expand/collapse; none cancels or restarts its original deadline. A distinct new accepted automatic finish restarts a fresh 3.0s generation; expiry or `NotchTimerState` deinitialization cancels it.
- Publish one atomic final idle notch snapshot synchronously before activating the completion generation so the first red frame never outlines the running indicator rail.
- Preserve all current timer arithmetic, sound, session persistence, shell geometry, hover/click behavior, and normal-profile data.

### Must NOT have (guardrails, anti-slop, scope boundaries)
- No `TimerEngine` timing/finish/count-up calculation change and no Core Data/schema change.
- No internal Timer-card keyline, full-screen overlay, invisible host-window border, or stroke around shadow padding.
- No bounce/elastic scale, blur, rotation, fake progress, percentage, infinity glyph, new logo asset, or motion when Count Up is paused/stopped.
- No new dependency, `npx impeccable install`, preference, setting, analytics, packaging target, or deployment-target change.
- No fixed sleep or polling in tests; no weakened, skipped, or deleted regression.
- No mutating timer scenario against the normal-profile store or preferences; all short countdown and Count Up interaction recordings use the sentinel-protected isolated profile.
- No Git commit or destructive Git action because the user did not authorize commits and this repository has no baseline `HEAD`.

## Verification strategy
> Zero human intervention - all verification is agent-executed.
- Test decision: TDD with XCTest plus deterministic injected scheduler/phase drivers; hosted SwiftUI/AppKit geometry and accessibility tests; full `swift test`.
- Evidence: `<attemptDir>/task-<N>-timer-finish-and-countup-motion.<ext>` where `<attemptDir>` is obtained from `omo-agent-toolkit ulw-loop status --json --session-id native-scheduler-realtime-recovery-20260817` after G008 registration.
- Behavioral surface: exact Release artifact driven through the sentinel-protected isolated profile for all mutating countdown/Count Up recordings; the same binary receives a separate read-only normal-profile smoke and is the only retained final process.
- Happy QA: run Count Up collapsed and observe the breathing stopwatch; finish a short countdown collapsed and expanded; expand/collapse during the active border.
- Failure/edge QA: repeat completion trigger, start/stop/reset/pause/category/mode changes during the effect, paused Count Up, injected Reduce Motion hosted surface, root reconstruction, and post-effect cleanup; verify the original deadline is retained, no residual border/animation exists, and no normal-profile store/preferences bytes change.
- Required gates: changed-file LSP diagnostics, focused tests, full Swift tests, clean Release Xcode build, strict codesign/plist, exact executable hash/process/store binding, final independent review.

## Execution strategy
### Parallel execution waves
> Target 5-8 todos per wave. Fewer than 3 (except the final) means you under-split.
- Wave 1 is sequential contract/state work because all later rendering depends on the exact snapshot and completion-effect interfaces.
- Wave 2 can execute controller mapping and view rendering only after Todo 2 fixes those interfaces; they share `NotchShellTests.swift`, so one worker owns both to avoid collisions.
- Wave 3 runs diagnostics/tests/build and real-surface QA after the code is stable.
- Team mode: OFF. Every implementation unit touches the same notch contract or shared test file and later units consume earlier interfaces, so parallel teammates would collide rather than shorten the critical path.

### Dependency matrix
| Todo | Depends on | Blocks | Can parallelize with |
| --- | --- | --- | --- |
| 1 | none | 2, 3, 4 | none |
| 2 | 1 | 3, 4, 5 | none |
| 3 | 2 | 4, 5 | none |
| 4 | 2, 3 | 5, 6 | none |
| 5 | 2, 3, 4 | 6, final wave | none |
| 6 | 5 | final wave | none |

## Todos
> Implementation + Test = ONE todo. Never separate.
<!-- APPEND TASK BATCHES BELOW THIS LINE WITH edit/apply_patch - never rewrite the headers above. -->
- [ ] 1. Lock the completion-border and Count Up activity-mark design contract
  - Recommended task executor category: `visual-engineering`
  - What to do / Must NOT do: Update `DESIGN.md` with the exact phase table (`1.0/0.25` at each 500ms boundary, removed at 3.0s), `2pt` inner outer-shell stroke, collapsed versus expanded geometry ownership, the full 1.6s stopwatch round trip (`0.8s` each direction), non-cancelling interruption rules, atomic idle-snapshot ordering, accessibility semantics, and static Reduce Motion endpoints. Do not alter existing Stream/Timer density tokens or outer geometry.
  - Parallelization: Wave 1 | Blocked by: none | Blocks: 2, 3, 4
  - References: `.omo/drafts/timer-finish-and-countup-motion.md`; `DESIGN.md:84-118,150-176`; official Impeccable animate guidance `https://impeccable.style/docs/animate/`.
  - Acceptance criteria: a read-only contract check can identify every phase timestamp/opacity/easing, both breathing half-cycles, inner-stroke geometry, both shell endpoints, start/stop/reset/pause/category/mode behavior, atomic finish ordering, active/paused/idle behavior, and all Must-NOT-Have constraints without consulting chat history.
  - QA scenarios: happy = inspect rendered contract with `read DESIGN.md`; failure = search for conflicting old `0.28s` completion-scale wording and ensure none remains. Evidence `<attemptDir>/task-1-design-contract.md`.
  - Commit: N | User did not authorize Git commits; keep the verified worktree uncommitted.

- [ ] 2. TDD the retained completion lifecycle and explicit notch activity snapshot
  - Recommended task executor category: `unspecified-high`
  - What to do / Must NOT do: In `NotchShellTests.swift`, first add failing tests for immediate opacity `1.0`, each exact 500ms phase (`0.25/1.0/0.25/1.0/0.25`), inactive terminal state at 3.0s, stale-generation cancellation, distinct-completion restart, no restart/cancel on start/stop/reset/pause/category/mode/expand/collapse, and Reduce Motion mapping. Add explicit idle/determinate-countdown/active-count-up snapshot semantics. Implement the smallest state changes in `NotchTimerState.swift` with an injected async sleeper/manual phase driver and cancel the owned task on deinit. Do not add real sleeps or touch TimerEngine.
  - Parallelization: Wave 1 | Blocked by: 1 | Blocks: 3, 4, 5
  - References: `NotchTimerState.swift:1-24`; `NotchShellTests.swift:1160-1215`; `TimerEngine.swift:122-201`; draft Decisions section.
  - Acceptance criteria: focused tests fail for the missing lifecycle before implementation, then pass; one trigger yields the exact phase table across six manual releases and inactive at 3.0s; a distinct completion invalidates stale callbacks; unrelated timer/UI state changes preserve generation/deadline; Count Up never maps to determinate progress.
  - QA scenarios: happy = `swift test --package-path NativeScheduler --filter NotchShellTests`; failure = manually deliver an old generation after restart and assert no state mutation. Evidence `<attemptDir>/task-2-state-tdd.txt`.
  - Commit: N | User did not authorize Git commits; keep the verified worktree uncommitted.

- [ ] 3. Thread timer mode and completion state through the retained controller bridge
  - Recommended task executor category: `unspecified-high`
  - What to do / Must NOT do: Replace independently scheduled snapshot publications with one main-actor snapshot publisher that atomically samples `mode`, running state, determinate progress, and category color. In `TimerViewModel.onTimerFinished`, synchronously publish the final idle snapshot before triggering the generation-safe effect, after session finalization. Preserve engine callbacks, sound, storage order, and the sole state owner.
  - Parallelization: Wave 2 | Blocked by: 2 | Blocks: 4, 5
  - References: `FloatingPanelController.swift:57-100`; `TimerViewModel.swift:249-269`; `TimerEngine.swift:145-201`; `NotchTimerState.swift`.
  - Acceptance criteria: deterministic tests prove Duration/End Time map to determinate activity, active Count Up maps to its explicit mark, pause/stop removes active Count Up motion, every snapshot is atomically consistent, the first active completion snapshot is idle-width, and each accepted automatic finish triggers one effect after finalization.
  - QA scenarios: happy = focused controller/snapshot XCTest invocation; failure = deliver queued stale publications around finish and assert no extended-rail first frame, zero-progress Count Up ring, or duplicate effect. Evidence `<attemptDir>/task-3-controller.txt`.
  - Commit: N | User did not authorize Git commits; keep the verified worktree uncommitted.

- [ ] 4. Render one shell border and one breathing Count Up stopwatch
  - Recommended task executor category: `visual-engineering`
  - What to do / Must NOT do: Conform `NotchShape` to `InsettableShape` without changing its outer path, then replace `pulseScale` in `NotchView.swift` with one `strokeBorder(lineWidth: 2)` completion overlay whose frame/corner radii inherit `growingPanel`; use only the published semantic-red opacity. In the collapsed rail, keep the determinate ring for countdowns and render the existing `stopwatch` SF Symbol for Count Up with category color and the exact 0.8s+0.8s breathing round trip. Gate loops with Reduce Motion; keep marks AX-hidden and expose live status on the shell control.
  - Parallelization: Wave 2 | Blocked by: 2, 3 | Blocks: 5, 6
  - References: `NotchView.swift:20-153`; `NotchShape.swift:1-43`; `NotchGeometry.swift:5-64`; `NotchWindow.swift:161-223`; `TimerView.swift:495-507`; `DESIGN.md` contract from Todo 1.
  - Acceptance criteria: hosted tests assert `strokeBorder` stays entirely inside the unchanged outer edge, collapsed border follows idle shell bounds from its first active frame, expanded border follows `816x384` and excludes shadow padding, root reconstruction does not reset phase/deadline, countdown keeps determinate trim, Count Up uses stopwatch/no trim/exact full-cycle timing, paused/stopped Count Up has no loop, and Reduce Motion uses static endpoints.
  - QA scenarios: happy = hosted `NotchView` snapshots at bright/dim/terminal and active Count Up phases; failure = reconstruct the root mid-effect and assert generation/phase/lifetime persist. Evidence `<attemptDir>/task-4-hosted-ui.png` plus `<attemptDir>/task-4-hosted-tests.txt`.
  - Commit: N | User did not authorize Git commits; keep the verified worktree uncommitted.

- [ ] 5. Run deterministic regression, diagnostics, and clean Release gates
  - Recommended task executor category: `unspecified-high`
  - What to do / Must NOT do: Run changed-file LSP diagnostics, focused Notch/Timer tests, full `swift test --package-path NativeScheduler`, clean Xcode Release build into the authoritative DerivedData path, plist validation, and strict deep codesign. Fix only regressions caused by this work; never weaken tests or modify unrelated files.
  - Parallelization: Wave 3 | Blocked by: 2, 3, 4 | Blocks: 6, final wave
  - References: `NativeScheduler/Package.swift`; existing G003/G004 evidence commands; `.omo/evidence/ulw/native-scheduler-realtime-recovery-20260817/`.
  - Acceptance criteria: zero changed-file diagnostics; focused and full suites pass once with zero failures; clean Release exits 0; plist and codesign pass; executable/source/bundle hashes are recorded.
  - QA scenarios: happy = all commands exit 0; failure = any new warning, stale module diagnostic, test flake, code-sign failure, or hash mismatch blocks progression. Evidence `<attemptDir>/task-5-engineering-gates.txt`.
  - Commit: N | User did not authorize Git commits; keep the verified worktree uncommitted.

- [ ] 6. Exercise the exact Release app and bind durable evidence
  - Recommended task executor category: `visual-engineering`
  - What to do / Must NOT do: Run every short countdown and Count Up interaction against a sentinel-protected isolated HOME/store using the exact verified Release; set smoke quit timeout to at least countdown duration plus 4s and drive Count Up through AX. Verify collapsed completion, expanded completion, expand/collapse mid-alert, Count Up active/paused/stopped, normal motion, hosted Reduce Motion, and cleanup after 3.0s. Then hash the normal store/preferences, launch the same artifact for read-only smoke only, verify byte-for-byte preservation, and retain exactly that one normal-profile process. Refresh G008 evidence, ledger, provenance, and final binding through named-session ULW CLI only.
  - Parallelization: Wave 3 | Blocked by: 4, 5 | Blocks: final wave
  - References: existing G002 QA tools; G004 artifact-provenance format; `AGENTS.md` normal-profile/AVD constraints; ULW manual-QA and cleanup rules.
  - Acceptance criteria: isolated-store video/stills show the exact phase cadence and no stroke after 3.0s; collapsed capture outlines only the camera shell; expanded capture outlines the full outer shell; Count Up shows the exact breathing stopwatch and no empty ring; hosted Reduce Motion is static; normal store/preferences before/after hashes match; source/binary/PID/store receipts agree; one latest normal-profile app remains.
  - QA scenarios: happy = sentinel-protected short countdown and AX-driven Count Up on exact Release; failure = root reconstruction mid-alert, state changes during alert, paused/stopped Count Up, injected Reduce Motion, timeout shorter than duration+4s, old process/hash, residual border, or any normal-profile hash change. Evidence `<attemptDir>/task-6-isolated-motion.mov`, `<attemptDir>/task-6-reduce-motion.mov`, `<attemptDir>/task-6-normal-readonly-binding.txt`.
  - Commit: N | User did not authorize Git commits; keep the verified worktree uncommitted.

## Final verification wave
> Runs in parallel after ALL todos. ALL must APPROVE. Surface results and wait for the user's explicit okay before declaring complete.
- [ ] F1. Plan compliance audit
  - Recommended task executor category: `unspecified-high`
  - Verify every Must-have/Must-NOT-Have and evidence reference against current source and G008 receipts; reject unsupported claims.
- [ ] F2. Code quality and deterministic-timing review
  - Recommended task executor category: `unspecified-high`
  - Review generation cancellation, ownership, scheduler seams, memory/task cleanup, Combine publication consistency, AX semantics, and test reliability.
- [ ] F3. Real manual visual QA
  - Recommended task executor category: `visual-engineering`
  - Independently drive the exact Release app, inspect fresh normal/Reduce Motion recordings and endpoint stills, and reject clipping, card-local borders, empty rings, jitter, strobe cadence, or stale artifacts.
- [ ] F4. Scope and data-safety fidelity
  - Recommended task executor category: `unspecified-high`
  - Confirm TimerEngine/persistence/schema/shell dimensions and unrelated features are unchanged, normal data is preserved, evidence hashes bind to source/artifact, and only the latest process remains.

## Commit strategy
- No commits. The user did not request commits, the repository has no authentic `HEAD`, and the parent worktree sees this project as untracked.
- Preserve unrelated changes and rely on explicit source/bundle hashes plus ULW ledger receipts instead of Git history.

## Success criteria
- Automatic Duration/End Time completion produces exactly three red outer-shell opacity pulses over 3.0 seconds.
- Collapsed alert outlines only the camera-attached shell; expanded alert outlines the complete `816x384` outer shell; expansion/collapse preserves remaining lifetime.
- Active Count Up displays a category-colored breathing stopwatch in the collapsed rail, while paused/stopped states do not loop and no fake progress appears.
- Reduce Motion renders static completion and Count Up indicators with the requested state duration and no pulse/spring loop.
- Timer engine calculations, sound, persistence, normal-profile records, shell geometry, and unrelated features remain intact.
- Deterministic focused tests, full Swift tests, changed-file diagnostics, clean Release build, codesign/plist, real-app manual QA, independent reviews, and exact artifact/PID/store receipts all pass.
