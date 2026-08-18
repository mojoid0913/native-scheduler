---
slug: daily-time-narrative-redesign
status: review-approved
phase: review_complete
intent: unclear
review_required: true
plan_path: .omo/plans/daily-time-narrative-redesign.md
plan_sha256: c77214177678db0fb9713aab0b54df2ca2762614c56c617052fddfcdc9532d64
review_round_id: 1423a1c8-017e-4476-8595-0ef3f7efa577
round_status: approved
completion_cas: [status=in_flight, workspace_root, runtime_home, target, launch_id, round_id, plan_sha256, session, receipt_identity=session, live_plan_sha256=plan_sha256, echoed_binding, terminal_transition=in_flight->approved|changes_requested|inconclusive]
pending-action: execute .omo/plans/daily-time-narrative-redesign.md
review:
  momus:
    status: approved
    workspace_root: /Users/chan/Projects/native_schedular
    runtime_home: null
    target: .omo/plans/daily-time-narrative-redesign.md
    round_id: 1423a1c8-017e-4476-8595-0ef3f7efa577
    plan_sha256: c77214177678db0fb9713aab0b54df2ca2762614c56c617052fddfcdc9532d64
    launch_id: 68b4e94d-21eb-483e-abc5-c7751eddb945
    session: /root/dayline_momus_round8
    result: OKAY
  independent:
    status: approved
    workspace_root: /private/tmp/native-scheduler-dayline-review-r8.1QraQ9
    runtime_home: /private/tmp/native-scheduler-dayline-codex-home-r8.5i5t1G
    target: .omo/plans/daily-time-narrative-redesign.md
    round_id: 1423a1c8-017e-4476-8595-0ef3f7efa577
    plan_sha256: c77214177678db0fb9713aab0b54df2ca2762614c56c617052fddfcdc9532d64
    launch_id: 63d9282e-2be9-400c-be34-2f3aceaad243
    session: codex:019fc874-1e3a-7bd1-9165-b6ea42ddb7fb; exec:51733
    result: OKAY
approach: Replace the 96-cell checkerboard with a responsive current-day Dayline that renders exact timer sessions as category-colored time blocks, keeps a plain-language current/recent detail visible, and reuses one day snapshot for the timeline and category summary.
---

# Draft: daily-time-narrative-redesign

## Components (topology ledger)
<!-- Lock the SHAPE before depth. One row per top-level component that can succeed or fail independently. -->
<!-- id | outcome (one line) | status: active|deferred | evidence path -->

| id | outcome | status | evidence path |
|---|---|---|---|
| C1 | The existing design contract is revised from a 96-cell heatmap to a named `Dayline / 오늘의 흐름` primitive with responsive, motion, contrast, and accessibility states. | active | `DESIGN.md`; `.omo/frontend-design/state.md` |
| C2 | A single current-day activity snapshot fetches exact `SessionEntity` ranges once, deterministically normalizes overlaps, and provides both chronological segments and category totals. | active | `NativeScheduler/Sources/NativeScheduler/Models/ManagedObjects.swift`; current `HeatmapViewModel.swift`; new model tests |
| C3 | The compact panel shows one rolling eight-hour lane; the expanded panel shows three fixed eight-hour lanes, each with category blocks, past/future track distinction, now marker, and a visible current/recent detail. | active | current `HeatmapView.swift`; `MainPanelView.swift`; fresh visual evidence |
| C4 | The panel header owns the full-day/nearby-hours toggle, removes the ambiguous standalone capsule, preserves category-color continuity, and shares the new snapshot with the existing category summary. | active | `MainPanelView.swift`; `TodayUsageSummaryView.swift`; exact-bundle native QA |
| C5 | Unit, build, accessibility, resize, reduced-motion, empty/live/midnight, and real pointer/keyboard QA prove the replacement without relying on screenshots or self-report alone. | active | `NativeScheduler/Tests/NativeSchedulerTests`; `.omo/evidence/daily-time-narrative-redesign/` |

## Open assumptions (announced defaults)
<!-- Intent is UNCLEAR: research resolves ambiguity, defaults are adopted (not asked), and each is surfaced in the plan's human TL;DR for veto. -->
<!-- assumption | adopted default | rationale | reversible? -->

