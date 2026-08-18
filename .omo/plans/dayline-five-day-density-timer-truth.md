# dayline-five-day-density-timer-truth - Work Plan

## TL;DR (For humans)
<!-- Fill this LAST, after the detailed plan below is written, so it summarizes the REAL plan. -->
<!-- Plain English for a non-engineer: NO file paths, NO todo numbers, NO wave/agent/tool names. -->

**What you'll get:** 기본 카테고리는 파란색으로 통일되고, Dayline을 펼쳤을 때만 오늘부터 최근 5일까지가 얇은 타임라인으로 보입니다. 타이머가 실제로 실행된 시간만 기록되며 창이 꺼지거나 앱이 재시작되어도 기록이 계속 늘어나는 오류를 막습니다.

**Why this approach:** 화면 바깥 크기는 유지하고 타이머 영역만 96pt로 압축해 Dayline에 높이를 돌려줍니다. 기록의 실행 여부는 불완전한 데이터 행이 아니라 현재 타이머가 소유한 세션 ID로 판단하고, 기존 종료시각 필드를 10초 체크포인트로 재사용해 스키마 변경과 초당 저장을 피합니다.

**What it will NOT do:** 5일을 넘는 탐색·통계 대시보드·기록 편집은 추가하지 않습니다. 외부 노치 창 크기, 할 일, 설정, Core Data 스키마와 배포 작업도 변경하지 않습니다.

**Effort:** Large
**Risk:** High - 타이머 수명주기·저장 실패·자정/DST와 96pt 고밀도 macOS UI를 같은 데이터 진실로 묶어야 합니다.
**Decisions to sanity-check:** 5일은 내부 Dayline 확장 때만 최신순으로 표시하고, 오래된 미종료 행은 삭제하지 않되 근거 없는 시간을 만들지 않도록 0초로 표시하며 복구 경고를 냅니다.

Your next move: 계획을 바로 실행하거나, 구현 전에 고정밀 계획 검토를 한 번 더 실행합니다. Full execution detail follows below.

---

> TL;DR (machine): Large/high-risk successor plan: fixed-shell 96pt timer density, expanded-only five-local-day Dayline, semantic default blue, timer-owned live authority, 10-second durable checkpoints, and exact-bundle lifecycle/visual gates.

## Scope
### Must have
- Treat this plan as the approved successor that absorbs the unfinished Task 8 and F1–F4 of `daily-time-narrative-redesign`; never mark the predecessor falsely complete. Rebind Boulder through an approved transfer record and make `product-hardening-efficiency-audit` depend on this successor.
- Keep `NotchGeometry.expandedPanelWidth/Height` at 816×384. Derive the actual `MainPanelView` proposal after `NotchView` padding; at the canonical 37pt notch it is 776×321.
- Keep collapsed Dayline as today's rolling eight hours. Fetch and render the recent five local calendar days only while the Dayline card's own disclosure is expanded.
- Expanded Dayline shows exactly five newest-first horizontal 24-hour rows (`Today` plus four locale dates), a shared `00 06 12 18 24` axis, per-day total, category color+pattern, empty days, one detail row, and today-only now/future/active semantics.
- Reserve exactly 96pt for the expanded timer/summary row and 6pt between it and Dayline; give all remaining right-column height to Dayline. Use expanded-only density: 8pt Dayline card inset, five 20pt day rows with 10pt tracks, text ≥11pt, and controls ≥24pt.
- Define `nsDefaultCategory = #4DABF7` as the category-identity fallback across timer chip/border, collapsed ring, Dayline, summary, and picker. Keep elapsed/untracked `#3A3A3A` and future `#252525` separate.
- Make `TimerViewModel.activeSessionID` the only in-process authority that lets a session extend to `asOf`. Create every timer session with `startTime == endTime`, checkpoint the same `endTime` no more than once per 10 seconds, and finalize every running→not-running transition at one captured timestamp.
- Make start, pause, stop, finish, reset, smoke reconfigure, category switch, quit, checkpoint, save failure, retry, crash/relaunch, and local-day rollover deterministic and testable with injected time/context/save seams.
- Preserve legacy nil-ended rows byte-for-byte. An unauthoritative nil end projects as `startTime` (zero duration), never grows, and surfaces a recoverable-data warning/count; it is never auto-deleted or rewritten.
- Use one fetch per reload for the current mode: one day while collapsed, one five-day range while expanded, plus `id == activeSessionID` inclusion. Ticks never fetch; only today reprojects each second.
- Pass SwiftPM/Xcode build and tests, save/fetch-frequency assertions, exact-app geometry and native interaction QA, accessibility/Reduce Motion checks, state isolation, cleanup, two visual reviews, and F1–F4 at one final recursive digest.

