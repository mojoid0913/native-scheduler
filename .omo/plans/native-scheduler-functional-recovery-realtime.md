# native-scheduler-functional-recovery-realtime - Work Plan

## TL;DR (For humans)
<!-- Fill this LAST, after the detailed plan below is written, so it summarizes the REAL plan. -->
<!-- Plain English for a non-engineer: NO file paths, NO todo numbers, NO wave/agent/tool names. -->

**What you'll get:** NativeScheduler의 기존 Tasks, Timer, Dayline, Settings, shell 기능이 다시 하나의 실제 앱에서 모두 동작하고, 모든 로컬 변경이 즉시 화면에 반영되며 저장 실패도 거짓 성공 없이 표시됩니다.

**Why this approach:** 디자인 파일을 되돌리는 대신 Codex 작업 기록과 현재 제품 동작을 실행 가능한 기준으로 고정합니다. 저장 완료·화면 publish·도메인 간 갱신 순서를 먼저 바로잡아 개별 화면에 임시 reload를 추가하는 방식의 재발을 막습니다.

**What it will NOT do:** 현재 디자인을 다시 설계하지 않습니다. 사용자 데이터나 설정을 초기화하지 않습니다. 테스트를 삭제·완화하거나 다른 프로젝트의 앱/AVD를 건드리지 않습니다.

**Effort:** Large
**Risk:** High - Core Data 저장 순서와 SwiftUI/AppKit 상태 전파가 Tasks, Timer, Dayline, Settings 전부를 가로지릅니다.
**Decisions to sanity-check:** Tasks는 다음 main-loop turn에 optimistic render 후 저장 실패 시 rollback하며, Timer 모델은 액션 반환 전 publish하고 SwiftUI는 다음 render에서 반영합니다. 최종 GUI QA는 같은 Xcode app artifact 하나만 사용합니다.

Your next move: Execute this approved plan under a fresh ULW session after MOMUS approval. Full execution detail follows below.

---

> TL;DR (machine): Large/high-risk cross-domain recovery; deterministic persistence/publish ordering, complete feature restoration, zero-test-failure build, exact-artifact GUI QA.

## Scope
### Must have
- Preserve and verify shell hover/click expansion, collapse, disclosure rail `<`/`>`, settings placement/menu, and current approved visual balance.
- Restore immediate Tasks create/edit/complete/reopen/delete, active/done counts, sections/folders, drag/reorder/cross-folder movement, auto-scroll, persistence, failure rollback, and relaunch restoration.
- Restore Timer normal/duration/end-time modes, start/pause/resume/stop/reset, category switching, single tick ownership, crash/termination finalization, and persisted session truth.
- Restore Dayline compact/five-day/detail interactions, live current segment, totals, category color/labels, midnight/DST behavior, and exactly-once refreshes from relevant Timer/session mutations.
- Restore Settings category CRUD, default category/duration, launch-at-login truth, and live propagation without relying on sheet dismissal.
- Run failing-first deterministic tests, full Swift tests, LSP diagnostics, Xcode build, isolated real-app QA, normal-profile smoke, independent final reviews, and leave the verified app running.

### Must NOT have (guardrails, anti-slop, scope boundaries)
- No schema reset, persistent-store deletion, user-data reseed, preference reset, destructive migration, or silent compatibility shim.
- No visual redesign, new product feature, broad generic event bus, duplicate state owner, opportunistic reload loop, swallowed save error, fixed sleep, polling-based test, source-string-only behavioral proof, or test weakening.
- No stale/smoke-only executable as final evidence. No other project's AVD/process. No Git commit because the repository has no HEAD and the user did not authorize commits.

## Verification strategy
> Zero human intervention - all verification is agent-executed.
- Test decision: TDD with XCTest/Swift Testing. Subscribe to the exact publisher/event before each action; use bounded expectations and injected clocks, never sleeps.
- Evidence: <attemptDir>/task-<N>-native-scheduler-functional-recovery-realtime.<ext> (attemptDir = currentAttemptDir from 'omo-agent-toolkit ulw-loop status --json', .omo/evidence/ulw/<session>/<goalId>/a<attempt>; outside ulw-loop use .omo/evidence/)
- Automated gates: `lsp_diagnostics` on changed Swift files; `swift test --package-path NativeScheduler` with zero failures; `xcodebuild -project NativeScheduler/NativeScheduler.xcodeproj -scheme NativeScheduler -configuration Debug -derivedDataPath <attemptDir>/DerivedData build`.
- GUI gate: launch `<attemptDir>/DerivedData/Build/Products/Debug/NativeScheduler.app` first with isolated `HOME=<attemptDir>/qa-home`, then the normal user profile without rebuilding. Record PID, executable path, SHA-256, store path, AX action log, screenshots, and cleanup receipts.