| assumption | adopted default | rationale | reversible? |
|---|---|---|---|
| Product role of the board | Treat it as a quiet reflection layer after the primary `task → category → timer` journey, not as another primary control. | The live panel gives most area and contrast to tasks/timer; the current board is small and secondary. | yes |
| Replacement archetype | Use a chronological Dayline, not a ring, chart dashboard, activity list, or another heatmap. | Daily continuity and start/end order matter; shipped time trackers use timelines for day views and reserve heatmaps for longer-range patterns. | yes |
| Data fidelity | Render exact Core Data session start/end ranges, clipped to the current calendar day, instead of retaining dominant 15-minute cells as the UI source. | The repository already stores exact ranges, and a continuous timeline should not imply false 15-minute boundaries. No schema migration is needed. | yes |
| Overlapping bad data | Partition at session boundaries and let the most recently started session win each overlap interval; never mutate stored sessions. | This matches category switching semantics and makes corrupted/legacy overlaps deterministic without hiding or deleting user data. | yes |
| Compact layout | Show a rolling eight-hour lane centered around context (two elapsed hours plus the current and five upcoming hours), with two-hour ticks. | It preserves the existing compact-window intent while removing the unreadable 8×3 matrix. | yes |
| Expanded layout | Show the full day as three stacked lanes: `00–08`, `08–16`, `16–24`. | Three lanes make hour mapping readable inside the existing ~520×126 card without horizontal scrolling. | yes |
| Always-visible meaning | Default the detail row to the active session, otherwise the most recent session; hover/focus/click may inspect another block but is never required to understand the card. | USWDS warns that hover-required visualizations exclude users and add cognitive cost. | yes |
| Summary | Keep the expanded category ring/list, but feed it from the same day snapshot; compact header shows `Today · total tracked`. | Retains useful proportion context without making a ring the primary chronology view or duplicating Core Data aggregation. | yes |
| Expansion control | Move the toggle into the Dayline header as a labelled native icon button and remove the standalone vertical capsule. | The existing capsule has no visible meaning and consumes a full column; the header control keeps cause and effect together. | yes |
| Visual language | Preserve the black/#111 restrained shell and category hue continuity; add named timeline past/future/selected tokens in `DESIGN.md` before code. | Existing brand identity is coherent; the problem is information form, not the palette. | yes |
| Motion | Only crossfade selection/category changes and update the live endpoint/now marker without decorative pulse; disable nonessential transition under Reduce Motion. | Motion must express state and remain comfortable in a persistent notch surface. | yes |
| History/editing | Current day is the complete scope; do not add past-day navigation, drag editing, goals, automatic app tracking, or calendar integration. | `MultiDayHeatmapView` history is an unused stub and these are separate product capabilities. | yes |

## Findings (cited - path:lines)