### Must NOT have (guardrails, anti-slop, scope boundaries)
- No outer shell resize, global scale transform, text below 11pt, actionable target below 24pt, scrolling, hidden day row, clipped timer control, or five full-size cards.
- No history outside the five visible days, date navigation, editable records, charts/goals/streaks, calendar/app tracking, analytics, new dependency, Core Data migration, or per-second save.
- Do not use `MultiDayHeatmapView`, `DailyLogReader`, 15-minute slots, or five independent fetches as Dayline truth.
- Do not infer live state from `SessionEntity.endTime == nil`; do not extend unauthoritative or legacy rows to the current time; do not silently delete or rewrite user history.
- Do not make a category switch with two timestamps/two saves, publish live authority before the initial checkpoint is durable, or clear a failed finalization reference before retry is possible.
- Do not change tasks, settings behavior, timer modes/inputs, notch hover/option locking, daily-log format, release/signing work, or activate `product-hardening-efficiency-audit` in parallel.
- Do not reuse predecessor PASS claims, stale screenshots, an assumed 384pt child height, or tests that manually imitate `TimerViewModel` instead of driving it.

## Verification strategy
> Zero human intervention - all verification is agent-executed.
- Test decision: TDD with XCTest. Each behavioral todo records a genuine failing assertion/missing contract before GREEN; UI composition adds an exact `NSHostingView` render/AX probe after model/layout tests.
- Evidence root: `ATTEMPT_ROOT=/Users/chan/Projects/native_schedular/.omo/evidence/start-work/dayline-five-day-density-timer-truth/aN`, resolved once to the first unused attempt and recorded in Boulder. Evidence: `$ATTEMPT_ROOT/task-<N>-*.{log,md,png,json}`.
- Source identity: Todo 1 creates a fresh recursive baseline manifest because the parent repository has no `HEAD`; exclusions are only `.omo/evidence/**`, `.omo/boulder.json`, the active plan/draft/transfer records, `NativeScheduler/.build/**`, `.swiftpm/**`, task-local DerivedData, and `.DS_Store`. Todo 9 freezes a final manifest; Todo 10 and F1–F4 must use that exact digest.
- Core commands: `rtk test swift test --package-path NativeScheduler`, `rtk swift build --package-path NativeScheduler`, and a clean `rtk xcodebuild -project NativeScheduler/NativeScheduler.xcodeproj -scheme NativeScheduler -configuration Debug -derivedDataPath <task-local> build`.
- Persistence tests use an in-memory store, injected clock, throwing save spy, and fetch/save counters. Native QA uses task-local `HOME`/`CFFIXED_USER_HOME`; production SQLite/WAL/SHM, logs, preferences, login item, TCC, and system settings must remain byte-identical.
- Failure policy: a failed test/build/QA lane cannot be checked off. Any source change after Todo 9 invalidates Todo 9, Todo 10, and all final-lane evidence.

## Execution strategy
### Parallel execution waves
> Target 5-8 todos per wave. Fewer than 3 (except the final) means you under-split.
- Wave 0: Todo 1 alone transfers plan ownership and freezes the fresh baseline; no product edit may precede it.
- Wave 1: Todos 2, 3, 4, and 6 may run in parallel only with their explicit disjoint file ownership. Their public handoff contract is fixed here: `TimerViewModel` publishes `activeSessionID`; `DayActivityStore` accepts that UUID as its live authority.
- Wave 2: Todos 5 and 7 run after timer/store contracts are green; their source owners are disjoint.
- Wave 3: Todo 8 composes the final UI after all upstream contracts; it runs alone because it touches shared view files.
- Wave 4: Todo 9 freezes all automated evidence, then Todo 10 alone owns the native app/visual surface.
- Final wave: F1 and F2 may review the frozen digest in parallel. F3 then owns native QA, and F4 starts after F3 cleanup. All must approve.