## Execution strategy
### Parallel execution waves
> Target 5-8 todos per wave. Fewer than 3 (except the final) means you under-split.
- Wave 1: Todos 1 and 7 run in parallel because persistence ordering and Notch layout touch separate implementation seams.
- Wave 2: Todos 2 and 4 run in parallel after the persistence contract exists.
- Wave 3: Todo 3 follows Todo 2; Todo 5 follows Todo 4.
- Wave 4: Todo 6 integrates Tasks/Timer/Dayline state into Settings and shell after the domain owners are stable.
- Wave 5: Todo 8 runs the exact-artifact integration and GUI recovery gate.

### Dependency matrix
| Todo | Depends on | Blocks | Can parallelize with |
| --- | --- | --- | --- |
| 1 | none | 2, 4 | 7 |
| 2 | 1 | 3, 6 | 4 |
| 3 | 2 | 6, 8 | 5 |
| 4 | 1 | 5, 6 | 2 |
| 5 | 4 | 6, 8 | 3 |
| 6 | 2, 3, 4, 5 | 8 | none |
| 7 | none | 8 | 1 |
| 8 | 3, 5, 6, 7 | F1-F4 | none |

## Todos
> Implementation + Test = ONE todo. Never separate.
<!-- APPEND TASK BATCHES BELOW THIS LINE WITH edit/apply_patch - never rewrite the headers above. -->
- [ ] 1. Make persistence completion and failure observable before domain recovery
  - Recommended task executor category: `deep`
  - What to do / Must NOT do: Add failing tests for save completion ordering and deterministic failure, then replace `CoreDataStack.save`'s fire-and-forget `ctx.perform`/print behavior with one MainActor-safe completion-aware result. Define terminal success as save completed, authoritative snapshot applied, then affected-domain revision emitted. Provide an in-memory/failing-store seam. Migrate existing call sites to compile without hiding failures. Must not add retries, fixed waits, or a second save API that leaves callers ambiguous.
  - Parallelization: Wave 1 | Blocked by: none | Blocks: 2, 4
  - References (executor has NO interview context - be exhaustive): `NativeScheduler/Sources/NativeScheduler/Models/CoreDataStack.swift:7-40`; `NativeScheduler/Sources/NativeScheduler/Models/ManagedObjects.swift:1-260`; `NativeScheduler/Sources/NativeScheduler/Features/Todo/TodoViewModel.swift:7-154`; `NativeScheduler/Sources/NativeScheduler/Features/Timer/TimerViewModel.swift:1-282`; `.omo/drafts/native-scheduler-functional-recovery-realtime.md`
  - Acceptance criteria (agent-executable): A test subscribed before mutation proves the success event occurs only after durable save and snapshot publication; a forced save failure returns typed failure, publishes no success revision, rolls context back, and exposes no phantom persisted row. Focused tests pass once with no sleeps.
  - QA scenarios (name the exact tool + invocation): `swift test --package-path NativeScheduler --filter PersistenceRealtimeTests`; happy save plus injected failure transcript. Evidence `<attemptDir>/task-1-native-scheduler-functional-recovery-realtime.log`.
  - Commit: N | Repository has no HEAD and commit authorization was not given.