- The production composition is `MainPanelView`: the board sits above the timer, compact at timer width and expanded to at most about 62%/520pt; expansion also reveals `TodayUsageSummaryView` (`NativeScheduler/Sources/NativeScheduler/Features/FloatingPanel/MainPanelView.swift:14-68`).
- The current compact board is an eight-hour × three-row matrix; the expanded board is 24 hours × four 15-minute rows, with sparse labels, a thin now marker, and meaning hidden mainly in `.help` (`NativeScheduler/Sources/NativeScheduler/Features/Heatmap/HeatmapView.swift:18-31,33-69,72-153`).
- The inspected native capture shows mostly uniform gray cells, a dominant white now line, no visible total/legend, and only a tiny category-colored cell, so the board reads as texture rather than a day narrative (`.omo/evidence/ulw/hover-option-pin-20260802-a1/G001-omo-ulw-loop/a1/manualQa/root-after-selection-expanded.png`).
- Exact session data already exists as `startTime`, optional `endTime`, and optional category; category changes split a running timer into a new session (`NativeScheduler/Sources/NativeScheduler/Models/ManagedObjects.swift:34-64`; `NativeScheduler/Sources/NativeScheduler/Features/Timer/TimerViewModel.swift:98-107,135-149,184-188`).
- Current heatmap reload performs one fetch for every slot, while compact non-15-minute rendering fetches again from view-driven calls; it also observes every context save (`NativeScheduler/Sources/NativeScheduler/Features/Heatmap/HeatmapViewModel.swift:46-66,99-122,172-184`).
- The category summary independently repeats slot-by-slot aggregation and its own timer/observer, so a shared day snapshot can remove duplicated work (`NativeScheduler/Sources/NativeScheduler/Features/Heatmap/TodayUsageSummaryView.swift:17-56,104-118,182-184`).
- `MultiDayHeatmapView` is not called by production and its historical loader clears the view then stops at a TODO; it is not a valid foundation for this replacement (`NativeScheduler/Sources/NativeScheduler/Features/Heatmap/MultiDayHeatmapView.swift:4-17,255-266`; `feedback.md:318-320`).
- Existing live tests already protect open-session growth, closed-session stability, and midnight rollover, and can be migrated to the day-snapshot contract (`NativeScheduler/Tests/NativeSchedulerTests/HeatmapLiveTests.swift:35-107`).
- Rize separates daily work into a customizable timeline and uses heatmaps for month-level pattern recognition: https://rize.io/changelog/new-calendar-home-views
- Timing groups related blocks into an intelligent daily timeline, and Toggl/Clockify both visualize a day as time blocks rather than a same-weight cell matrix: https://timingapp.com/?lang=en ; https://support.toggl.com/en-us/article/the-timeline-feature-1txzwm1/ ; https://clockify.me/features/calendar
- Structured makes the daily timeline its primary day-planning surface and couples time, duration, color, and icons for glanceability: https://help.structured.app/en/articles/380546
- USWDS recommends one central idea, visible labels/context, underlying textual access, and no required hover; WCAG 1.4.1 requires a visible alternative to color: https://designsystem.digital.gov/components/data-visualizations/ ; https://www.w3.org/WAI/WCAG20/Understanding/use-of-color

## Decisions (with rationale)

- **Direction name:** `Dayline / 오늘의 흐름`. It communicates chronology in plain language and avoids the analytics-heavy implication of “heatmap.”
- **Compact anatomy:** `Today · <total>` header + expand button; one rolling eight-hour track; two-hour tick labels; category blocks; now marker; one detail line such as `Study · 13:05–13:42 · 37m`.
- **Expanded anatomy:** the same header + collapse button; three labelled eight-hour tracks; a shared detail line; the existing category ring/list remains below beside the timer.
- **Track semantics:** elapsed-but-untracked, future, category session, active/selected session, and now marker are separate named states. Category color is always paired with visible current/recent text and VoiceOver labels; short blocks need no cramped inline text.
- **Interaction:** active or most recent block is selected by default. Pointer hover, click, and keyboard focus may change the detail line. Escape/blur returns to the active/recent default. Timeline reading must succeed without interaction.
- **Data:** fetch sessions overlapping the current day once, clip to day bounds, normalize overlaps without writing data, derive chronological segments and category totals from the same immutable snapshot, and update the active endpoint on a one-second clock. A new day replaces the snapshot and clears yesterday.
- **Retirement:** production no longer instantiates the current heatmap model/view. Remove or explicitly retire the unused multi-day heatmap stub only when no references remain; do not build its unfinished historical path.
- **Verification:** tests-after for pure projection/normalization/layout because behavior is being redesigned, plus existing regression suites, fresh Xcode build, exact-bundle native QA at compact/full widths, keyboard/VoiceOver labels, Reduce Motion, and dual visual QA.

## Scope IN

- Revise `DESIGN.md` and the frontend design-state constraints before implementation.
- Replace the current-day checkerboard and its ambiguous standalone toggle with the Dayline surface.
- Build one current-day session snapshot shared by the Dayline and category summary.
- Preserve timer/category color continuity, tasks, timer controls, notch geometry, settings, and normal hover expansion.
- Cover no-activity, one session, many categories, active session, default/no-category, overlap, midnight/DST, compact/expanded resize, keyboard/VoiceOver, and Reduce Motion states.
- Produce exact-bundle build/runtime provenance, stills plus a short interaction capture, and objective visual/design review artifacts.

## Scope OUT (Must NOT have)