### Dependency matrix
| Todo | Depends on | Blocks | Can parallelize with |
| --- | --- | --- | --- |
| 1 | none | 2–7 | none |
| 2 | 1 | 8 | 3, 4, 6 |
| 3 | 1 | 8 | 2, 4, 6 |
| 4 | 1 | 5, 7 | 2, 3, 6 |
| 5 | 4 | 9 | 7 |
| 6 | 1 | 7, 8 | 2, 3, 4 |
| 7 | 4, 6 | 8, 9 | 5 |
| 8 | 2, 3, 6, 7 | 9 | none |
| 9 | 5, 7, 8 | 10, F1–F4 | none |
| 10 | 9 | F1–F4 | none |

## Todos
> Implementation + Test = ONE todo. Never separate.
<!-- APPEND TASK BATCHES BELOW THIS LINE WITH edit/apply_patch - never rewrite the headers above. -->
- [x] 1. Transfer the active Dayline work into this successor and capture a fresh baseline
  What to do / Must NOT do: Create an approved start-work transfer record stating that predecessor Task 8/F1–F4 are superseded and absorbed, not completed. Rebind Boulder through the start-work mechanism to this plan. Amend the queued hardening plan so its P0 depends on this successor and its persistence/termination tasks consume this plan's evidence instead of reimplementing it. Record a fresh complete source/config/design manifest and current 62-test inventory before any product edit. Do not hand-edit status to fabricate completion, activate hardening, stage/commit, or reuse predecessor PASS evidence.
  Parallelization: Wave 0 | Blocked by: none | Blocks: 2–7.
  References: `.omo/boulder.json`; `.omo/plans/daily-time-narrative-redesign.md` Task 8/F1–F4; `.omo/start-work/amendment-3.md`; `.omo/plans/product-hardening-efficiency-audit.md` P0/Todos 2,7; the current 40-file digest in the draft is diagnostic only.
  Acceptance criteria: Boulder points to this plan and a new attempt root; the signed/hashed transfer record names all carried criteria and leaves predecessor incomplete/superseded; hardening explicitly waits for this plan; recursive manifest and test inventory are reproducible; `rtk test swift test --package-path NativeScheduler` executes exactly the inventoried 62 baseline tests with 0 failures before edits.
  QA scenarios: happy — compare a second manifest calculation and prove identical digest; failure — a fixture that marks predecessor Task 8 complete or leaves hardening depending only on the predecessor must be rejected. Evidence: `$ATTEMPT_ROOT/task-1-transfer.md`, `task-1-baseline-manifest.txt`, `task-1-baseline-digest.txt`, `task-1-tests.log`.
  Commit: N | chore(plan): transfer predecessor ownership safely

- [x] 2. Lock the five-day/density design contract and real padded geometry with RED tests
  What to do / Must NOT do: Update `DESIGN.md` from current-day/three-lane semantics to expanded-only five-day semantics and the exact 96pt allocation. Add a test-visible layout probe and layout metrics using the real padded child proposal: width `816-40=776`; height `384-(notchHeight+10)-16`, canonical 321 at 37pt. Expanded uses 96pt timer/summary + 6pt gap + the remainder for Dayline; collapsed metrics remain byte-for-behavior compatible. Test notch heights 32, 37, and 42. Do not resize `NotchGeometry`, globally scale, or assume the child is 384pt tall.
  Parallelization: Wave 1 | Blocked by: 1 | Blocks: 8 | Parallel with: 3,4,6.
  References: `NotchGeometry.swift:4-9,44-47,92-99`; `NotchView.swift:71-85`; `MainPanelView.swift:21-78,146-194`; `NotchShellTests.swift:7-37`; `DESIGN.md:1-108`.
  Acceptance criteria: RED proves current 128pt/assumed-height contract fails. GREEN asserts canonical panel content is 776×321, expanded timer is exactly 96, Dayline receives `contentHeight-96-6`, every allocation sums without overflow for 32–42pt notches, and all collapsed metric assertions remain unchanged. `rtk test swift test --package-path NativeScheduler --filter NotchShellTests` passes.
  QA scenarios: happy — an `NSHostingView` probe reports the exact child proposal and metrics; failure — feed 776×384 or change outer shell constants and require test failure. Evidence: `$ATTEMPT_ROOT/task-2-red.log`, `task-2-layout.log`, `task-2-contract.diff`, `task-2-probe.json`.
  Commit: N | feat(layout): lock expanded density geometry