- [ ] 2. Restore immediate Task input, CRUD, counts, and persistence
  - Recommended task executor category: `unspecified-high`
  - What to do / Must NOT do: Write a real AppKit-to-view-model failing test before production changes. Inject the persistence dependency into the one long-lived `TodoViewModel`; serialize or revision-stamp overlapping mutations. Make Return submit the exact current `NSTextField` value once, optimistically publish row/count by the next main-loop turn, clear only after acceptance, confirm after save, and restore text/rollback with visible error on failure. Cover create, edit if exposed, complete, reopen, delete, active/done counts, whitespace/empty input, and relaunch persistence. Must not replace the native field with a design-only SwiftUI mock.
  - Parallelization: Wave 2 | Blocked by: 1 | Blocks: 3, 6
  - References: `NativeScheduler/Sources/NativeScheduler/Features/Todo/TodoTaskInputField.swift:1-106`; `NativeScheduler/Sources/NativeScheduler/Features/Todo/TodoViewModel.swift:7-59`; `NativeScheduler/Sources/NativeScheduler/Features/Todo/TodoListView.swift:1-575`; `NativeScheduler/Tests/NativeSchedulerTests/NotchShellTests.swift:1065-1115`
  - Acceptance criteria: A hosted real `NSTextField` Return path produces exactly one row and count update on the next main turn, one save confirmation, no duplicate submission, and rollback/text preservation on injected failure. Complete/reopen/delete each publish once and survive an in-memory store reopen.
  - QA scenarios: `swift test --package-path NativeScheduler --filter TodoRealtimeTests`; AppKit happy input `"Realtime exact task"` and save-failure input with bounded expectations. Evidence `<attemptDir>/task-2-native-scheduler-functional-recovery-realtime.log`.
  - Commit: N | Repository has no HEAD and commit authorization was not given.

- [ ] 3. Restore Task sections, drag ordering, cross-folder moves, and auto-scroll
  - Recommended task executor category: `unspecified-high`
  - What to do / Must NOT do: Extend failing tests across section create/rename/delete/expand, active/done section separation, item and section reorder, cross-folder move, invalid drag payload, and immediate 16ms auto-scroll cadence. Route every action through the same `TodoViewModel` mutation/revision contract and preserve stable IDs/order across relaunch. Must not introduce timing sleeps or update only drag overlays while leaving persisted order stale.
  - Parallelization: Wave 3 | Blocked by: 2 | Blocks: 6, 8
  - References: `NativeScheduler/Sources/NativeScheduler/Features/Todo/TodoViewModel.swift:60-154`; `NativeScheduler/Sources/NativeScheduler/Features/Todo/TodoListView.swift:90-575`; `NativeScheduler/Tests/NativeSchedulerTests/TodoDragMotionTests.swift:1-120`
  - Acceptance criteria: Publisher-backed tests prove every section/item operation changes visible snapshots exactly once; a reverse-completion persistence seam cannot overwrite the newest order; relaunch yields the same sections, membership, completion state, and priority order; drag cadence remains immediate at 16ms.
  - QA scenarios: `swift test --package-path NativeScheduler --filter TodoRealtimeTests` and `swift test --package-path NativeScheduler --filter TodoDragMotionTests`; real isolated-app drag/reorder screenshots and AX order dump. Evidence `<attemptDir>/task-3-native-scheduler-functional-recovery-realtime/`.
  - Commit: N | Repository has no HEAD and commit authorization was not given.

- [ ] 4. Restore Timer authority, modes, categories, and deterministic ticks
  - Recommended task executor category: `deep`
  - What to do / Must NOT do: Add failing tests around same-turn model publication, typed persistence failure, single ticker ownership, and delayed clock jumps. Inject a monotonic/manual clock and tick source into TimerEngine/ViewModel. Keep one authoritative running session across normal/duration/end-time start, pause, resume, stop, reset, category switch, crash/termination, and finalization. Publish Timer model state before action return, confirm/rollback persistence truth, and emit one monotonically increasing session revision only after relevant saved mutations. Must not create duplicate timers or use wall-clock sleeps.
  - Parallelization: Wave 2 | Blocked by: 1 | Blocks: 5, 6
  - References: `NativeScheduler/Sources/NativeScheduler/Features/Timer/TimerEngine.swift:1-300`; `NativeScheduler/Sources/NativeScheduler/Features/Timer/TimerViewModel.swift:1-282`; `NativeScheduler/Sources/NativeScheduler/Features/Timer/TimerView.swift:1-360`; `NativeScheduler/Tests/NativeSchedulerTests/TimerEngineTests.swift:1-520`; `NativeScheduler/Tests/NativeSchedulerTests/TerminationLifecycleTests.swift:1-180`
  - Acceptance criteria: Manual ticks produce one update per running second, none while stopped, no duplicate ticker after restart, and correct elapsed time after a multi-second jump. Each action publishes before return, persists exact session boundaries, and rolls back with visible error on injected failure.
  - QA scenarios: `swift test --package-path NativeScheduler --filter TimerEngineTests` and `--filter TerminationLifecycleTests`; isolated-app normal/duration/end-time Start/Pause/Resume/Stop/Reset plus category switch. Evidence `<attemptDir>/task-4-native-scheduler-functional-recovery-realtime/`.
  - Commit: N | Repository has no HEAD and commit authorization was not given.