- No historical day/week/month UI, multi-day persistence repair, calendar import, automatic app tracking, goals, streaks, coaching, billing, or analytics dashboard.
- No drag-to-edit, resize-to-edit, or mutation of stored sessions from the Dayline.
- No Core Data schema migration and no new dependency/chart library; use native SwiftUI/AppKit primitives.
- No redesign of tasks, timer input, category editor, notch shell geometry, or collapsed progress ring.
- No hover-only meaning, color-only category distinction, decorative pulse, horizontal scrolling, or tiny inline labels forced into short blocks.
- No use of framesmith, Figma bridge tooling, canvas adapters, or `canvas_evaluate`.
- Preserve unrelated user/untracked workspace files; the repository is unborn/dirty and work must be scoped to named paths only.

## Open questions

None. All open choices above are reversible product/UI defaults; the user can veto any one at the approval gate.

## High-accuracy review history

- Round `3b567660-d8d3-4ae9-a112-685cf5235f70` reviewed plan digest `22f370cc1e8ea7488d990680c4a96718fce0823d6744e2a74f1805ea8f85923c` and is invalidated.
- Native Momus receipt `/root/dayline_momus_round1`, launch `6ae0d48e-5604-4c83-816d-cfcd912350bc`: `INCONCLUSIVE` before content review because the required local `rtk` wrapper was unavailable. Next round explicitly permits raw read-only descriptor commands when `rtk` is absent.
- Independent Codex receipt `codex:019fc83d-89bb-78a1-852f-2465c7a24591; exec:44545`, launch `536fce0a-7b68-4362-9d14-601442fce3d6`: descriptor/digest binding passed, then `CHANGES_REQUESTED`. Durable result: `.omo/evidence/plan-review/daily-time-narrative-redesign/round-1-independent.txt` (SHA-256 `2b0874e5f0072b569524de74f147bf874324a519aa7b3d604bf1cfae37c7836d`).
- Fix summary: serialize baseline/preflight before edits; force task-local build outputs; resolve a single attempt root; lock overlap predicate/half-open and rollover-failure behavior; remove duplicate Settings reload; separate AX and keyboard order; disambiguate repeated-hour labels; preflight all TCC capabilities; use a fixed-snapshot host instead of mutating user persistence; make F4 build independently and final lanes reject-only; remove the undefined full-width indicator.
- Round `e527867a-d43c-4523-8525-08aaabdd3dbd` targeted digest `c7744f086c759ac012cd4dc30ae0c1ed33c5f0b28db7cf79e35f818fa586049a` and is invalidated without a plan change. Native Momus `/root/dayline_momus_round2` returned `OKAY`; independent Codex `codex:019fc849-7686-7ef1-86b7-967e71cb1ed3; exec:91482` returned `INCONCLUSIVE` before reading because the persisted `/tmp/...` workspace literal canonicalized to `/private/tmp/...`. Durable result: `.omo/evidence/plan-review/daily-time-narrative-redesign/round-2-independent.txt` (SHA-256 `14c455a888bbaacb1a00d607144b91ca11649059752e1e7b17ee24e67f8b7362`). Next round persists and dispatches the literal `/private/tmp/...` canonical roots.
- Round `257953c1-4660-4c96-8584-513fde03b613` reviewed digest `c7744f086c759ac012cd4dc30ae0c1ed33c5f0b28db7cf79e35f818fa586049a` and is invalidated. Momus `/root/dayline_momus_round3` requested removal of exact-app timer/category mutations because they permanently write the user's fixed SQLite store and no deletion/isolated-store path exists. Independent Codex `codex:019fc84c-27bd-7430-8ef1-3aadd8d90252; exec:9304` returned `INCONCLUSIVE` before descriptor opening because its first shell heredoc was blocked in the read-only sandbox. Durable result: `.omo/evidence/plan-review/daily-time-narrative-redesign/round-3-independent.txt` (SHA-256 `2762dd5787f5fe098addea8b98a02ce0e41c53917ef381cba9472353d18c2bb6`). Fix: exact-app QA is persistence-read-only; in-memory context/fixed host proves session-save behavior. Next independent prompt mandates inline `python3 -c` descriptor validation and forbids heredocs.
- Round `d172dab4-c631-4987-a829-e15612532b2d` reviewed digest `0a3934e257accf9e85c3d3552071c45049ca07e3bdcaabeb43c4522ab9bc15b8` and requested changes. Momus `/root/dayline_momus_round4` found normal first launch can register a login item/write `didRegisterLaunchAtLogin`; the fix mandates volatile `-didRegisterLaunchAtLogin YES`, persistence/login-state hashing, and SIGKILL cleanup. Independent Codex `codex:019fc851-0234-7953-8625-d9dfc4f1ed7a; exec:48975` verified the descriptor/hash and requested full-plan reruns per attempt, snapshot-owned time/calendar inputs, serial source writers, and exclusive native QA. Durable result: `.omo/evidence/plan-review/daily-time-narrative-redesign/round-4-independent.txt` (SHA-256 `7cfe392084c6e399bd5aa54d910bf7976fc5d341c3d7a68fab1a4e0c6955a5e2`). All corrections are incorporated for a fresh round.
- Round `ec2e833e-ffa6-4d09-90ce-15afea1f0211` reviewed digest `11865f0bb237545ce45a31233fdffa3cfe293c8b4140fad3d297be5b87e5c108`. Momus `/root/dayline_momus_round5` returned `OKAY`. Independent Codex `codex:019fc859-a013-70a2-b264-c7ac61c4eaea; exec:63017` verified the descriptor/hash and requested a byte-complete pristine restoration path for fresh RED attempts, snapshot-locale-bound summary sorting, and moving deferred integrated category-save QA from Todo 5 into Todo 6. Durable result: `.omo/evidence/plan-review/daily-time-narrative-redesign/round-5-independent.txt` (SHA-256 `20d926d02ee7ac1504ac9d47d8876559cf9e04512bbd43a2e55080d2ead0ec07`). All corrections are incorporated for a fresh round.
- Round `4c834ff7-5b03-4fff-bccd-5d0212223454` reviewed digest `7bf4420b6ee9f927af8100b73110c1fd6674595ecdb366ade7bd2001a44d6134` and requested changes. Momus `/root/dayline_momus_round6` required crash-safe recovery for a task that partially edits before owner completion. Independent Codex `codex:019fc861-ab09-7683-89a7-de5d124ae2b9; exec:90845` verified its descriptor/hash and additionally required an explicit Todo 7 acceptance section, correctly scoped dual-build language, and unique identities for nonadjacent segments split from one source session. Durable result: `.omo/evidence/plan-review/daily-time-narrative-redesign/round-6-independent.txt`. Corrections add a per-write hash-chained journal, exact build-gate ownership, Todo 7 acceptance, and boundary-qualified `SegmentID` coverage for data, rendering, and selection.
- Round `c3b18f86-016d-45af-8da5-6396e9b398e5` reviewed digest `6adcb3904f7c2360cf8b2818466be96c3a906b2cf33536ca6b2574e3779681f6` and requested changes. Momus `/root/dayline_momus_round7` returned `OKAY`. Independent Codex `codex:019fc868-bc05-7ee1-874e-db350cb76b61; exec:68205` verified its no-follow descriptor/hash, then required live-tick-stable split-piece IDs, durable staged replacement recovery, guarded native lease/settings recovery, exact-bundle QA isolation from production persistence, native-lock allowlists, and canonical command/build bindings. Durable result: `.omo/evidence/plan-review/daily-time-narrative-redesign/round-7-independent.txt` (SHA-256 `b89393ad7cbfcc66b3ce5486891834a6384a9a59e34ac171299f503ab99c0f64`). Corrections use `session UUID + normalized piece start`, durable staged writes, guarded stale-state recovery, and task-local `CFFIXED_USER_HOME` exact-bundle launches.
- Round `1423a1c8-017e-4476-8595-0ef3f7efa577` reviewed and approved digest `c77214177678db0fb9713aab0b54df2ca2762614c56c617052fddfcdc9532d64`. Momus `/root/dayline_momus_round8` returned `OKAY`. Independent Codex `codex:019fc874-1e3a-7bd1-9165-b6ea42ddb7fb; exec:51733` verified its no-follow descriptor and same-FD target hash, reviewed the complete plan, and returned `OKAY`. Durable result: `.omo/evidence/plan-review/daily-time-narrative-redesign/round-8-independent.txt`. This digest is the execution contract.