- [x] 3. Separate semantic default blue from gray timeline tracks
  What to do / Must NOT do: Define `Color.nsDefaultCategory` as exact sRGB `#4DABF7`; route nil, blank, and malformed category identity through it. Keep `nsDefaultSlot/daylineElapsedTrack #3A3A3A` and `nsFutureSlot/daylineFutureTrack #252525`. Update TimerView chip/popover/border, TimerViewModel theme, NotchTimerState/ring, Dayline blocks/swatches, Today summary, and default picker option to call the one category resolver. Persisted valid custom colors remain normalized but unchanged. Do not recolor empty/untracked/future tracks or derive the default from a palette array index.
  Parallelization: Wave 1 | Blocked by: 1 | Blocks: 8 | Parallel with: 2,4,6.
  References: `Colors.swift:4-33,62-74`; `TimerView.swift:73-94,250-305,470-490`; `TimerViewModel.swift:21-27`; `NotchTimerState.swift:4-8`; `HeatmapView.swift:627-708`; `TodayUsageSummaryView.swift:14-55,139-170`; `NotchShellTests.swift:38-61`.
  Acceptance criteria: failing-first assertions cover nil/blank/malformed, exact blue, valid custom colors, and gray track separation. A consumer matrix test proves timer border, compact ring, Dayline and summary resolve the same category hex. Focused tests and the full suite pass.
  QA scenarios: happy — render Default and a custom orange category and sample/assert the semantic colors; failure — force nil category and prove neither elapsed nor future track becomes blue. Evidence: `$ATTEMPT_ROOT/task-3-red.log`, `task-3-colors.log`, `task-3-consumer-matrix.json`.
  Commit: N | fix(theme): unify default category blue

- [x] 4. Make timer-owned session authority and 10-second checkpoints deterministic
  What to do / Must NOT do: Give `TimerViewModel` injected clock/context/throwing-save seams and `@Published private(set) activeSessionID`. On start, run engine validation, create one row at one captured instant with `startTime == endTime`, save synchronously, then publish authority; if save fails stop/revert the engine, publish a recording error, and never claim activity. While running, checkpoint the same row at thresholds 10,20,… seconds, never each tick. Pause/stop/finish/reset/smoke reconfigure clear live authority at one captured boundary, set exact end, and use one idempotent finalizer. A checkpoint failure keeps timer+authority and retries at the next threshold; a final failure keeps a pending reference/last durable checkpoint, clears authority, and publishes retryable error state/methods for Todo 8's control. Category switch uses one timestamp, creates `new.start == new.end == old.end`, saves once, then switches category/authority; failure rolls back the replacement and retains the old category/authority. Do not use `SessionEntity.isRunning` as new truth or enqueue finish finalization in a detached/unowned task.
  Parallelization: Wave 1 | Blocked by: 1 | Blocks: 5,7 | Parallel with: 2,3,6.
  References: `TimerViewModel.swift:7-34,82-188`; `TimerEngine.swift:48-132`; `CoreDataStack.swift:26-41`; `ManagedObjects.swift:34-52`; `TimerEngineTests.swift:1-270`.
  Acceptance criteria: TDD matrix proves durable start before authority; 9.9s causes no checkpoint and 10.0s causes one; 31s yields only start+3 checkpoint saves; every transition has one exact end; pause/resume excludes paused time; repeated finalization is idempotent; category boundary has no gap/overlap and one save; create/checkpoint/final/category failure policies and retryable model state match above; no production per-second save remains.
  QA scenarios: happy — in-memory Core Data + fake clock drives a 25s run, pause/resume, category switch and stop with exact rows/save counts; failure — throwing save spy at each boundary proves no false authority, dual row, data deletion, or unbounded growth. Evidence: `$ATTEMPT_ROOT/task-4-red.log`, `task-4-focused.log`, `task-4-save-counts.json`, `task-4-failures.log`.
  Commit: N | fix(timer): persist authoritative bounded sessions