- [ ] 5. Restore exactly-once Timer-to-Dayline live synchronization
  - Recommended task executor category: `deep`
  - What to do / Must NOT do: Add failing tests proving one relevant session revision causes exactly one DayActivity refresh and an unrelated Todo save causes zero. Feed `DayActivityStore` the narrow Timer/session revision source on MainActor; remove or strictly filter/de-duplicate the broad `didSave` path. Preserve compact/five-day snapshots, live growth, totals, current marker, category color/labels, selected details, midnight rollover, DST lengths, and failure snapshot rules. Must not add a generic event bus or refetch on every tick.
  - Parallelization: Wave 3 | Blocked by: 4 | Blocks: 6, 8
  - References: `NativeScheduler/Sources/NativeScheduler/Features/Heatmap/HeatmapViewModel.swift:318-525`; `NativeScheduler/Sources/NativeScheduler/Features/Heatmap/HeatmapView.swift:1-520`; `NativeScheduler/Sources/NativeScheduler/Features/Heatmap/TodayUsageSummaryView.swift:1-260`; `NativeScheduler/Sources/NativeScheduler/Features/FloatingPanel/MainPanelView.swift:15-125`; `NativeScheduler/Tests/NativeSchedulerTests/HeatmapLiveTests.swift:1-520`; `NativeScheduler/Tests/NativeSchedulerTests/HeatmapSlotTests.swift:1-680`
  - Acceptance criteria: Start/pause/resume/category/stop each update Timer and Dayline coherently on the defined render boundary; one relevant mutation yields one fetch/reprojection, Todo saves yield zero, ticks reuse the cached day snapshot, and midnight/DST tests remain deterministic.
  - QA scenarios: `swift test --package-path NativeScheduler --filter HeatmapLiveTests` and `--filter HeatmapSlotTests`; isolated-app Timer start/category switch while compact and five-day Dayline are inspected. Evidence `<attemptDir>/task-5-native-scheduler-functional-recovery-realtime/`.
  - Commit: N | Repository has no HEAD and commit authorization was not given.

- [ ] 6. Restore live Settings propagation and shared shell composition
  - Recommended task executor category: `unspecified-high`
  - What to do / Must NOT do: Write failing integration tests, then route category CRUD/default mutations through the existing Timer/category authority injected into Settings. Update Timer selector/accent, active session category, Dayline color/labels, and defaults while the sheet remains open; sheet dismissal without changes emits no reload. Preserve launch-at-login truthful failure behavior, shell interaction lock, settings midpoint placement, disclosure rail, and quit menu. Must not create a second category owner or rely on onDismiss reloads.
  - Parallelization: Wave 4 | Blocked by: 2, 3, 4, 5 | Blocks: 8
  - References: `NativeScheduler/Sources/NativeScheduler/Features/Settings/SettingsView.swift:1-260`; `NativeScheduler/Sources/NativeScheduler/Features/Settings/CategoryEditorView.swift:1-120`; `NativeScheduler/Sources/NativeScheduler/Features/FloatingPanel/MainPanelView.swift:15-211`; `NativeScheduler/Sources/NativeScheduler/Features/FloatingPanel/NotchView.swift:1-520`; `NativeScheduler/Tests/NativeSchedulerTests/NotchShellTests.swift:1-1320`
  - Acceptance criteria: Category add/rename/color/default/delete publishes once to every visible consumer before sheet close; no-op dismissal publishes zero; deleting an active/default category follows the existing safe fallback; launch-at-login failure remains visible and does not lie about enabled state.
  - QA scenarios: Run `swift test --package-path NativeScheduler --filter SettingsRealtimeTests` and `swift test --package-path NativeScheduler --filter NotchShellTests/testShellMenuCloseCannotUnlockSettingsInteraction`. Launch the isolated exact app with `HOME=<attemptDir>/qa-home <attemptDir>/DerivedData/Build/Products/Debug/NativeScheduler.app/Contents/MacOS/NativeScheduler`; use `osascript`/System Events to click Settings, add category `Realtime QA`, rename it `Realtime QA Renamed`, change its color/default, verify the Timer category selector and Dayline detail expose the renamed category before closing Settings, then close/reopen Settings and verify persistence. Invoke the launch-at-login failure seam and assert the toggle remains off with a visible error. A no-change sheet close must leave the recorded category/session revision unchanged. Save AX dumps, screenshots, test stdout, revision log, PID/path/hash, and cleanup receipt under `<attemptDir>/task-6-native-scheduler-functional-recovery-realtime/`; success requires both test commands exit 0 and every named AX/state assertion match exactly.
  - Commit: N | Repository has no HEAD and commit authorization was not given.

