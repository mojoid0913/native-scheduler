---
slug: native-scheduler-functional-recovery-realtime
status: approved
intent: clear
review_required: true
plan_path: .omo/plans/native-scheduler-functional-recovery-realtime.md
plan_sha256: 4b799409d4f5aab697e048945a7b62c0d808850d54c6ca2f0a30d55bf607b93c
review_round_id: momus-round-2-4b799409
review_round_limit: 5
pending-action: write and review .omo/plans/native-scheduler-functional-recovery-realtime.md
review:
  history:
    - round_id: momus-round-1-b4c0f46e
      plan_sha256: b4c0f46e293881b17bbd20034011b48f9a0877bf9d89fbddfa857a387ee7d3b5
      session: st_01a00c9a
      result: "REJECT: Todo 6 QA lacked exact commands/AX expectations; F1-F4 lacked executable QA scenarios and approval evidence procedures."
      fix_summary: "Added exact Settings tests and AX sequence; added commands, artifact checks, expected results, and approval thresholds to F1-F4."
  momus:
    status: approved
    workspace_root: /Users/chan/Projects/native_schedular
    runtime_home: null
    target: .omo/plans/native-scheduler-functional-recovery-realtime.md
    round_id: momus-round-2-4b799409
    plan_sha256: 4b799409d4f5aab697e048945a7b62c0d808850d54c6ca2f0a30d55bf607b93c
    launch_id: native-scheduler-realtime-plan-momus-r2
    session: st_01a00c9f
    result: "OKAY: all references and evidence paths exist and are relevant; every todo has executable QA commands and expected outcomes."
    fix_summary: "Round 1 blockers fixed; round 2 approved against the unchanged live digest."
approach: Reconstruct the accepted behavior contract from Codex sessions and existing plans, reproduce every user action against one exact app artifact, then repair persistence/state propagation at the transaction boundary with narrow typed domain signals before recovering each feature domain with failing-first publisher, AppKit, persistence, clock, and real-app QA.
---

# Draft: native-scheduler-functional-recovery-realtime

## Components (topology ledger)
<!-- Lock the SHAPE before depth. One row per top-level component that can succeed or fail independently. -->
<!-- id | outcome (one line) | status: active|deferred | evidence path -->
C1 | Accepted Codex-era functionality is an explicit executable behavior ledger | active | `.omo/evidence/native-scheduler-functional-recovery-realtime/C1/behavior-ledger.md`
C2 | Every mutation has deterministic save -> publish -> render ordering and typed failure behavior | active | `.omo/evidence/native-scheduler-functional-recovery-realtime/C2/state-contract.log`
C3 | Tasks create/edit/complete/reopen/delete/folder/reorder operations render immediately and persist | active | `.omo/evidence/native-scheduler-functional-recovery-realtime/C3/`
C4 | Timer modes, lifecycle, category changes, and persistence remain authoritative and immediately visible | active | `.omo/evidence/native-scheduler-functional-recovery-realtime/C4/`
C5 | Dayline compact/five-day/detail/live segments track Timer and persisted sessions without stale frames | active | `.omo/evidence/native-scheduler-functional-recovery-realtime/C5/`
C6 | Settings, category/default changes, shell controls, disclosure rail, and lifecycle actions stay connected | active | `.omo/evidence/native-scheduler-functional-recovery-realtime/C6/`
C7 | Build and launch provenance always identifies the exact freshly built app under test | active | `.omo/evidence/native-scheduler-functional-recovery-realtime/C7/provenance.json`
C8 | Full automated gates and isolated plus normal-profile real-app QA pass with zero unexplained failures | active | `.omo/evidence/native-scheduler-functional-recovery-realtime/C8/`