- [x] 5. Order termination before logging and bound every mounted legacy duration consumer
  What to do / Must NOT do: Add `FloatingPanelController.prepareForTermination()` that asks the timer finalizer to save synchronously before `flushDailyLog()`. Quit gets one bounded immediate retry; if both saves fail, clear live authority, restore the row to its last durable checkpoint, record the failure, and terminate without fabricating later time. Change the mounted daily-log calculation so unauthoritative nil ends cap at `startTime`; preserve rows and log format. Prove old `HeatmapViewModel`/`MultiDayHeatmapView` are unmounted; if any mounted `end ?? now` duration consumer exists, apply the same cap. Do not await indefinite work during termination or call the log before the timer result.
  Parallelization: Wave 2 | Blocked by: 4 | Blocks: 9 | Parallel with: 7.
  References: `AppDelegate.swift:28-34`; `FloatingPanelController.swift:54-98`; `ManagedObjects.swift:34-64`; all `rtk rg -n 'endTime \\?\\? Date|end \\?\\? asOf|end \\?\\? now' NativeScheduler/Sources` results; queued hardening Todos 2/7.
  Acceptance criteria: tests prove final save precedes log read, one retry only, successful quit records exact end, double failure logs only through last durable checkpoint, arbitrary nil row contributes zero, and raw Core Data row remains byte-equivalent. No mounted production consumer extends an unauthoritative nil row.
  QA scenarios: happy — smoke timer quits between checkpoints and reopened store/log end at quit time; failure — force both quit saves to fail and prove reopen/log stop at previous checkpoint with a recorded non-secret error. Evidence: `$ATTEMPT_ROOT/task-5-red.log`, `task-5-termination.log`, `task-5-consumer-audit.txt`, `task-5-reopen.json`.
  Commit: N | fix(lifecycle): finalize before daily logging

- [x] 6. Extend the single store into an expanded-only five-local-day window
  What to do / Must NOT do: Reuse the existing pure overlap projector and `DayActivityStore`; do not build the legacy grid or five stores. Add a window value containing exactly five newest-first day snapshots. Compute dates with Calendar day arithmetic, range `[startOfDay(today-4), nextDayStart(today))`, and fetch once per reload with normal overlap OR `id == activeSessionID`. While collapsed retain/fetch only today. When the internal Dayline toggle expands, lazily fetch the range; when it collapses retain today's snapshot and release historical cache. On ticks reproject only today; older four snapshots remain equal/stable. Relevant save performs one current-mode fetch; unrelated save none; rollover performs one new window fetch. Day-qualified segment identity includes dayStart. Unauthoritative nil end equals start and adds recovery warning/count without row mutation.
  Parallelization: Wave 1 | Blocked by: 1 | Blocks: 7,8 | Parallel with: 2,3,4.
  References: `HeatmapViewModel.swift:190-500`; `HeatmapLiveTests.swift:37-490`; `MultiDayHeatmapView.swift:1-19,255-266`; `ManagedObjects.swift:34-64`; `DESIGN.md` data truth.
  Acceptance criteria: RED/GREEN covers five exact dates/newest-first, empty middle day, one range fetch, zero tick fetch, one relevant-save/checkpoint fetch, unrelated save zero, rollover one, current active OR-query inclusion, cross-midnight split, overlap totals, 23h/25h days, only today's snapshot changing, stable historic IDs, same-window failure retention, rollover failure exact-date fallback, recovery clearing, and legacy nil zero-duration warning.
  QA scenarios: happy — in-memory sessions across five dates generate exact per-day totals with only today ticking; failure — omit active-ID OR clause at midnight and require the cross-boundary test to fail. Evidence: `$ATTEMPT_ROOT/task-6-red.log`, `task-6-window.log`, `task-6-fetch-counts.json`, `task-6-dst.log`.
  Commit: N | feat(dayline): project five local days once