- [ ] 7. Fix the two existing NotchShell layout and accessibility regressions
  - Recommended task executor category: `visual-engineering`
  - What to do / Must NOT do: Reproduce `testExpandedLayoutClampsMalformedSmallProposalsWithoutOverflow` and `testExpandedMainPanelRendersEveryTaskEightFixtureAtTheRealPaddedChild` failing first, then fix the actual layout/proposal/accessibility-child root cause while preserving the approved design, rail, spacing, heights, settings position, hover/click behavior, and reduction-motion semantics. Must not change fixture expectations merely to match the bug or hide inaccessible children.
  - Parallelization: Wave 1 | Blocked by: none | Blocks: 8
  - References: `NativeScheduler/Sources/NativeScheduler/Features/FloatingPanel/MainPanelView.swift:1-470`; `NativeScheduler/Sources/NativeScheduler/Features/FloatingPanel/NotchView.swift:1-520`; `NativeScheduler/Sources/NativeScheduler/Shared/DesignSystem/DesignMetrics.swift:1-220`; `NativeScheduler/Tests/NativeSchedulerTests/NotchShellTests.swift:560-610,1200-1320`
  - Acceptance criteria: Both exact tests pass without assertion changes that weaken bounds/AX coverage; compact and expanded widths/heights remain within approved metrics; all real task fixtures are present at the padded accessibility child; reduce-motion behavior is preserved.
  - QA scenarios: `swift test --package-path NativeScheduler --filter NotchShellTests/testExpandedLayoutClampsMalformedSmallProposalsWithoutOverflow` and `--filter NotchShellTests/testExpandedMainPanelRendersEveryTaskEightFixtureAtTheRealPaddedChild`; screenshot/AX comparison at compact and expanded sizes. Evidence `<attemptDir>/task-7-native-scheduler-functional-recovery-realtime/`.
  - Commit: N | Repository has no HEAD and commit authorization was not given.

- [ ] 8. Prove the complete product through one exact app artifact
  - Recommended task executor category: `unspecified-high`
  - What to do / Must NOT do: Run the full clean verification on the frozen source tree, build one Xcode app artifact, then use that same hash for isolated and normal-profile GUI QA with no intervening rebuild. Drive shell, Tasks, folders/drag, Timer modes, Dayline compact/five-day/details, Settings/category/default, persistence relaunch, one bad-input/save-failure path where injectable, Settings/Quit menu, and lifecycle cleanup. Record PID/path/hash/store receipts. Leave only the final normal-profile app running. Must not count source inspection, static screenshots, smoke-only autostart, or a different binary as behavioral proof.
  - Parallelization: Wave 5 | Blocked by: 3, 5, 6, 7 | Blocks: F1-F4
  - References: every source/test file changed by Todos 1-7; `.omo/evidence/ulw/native-scheduler-functional-recovery-20260817/G001-outcome-the-current-nativescheduler/a1/C002/action-log.txt`; `AGENTS.md`
  - Acceptance criteria: LSP reports 0 errors/warnings on changed files; `swift test --package-path NativeScheduler` passes all tests once with zero failures; Xcode build exits 0; both profiles use identical artifact SHA-256; isolated QA proves every behavior and cleanup; normal-profile smoke preserves existing data and leaves the verified process running.
  - QA scenarios: `lsp_diagnostics`; full `swift test`; full `xcodebuild`; `osascript`/AX action driver plus `screencapture` for happy, bad input, persistence relaunch, and menu paths. Evidence `<attemptDir>/task-8-native-scheduler-functional-recovery-realtime/`.
  - Commit: N | Repository has no HEAD and commit authorization was not given.

## Final verification wave
> Runs in parallel after ALL todos. ALL must APPROVE. Surface results and wait for the user's explicit okay before declaring complete.
- [ ] F1. Plan compliance audit
  - Recommended task executor category: `unspecified-high`
  - Verify every Must have, Must NOT have, todo acceptance, evidence path, and cleanup receipt against the frozen source tree. APPROVE only with no missing behavior.
  - QA scenarios: Run `omo-agent-toolkit ulw-loop status --session-id native-scheduler-functional-recovery-realtime-20260817 --json` and parse every criterion/todo evidence reference; verify each referenced artifact exists, is non-empty, and is stamped with the frozen source manifest/hash from Todo 8. Read this plan and produce a checklist mapping every Must have/Must NOT have/Todo 1-8 acceptance clause to an artifact and observed result. Write `<attemptDir>/F1-plan-compliance.md`. APPROVE only when mapping coverage is 100%, all cleanup receipts exist, and there is no unstamped/stale/missing artifact.