## Open assumptions (announced defaults)
<!-- Record any default you adopt instead of asking, so the user can veto it at the gate. -->
<!-- assumption | adopted default | rationale | reversible? -->
"Existing functionality" baseline | Union of accepted behavior in current source, `.omo/plans/product-hardening-efficiency-audit.md`, `.omo/plans/daily-time-narrative-redesign.md`, `.omo/plans/dayline-five-day-density-timer-truth.md`, and linked Codex sessions; rejected experiments are excluded | Repository has no Git HEAD, so history cannot supply the baseline | yes
Realtime local mutation | From the user event, Task/setting optimistic state is visible by the next main run-loop turn and is confirmed or visibly rolled back after persistence; Timer model state publishes before the action returns and dependent SwiftUI surfaces reflect it on the next render; running time follows an injected monotonic one-second tick | Matches the user's immediate-feedback requirement without promising impossible same-stack SwiftUI rendering or hiding save failure | yes
User data | Preserve the current Core Data store, preferences, categories, sessions, tasks, folders, daily logs, and launch-at-login state; use isolated temporary HOME/store first | Recovery must not trade functionality for data loss | no destructive migration
Visual scope | Preserve the approved current dark balanced design, rail, spacing, typography, and settings placement; change only interaction feedback required to make state truthful | User explicitly asked for functional recovery, not another redesign | yes
Canonical runtime | SwiftPM remains the unit-test surface; final GUI QA launches the exact freshly built Xcode app bundle and records PID, executable path, hash, store path, and build receipt | Current SwiftPM and Xcode binaries have different hashes and a stale/wrong launch can look like lost functionality | yes
Git | No commits are created unless the user separately authorizes them | Repository reports no commits/HEAD and commit authorization was not given | yes

## Findings (cited - path:lines)
- The product code has not been reduced to a mock design: Tasks, Timer, Dayline, Settings, shell, persistence, and lifecycle source files are still registered. The accepted feature history is preserved in `.omo/boulder.json:1-54` and the three existing plans, including the full Dayline/Timer final verification wave in `.omo/plans/dayline-five-day-density-timer-truth.md:100-237`.
- There is no Git HEAD. `git status --short` reports an unborn repository, so a normal “restore the pre-design commit” operation is impossible. The plan must use the recorded Codex session IDs in `.omo/boulder.json:8-42` and executable behavior as the recovery oracle.
- `CoreDataStack.save` schedules `ctx.save()` through `ctx.perform` and returns immediately; errors are printed but not propagated (`NativeScheduler/Sources/NativeScheduler/Models/CoreDataStack.swift:34-40`). Callers can therefore reload/publish before durability succeeds, and dependent stores that listen for save notifications can update later or not at all.
- `TodoViewModel` is a local `@StateObject` while Timer and Dayline use different ownership/notification paths (`NativeScheduler/Sources/NativeScheduler/Features/FloatingPanel/MainPanelView.swift:15-20`). This proves fragmented propagation, not duplicate owners by itself. The verified causal defect is that Todo actions call `save()` and immediately call `reload()` (`NativeScheduler/Sources/NativeScheduler/Features/Todo/TodoViewModel.swift:28-59`) without a deterministic transaction boundary.
- The native Return bridge intentionally defers submission one main-queue turn (`NativeScheduler/Sources/NativeScheduler/Features/Todo/TodoTaskInputField.swift:58-96`). That is safe for AppKit delegate reentrancy, but the current regression only asserts source structure rather than driving the real field and observing the rendered list (`NativeScheduler/Tests/NativeSchedulerTests/NotchShellTests.swift:1065-1115`).
- Dayline has stronger live-state tests and observes Core Data save notifications, but its refresh timing still depends on the asynchronous save boundary (`NativeScheduler/Sources/NativeScheduler/Features/Heatmap/HeatmapViewModel.swift:318-376`). This can explain a Timer change appearing before the corresponding Dayline segment.
- Settings refreshes Timer categories and Todo only when the settings sheet dismisses (`NativeScheduler/Sources/NativeScheduler/Features/FloatingPanel/MainPanelView.swift:110-125`); category/default changes do not share one explicit mutation result stream across every consumer.
- The present automated suite is not a clean gate: `swift test --package-path NativeScheduler` executes 112 tests and reports 25 assertion failures concentrated in `testExpandedLayoutClampsMalformedSmallProposalsWithoutOverflow` and `testExpandedMainPanelRendersEveryTaskEightFixtureAtTheRealPaddedChild`. LSP reports 0 diagnostics across 30 Swift source files, so this is behavioral/layout debt, not compilation failure.
- Existing tests cover Timer/Dayline model semantics well but have no equivalent end-to-end Task CRUD/folder/persistence publisher suite. A source-string test can pass while the actual view remains stale.
- The running SwiftPM executable and the latest Xcode Debug app have different SHA-256 hashes. That is expected for different build products, but without PID/path/hash receipts it is impossible for a user to know which product is being tested.