- [x] 7. Wire timer authority, expansion state, persistence and Dayline in one integration test
  What to do / Must NOT do: `MainPanelView` passes `timerVM.activeSessionID` into its single `DayActivityStore` and toggles the store's five-day mode only from the Dayline card disclosure. `TodayUsageSummaryView` always receives today's snapshot, never a five-day aggregate. Add a real cross-boundary XCTest that instantiates TimerViewModel, in-memory Core Data, fake clock/save spy and DayActivityStore; it must start the actual timer VM rather than manually insert rows. Do not create a second ticker/store, load history merely because the outer notch opens, or duplicate projection logic in the view.
  Parallelization: Wave 2 | Blocked by: 4,6 | Blocks: 8,9 | Parallel with: 5.
  References: `MainPanelView.swift:5-78,127-135`; `TimerViewModel.swift`; `HeatmapViewModel.swift`; `HeatmapLiveTests.swift:318-360` (existing mimic test to replace/supplement); `TodayUsageSummaryView.swift:67-117`.
  Acceptance criteria: integration test proves start grows today once per second without refetch, 10s checkpoint triggers at most one reload, pause freezes immediately, resume creates a new segment excluding pause, category switch is atomic, collapse releases history, re-expand fetches once, crash/relaunch caps at last checkpoint, and arbitrary nil row never grows.
  QA scenarios: happy — drive 12s fake time through the actual VM/store and assert published snapshots plus persisted values; failure — clear activeSessionID while leaving a row nil/open and prove the UI remains frozen with warning. Evidence: `$ATTEMPT_ROOT/task-7-red.log`, `task-7-integration.log`, `task-7-publication.json`.
  Commit: N | test(dayline): lock timer-to-history truth

- [x] 8. Render five thin lanes and the 96pt timer/summary surface without clipping
  What to do / Must NOT do: Replace the expanded three same-day ranges with five rows: `Today`, then four locale weekday+month/day labels, each per-day total, 10pt track inside a 20pt row, common `00 06 12 18 24` axis, and a single-line detail. Historical rows have elapsed+category only; today alone has future track, now marker and Active. Use day-qualified interaction IDs and AX order header→toggle→newest through oldest. Expanded Dayline inset is 8pt. Reflow TimerView only in the Dayline-expanded state to 48pt time box, 60pt primary row, 4pt row gap, 24pt secondary controls and 4pt vertical insets; collapsed TimerView stays unchanged. Render the retryable recording error as a 24pt warning/retry control with label/help and keyboard action. Reflow Today summary within 96pt using its existing ring and at most top three categories plus `Etc`; it remains today-only. No scroll, clipping, global scaling, hidden meaning, or subminimum text/hit targets.
  Parallelization: Wave 3 | Blocked by: 2,3,6,7 | Blocks: 9 | Parallel with: none.
  References: `HeatmapView.swift:222-287,470-718`; `MainPanelView.swift:21-78,146-194`; `TimerView.swift:5-70,96-180,250-305,380-490`; `TodayUsageSummaryView.swift:14-180`; `HeatmapSlotTests.swift:48-290`; `NotchShellTests.swift`.
  Acceptance criteria: layout/semantic tests assert five 20pt rows, 10pt tracks, shared axis, correct dates/totals/states/order, 96pt timer/summary, unchanged collapsed allocations, ≥11pt meaningful text and ≥24pt actions. Exact `NSHostingView` captures at 776×321 show all five rows, timer controls, summary and detail with zero overlap/truncation in empty/default/custom/many-category and DST fixtures.
  QA scenarios: happy — pointer pin, keyboard focus/activate, collapse/re-expand, and Reduce Motion preserve selection rules and labels; failure — render at notch heights 32/42 and fail on missing row, clipped control, aggregate-labelled-as-today, blue gray-track, or AX order drift. Evidence: `$ATTEMPT_ROOT/task-8-red.log`, `task-8-layout.json`, `task-8-empty.png`, `task-8-active.png`, `task-8-many-categories.png`, `task-8-ax.json`.
  Commit: N | feat(dayline): fit five-day history into expanded shell