## Planning review constraints (verified 2026-08-03)

- User approval was received through `$omo:start-work`; plan generation and mandatory review are authorized, but product implementation remains gated on plan approval.
- Preserve `HeatmapSlot`, `SessionEntity.sessions(forSlot:)`, `DailyLogWriter`, `FloatingPanelController.flushDailyLog()`, and `MultiDayHeatmapView`; they remain compile-time or daily-log consumers even though the Dayline replaces the production board.
- One `DayActivityViewModel` owner in `MainPanelView` performs one Core Data fetch per reload, copies managed values into immutable structs, and feeds both the Dayline and category summary. One-second ticks reproject copied values without refetching; relevant session/category saves and calendar-day changes reload. Fetch failure keeps the last good snapshot and exposes a non-disruptive error state for tests/logging.
- Normalize overlaps for display only: clip to the current local calendar day, reject invalid `end < start`, clip future endpoints to `now`, partition at all boundaries, and choose the latest `startTime`; equal starts use a stable lexical session UUID tie-break. Dayline totals and summary totals are derived from the same winning segments and never double-count.
- Day geometry uses local wall-clock anchors `00:00`, `08:00`, `16:00`, and the following `startOfDay`; segment widths within each lane are proportional to elapsed seconds between that lane's calendar-derived anchors. Spring-forward gaps render no invented time; fall-back repeated time remains chronological. Tests lock both 23-hour and 25-hour totals/positions.
- Compact window is the calendar-clipped interval from the start of the hour two hours before `now` through eight elapsed hours, clamped to the current day and shifted only enough to retain an eight-hour span when the day has capacity. Tests lock 00:30, midday, and 23:30 ranges, ticks, and now-marker positions.
- Every category receives a deterministic non-color marker (short symbol/pattern in blocks and matching marker beside visible detail/summary text) plus an accessibility label containing category, start/end, duration, and active state. Short blocks do not require inline text. Color is never the sole identifier.
- Escape remains owned by `NotchWindow` and closes the panel. Dayline selection resets on blur, focus change, or its explicit “Return to current activity” accessibility action; no competing Escape handler is added.
- The visible title is `오늘의 흐름`; the accessibility label is `오늘의 흐름, 오늘 기록 <duration>`; the existing calendar date header remains. The labelled `rectangle.expand.vertical` / `rectangle.compress.vertical` control lives inside the Dayline card header.
- UI acceptance uses actual runtime measurements rather than the stale ~520pt estimate: capture compact and expanded bounds from the exact running window, prove no clipping at those widths, readable 11pt-or-larger labels, deterministic focus order, named accessibility values/actions, and no nonessential transition when Reduce Motion is enabled.
- Both `swift test --package-path NativeScheduler` and a fresh DerivedData Debug `xcodebuild` are required. New Swift files require bounded `xcodegen` regeneration from `project.yml` followed by project-file hash review; prefer adapting existing files when it keeps the implementation smaller.
- The repository is unborn and parent-rooted. Every task records a named-path pre/post SHA-256 manifest, forbids broad staging/deletion/generation, marks commits `N`, and preserves unrelated files. Final review binds to the source manifest digest rather than a nonexistent commit SHA.
- Native QA must bind the launched PID to the exact fresh app bundle and code payload, use an isolated disposable application-support location where supported, record window bounds/ownership, and clean up helper processes/artifacts. `qa_helper.swift` alone cannot prove click, keyboard, AX, or VoiceOver behavior; use native accessibility inspection/AppleScript only where available and report any permission limit honestly.

## Approval gate
status: approved-for-plan-generation
approach: Plan the complete Dayline replacement, shared current-day snapshot, panel integration, design-system update, tests, native/manual accessibility QA, and final review. Do not implement during planning.
next-workflow-action: Fill `.omo/plans/daily-time-narrative-redesign.md`, complete adversarial and dual high-accuracy review, then execute the approved plan in this `$omo:start-work` session.
<!-- When exploration is exhausted and unknowns are answered, set status: awaiting-approval. -->
<!-- That durable record is the loop guard: on a later turn read it and resume at the gate instead of re-running exploration. -->