## Decisions (with rationale)
- Build an executable behavior ledger first. Every accepted action gets trigger, expected on-screen delta, persistence delta, failure behavior, automated test, manual QA invocation, and evidence path.
- Fix the root transaction ordering rather than add more opportunistic `reload()` calls. A mutation has two explicit states: optimistic presentation for immediate feedback, then terminal success only after persistence, authoritative snapshot application, and affected-domain signal emission; failure rolls back and surfaces a typed error without emitting success.
- Keep one long-lived observable owner per domain as an invariant, not as the assumed root cause. Inject it at the narrowest shared composition scope. Use narrow typed affected-domain signals or awaited mutation results, not a generic event bus; no consumer depends solely on sheet dismissal or an unsequenced notification.
- Serialize overlapping mutations or attach monotonic revisions so an older save/reload completion can never overwrite a newer published snapshot.
- Give Dayline exactly one effective refresh path per relevant mutation: explicit affected-domain signals are preferred; any retained Core Data notification must be main-thread filtered and de-duplicated. An unrelated Todo save causes zero Dayline refreshes and one relevant session save causes exactly one.
- Preserve the AppKit next-run-loop Return handoff, but anchor its SLA to the key event: verify a real `NSTextField` produces exactly one optimistic row/count update on the next main turn, then one terminal persistence result or one visible rollback, with bounded expectations and no sleeps.
- Recover complete Tasks behavior, not just Enter: active/done counts, complete/reopen/delete, folder create/rename/delete/expand, item and folder reorder, cross-folder moves, drag auto-scroll, empty states, and relaunch persistence all receive failing-first coverage.
- Treat Timer -> Dayline propagation as one user-visible transaction: start/pause/resume/stop/reset and mode/category changes synchronously publish model authority; SwiftUI reflects it on the next render; midnight/DST and live growth use an injected manual monotonic clock/tick source so there is one update per running second, none while stopped, no duplicate ticker after restart, and correct catch-up after delayed execution.
- Treat Settings/category/default changes as live domain mutations. Timer selector, active accent, Dayline colors/labels, and defaults must converge without reopening the shell or relaunching.
- Add exact-artifact runtime receipts and prohibit final QA against an unverified binary. The final process must be the one built in the same verification run.
- Full completion requires zero test failures caused or tolerated by the recovery. Before the fix, baseline comparison keys on the exact two known failing test identities, not only the count. The final gate fixes those NotchShell failures at their actual layout/accessibility root cause and reaches zero failures without weakening assertions.
- Verification is TDD for behavioral changes: subscribe before triggering, use bounded expectations, never fixed sleeps/polling, then drive isolated real-app happy/failure/relaunch flows and a final non-destructive normal-profile smoke.

## Scope IN
- Complete shell/notch expand-collapse-hover behavior, disclosure rail `<`/`>`, settings/menu entry, and settings-button placement.
- Complete Tasks CRUD, active/done columns and counts, folders/sections, drag/reorder/cross-folder movement, auto-scroll, native keyboard submission, Core Data durability, failure state, and relaunch restoration.
- Complete Timer normal/duration/end-time modes, start/pause/resume/stop/reset, category switching, crash/termination/finalization behavior, persisted session truth, and visible progress.
- Complete Dayline compact and five-day views, live current-day growth, Timer/category synchronization, details, marker/segment selection, midnight/DST behavior, accessibility, and readable metadata.
- Complete Settings category CRUD, default category/duration, launch-at-login truth, and propagation to all visible consumers.
- Deterministic in-memory persistence tests, AppKit/SwiftUI integration tests, full Swift tests, Xcode build, LSP diagnostics, exact-binary provenance, isolated real-app QA, normal-profile smoke, and evidence cleanup.
- Preserve current user data and the approved visual design.

## Scope OUT (Must NOT have)
- No new product feature, new visual redesign, schema reset, store deletion, user-data reseeding, or mock replacement of existing functionality.
- No Git reset/checkout, no attempt to fabricate missing repository history, and no commit without separate authorization.
- No fixed sleeps, polling-delay tests, source-string-only behavioral claims, skipped/weakened tests, swallowed persistence errors, duplicate source of truth, or “should work” verification.
- No final QA against a smoke fixture, empty synthetic shell, stale process, or executable whose path/hash/store cannot be proven.

## Open questions
None. The remaining choices are reversible implementation details governed by the accepted behavior and non-destructive defaults above.

## Approval gate
status: awaiting-approval
<!-- When exploration is exhausted and unknowns are answered, set status: awaiting-approval. -->
<!-- That durable record is the loop guard: on a later turn read it and resume at the gate instead of re-running exploration. -->