- [x] 9. Freeze the source and pass automated correctness/resource gates
  What to do / Must NOT do: Run focused and complete SwiftPM tests, clean SwiftPM build, clean Xcode Debug build, source-string audits, and deterministic resource checks at one recursive digest. Assert timer saves are bounded by initial + `floor(elapsed/10)` + final (plus atomic category boundaries), one fetch per relevant save at most, no history ticker while collapsed, and historical snapshots do not churn. Update test inventory. Do not accept projector-only tests, ignored failures, stale DerivedData, or evidence from another digest.
  Parallelization: Wave 4 | Blocked by: 5,7,8 | Blocks: 10,F1–F4 | Parallel with: none.
  References: all changed source/tests; `NativeScheduler/Package.swift`; `NativeScheduler/NativeScheduler.xcodeproj`; Todo 1 manifest rules.
  Acceptance criteria: all named focused suites and the complete updated XCTest inventory pass; `rtk swift build --package-path NativeScheduler` and clean `rtk xcodebuild ... build` exit 0; `rtk rg` finds no mounted `endTime ?? Date()/asOf` live inference, no per-second save, and no production three-lane expanded path; final manifest/digest is internally reproducible.
  QA scenarios: happy — 61s fake run meets exact save/fetch counts and memory snapshot identities; failure — inject a one-second save or historical mutation and require the resource assertion to fail. Evidence: `$ATTEMPT_ROOT/task-9-focused.log`, `task-9-full-tests.log`, `task-9-build.log`, `task-9-xcode.log`, `task-9-resource.json`, `task-9-final-manifest.txt`, `task-9-final-digest.txt`.
  Commit: N | test(gate): freeze five-day timer truth

- [x] 10. Observe the exact app working across pointer, lifecycle, visual and restart surfaces
  What to do / Must NOT do: Build a fresh exact bundle into task-local DerivedData and launch with isolated HOME/store/preferences. Bind screenshots and AX/pointer actions to its PID/window. Incorporate the 2026-08-12 user layout feedback before the final exact-app pass: the 90-degree Dayline disclosure must remain visibly centered between the Dayline and timer cards, use the requested native AppKit `NSButton` path so real pointer/AXPress invokes its action through the overlapped seam, and toggle compact/expanded state; reduce the lower timer/summary row below the prior 96pt allocation and return the reclaimed height to Dayline while keeping every control visible and at least 24pt. The shell menu remains a 22×22 circle and must not reserve or stretch right-column height. Verify outer hover/options/category popover lock remains, then inspect compact Dayline, expanded five rows, the reduced timer/summary row, default/custom color propagation, timer live tick, 10s checkpoint, pause/stop/category switch, quit/relaunch/crash cap, empty/DST/many-category states, keyboard/VoiceOver labels and Reduce Motion. Capture the runtime layout probe proving the actual child proposal. Do not modify TCC/System Settings, any AVD, or user production state.
  Parallelization: Wave 4 | Blocked by: 9 | Blocks: F1–F4 | Parallel with: none.
  References: Todo 9 digest; `NotchView.swift`; `NotchWindow.swift`; `MainPanelView.swift`; QA isolation/cleanup rules above.
  Acceptance criteria: exact-bundle evidence observes all requested behaviors; the inter-card disclosure is visible and an actual pointer/AX press expands and collapses Dayline; all five lanes and every timer control are visible after the timer-row reduction; the shell gear is circular rather than vertically stretched; mouse exit stays locked while options/popover is active; pause freezes immediately; forced relaunch never grows beyond last checkpoint; production state hashes are unchanged; owned app/helper processes, temp homes and DerivedData are cleaned.
  QA scenarios: happy — press the visible inter-card disclosure, capture both compact and expanded states, then run Default timer ≥12s and observe bounded blue history with the shorter timer row; failure — reject a build where the disclosure is visible but does not change state, is covered by either card, the gear becomes a vertical pill, or the timer row still starves Dayline; kill after a checkpoint, relaunch later and prove no offline extension; move pointer into category/options surfaces and prove panel stays expanded. Evidence: `$ATTEMPT_ROOT/task-10-native-qa.md`, `task-10-layout-probe.json`, `task-10-compact.png`, `task-10-expanded.png`, `task-10-relaunch.json`, `task-10-cleanup.txt`.
  Commit: N | test(native): verify exact expanded Dayline