- [ ] F2. Code quality review
  - Recommended task executor category: `deep`
  - Review persistence ordering, MainActor safety, publisher/tick ownership, error propagation, test determinism, performance, data safety, and absence of duplicate state/events. APPROVE only with no blocker/high/medium finding.
  - QA scenarios: Run `lsp_diagnostics` on every changed Swift file, `swift test --package-path NativeScheduler`, and the exact Todo 8 `xcodebuild` command; inspect the complete changed-file manifest and source for fire-and-forget saves, printed/swallowed errors, duplicate publishers/tickers, broad unfiltered notifications, fixed sleeps/polling, weakened tests, and user-store mutation. Write command transcripts and findings to `<attemptDir>/F2-code-quality.md`. APPROVE only when diagnostics are clean, both commands exit 0, tests report zero failures, and there are no blocker/high/medium findings.
- [ ] F3. Real manual QA
  - Recommended task executor category: `unspecified-high`
  - Independently drive the frozen exact app through isolated and normal-profile surfaces, compare artifact receipts, inspect screenshots/AX/logs, and APPROVE only when observed behavior matches every criterion.
  - QA scenarios: Verify Todo 8's Xcode app SHA-256, then launch that unchanged artifact with isolated `HOME=<attemptDir>/final-qa-home`. Through `osascript`/System Events drive: expand/collapse and `<`/`>` rail; exact Return task creation; complete/reopen/delete; folder create/rename/reorder/delete; item/cross-folder drag; Timer normal/duration/end-time start/pause/resume/category/stop/reset; Dayline compact/five-day/detail/live growth; Settings category/default and bad-input/failure surface; quit/relaunch persistence. Capture AX text after every state transition and screenshots per domain. Terminate only the isolated PID, launch the same hash under the normal profile, verify existing data counts and non-destructive shell/Tasks/Timer/Dayline/Settings smoke, and leave that PID running. Write `<attemptDir>/F3-real-manual-qa.md`, action log, screenshots, PID/path/hash/store receipts, before/after data counts, and cleanup receipt. APPROVE only when every expected state transition is observed and both profiles use the identical hash.
- [ ] F4. Scope fidelity
  - Recommended task executor category: `unspecified-high`
  - Confirm approved design and user data are preserved, no feature/test weakening or unrelated work entered the diff, and final app process is the exact reviewed artifact.
  - QA scenarios: Compare Todo 8's before/after source manifests and enumerate every changed path against Todos 1-7; inspect `NativeScheduler/Tests` for removed/skipped/weakened assertions; compare normal-profile Core Data entity counts and preferences before/after F3; compare compact/expanded screenshots against the approved baseline for rail, spacing, heights, settings midpoint, typography, and colors; run `ps -p <final-pid> -o pid=,command=` and `shasum -a 256 <reported-executable>` to match the reviewed artifact. Write `<attemptDir>/F4-scope-fidelity.md`. APPROVE only when every changed path is planned, no test is weakened, persisted counts/preferences are preserved except explicitly created-and-cleaned QA data, visual invariants match, and the final running PID/hash is exact.

## Commit strategy
- No commits. The repository has no HEAD and the user authorized implementation, not Git commits.
- Keep each todo's files and evidence isolated in the working tree; never stage or reset unrelated changes.

## Success criteria
- All accepted Codex-era Tasks, Timer, Dayline, Settings, shell, persistence, and lifecycle behaviors are observable in the exact final app.
- Task and Settings local mutations render by the next main-loop turn with deterministic confirmation/rollback; Timer model mutations publish before return and Dayline reflects relevant session revisions exactly once.
- Full Swift test suite has zero failures, changed-file LSP diagnostics are clean, and Xcode Debug build succeeds.
- Isolated and normal-profile QA use the same SHA-256 app artifact, preserve user data, record non-empty evidence, clean temporary processes/stores, and leave the verified normal-profile app running.
- F1-F4 all APPROVE with no unresolved blocker/high/medium finding.