## Final verification wave
> Runs in parallel after ALL todos. ALL must APPROVE. Surface results and wait for the user's explicit okay before declaring complete.
- [ ] F1. Plan compliance audit
- [ ] F2. Code quality review
- [ ] F3. Real manual QA
- [ ] F4. Scope fidelity

F1: an independent gate reviewer maps every Must/Must-NOT and Todo acceptance item to fresh evidence at Todo 9's digest; predecessor transfer and queued-hardening dependency must be correct. Evidence: `$ATTEMPT_ROOT/F1-plan-compliance.md`.

F2: an independent reviewer audits all changed Swift/tests for MainActor/Core Data correctness, clock/save injection, idempotent lifecycle, failure truthfulness, DST/calendar math, accessibility, duplicated responsibility and unused code. No unresolved high/medium finding. Evidence: `$ATTEMPT_ROOT/F2-code-quality.md`.

F3: a fresh QA executor independently rebuilds and repeats exact-app compact/expanded, pointer lock, timer/checkpoint/pause/relaunch, default/custom colors, five dates, AX/keyboard/Reduce Motion and isolation cleanup. Evidence: `$ATTEMPT_ROOT/F3-real-qa.md`.

F4: an independent scope/manifest reviewer proves the final recursive digest matches F1–F3, outer shell/Core Data schema/tasks/settings/release surfaces were not changed, legacy rows were preserved, and no unowned file/state drift occurred. Evidence: `$ATTEMPT_ROOT/F4-scope-manifest.md`.

## Commit strategy
- Do not stage or commit: the parent repository has no `HEAD` and project files are untracked user data.
- Every implementation todo owns only the paths named in its references/acceptance; record pre/post hashes. Parallel writers must be disjoint, and any overlap forces serialization.
- No broad formatter, project regeneration, dependency addition, unrelated cleanup, or hardening/release work.

## Success criteria
- Default/no-category identity is exact `#4DABF7` across timer border/chip, collapsed notch ring, Dayline, summary and picker; elapsed and future tracks remain their gray roles.
- Compact Dayline remains today's rolling eight-hour view. Only its internal expanded state fetches and shows exactly five newest-first local days with all rows, totals, category patterns, shared axis, detail and accessible order visible in the fixed shell.
- The canonical expanded child proposal is measured, timer/summary is exactly 96pt, Dayline gets the remainder, and 32–42pt notch heights render without clipping, scrolling, global scale, small text or undersized controls.
- Only an active `TimerViewModel.activeSessionID` grows to `asOf`; initial/end checkpoints are durable, saves occur no more than every 10 seconds while running, and all transitions/category boundaries/quit are exact and idempotent.
- Save failures never publish false recording, create overlapping authority, delete history, or cause offline growth. Legacy nil-ended rows stay unchanged, display zero duration with recovery warning, and daily logs never extend them.
- Five-day data uses one range fetch per reload; ticks do not fetch; only today changes each second; local-day rollover, cross-midnight sessions, empty days, overlap normalization, 23/25-hour days and recovery errors pass real integration tests.
- SwiftPM and Xcode builds/tests, deterministic save/fetch resource assertions, exact-app native QA, two visual reviews and F1–F4 all approve one final recursive digest while production state and system settings remain unchanged.
- The predecessor is truthfully transferred, the hardening plan waits on this successor, and no hardening, signing, notarization, DMG or Mac App Store work runs in parallel.
