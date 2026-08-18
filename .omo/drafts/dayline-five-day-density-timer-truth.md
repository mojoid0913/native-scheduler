---
slug: dayline-five-day-density-timer-truth
status: planned
intent: clear
review_required: false
pending-action: choose direct start-work or high-accuracy plan review for .omo/plans/dayline-five-day-density-timer-truth.md
approach: Correct the live padded-content geometry first; keep the collapsed Dayline as today's rolling view; replace expanded same-day lanes with a lazy five-local-day timeline backed by one Core Data range fetch and immutable per-day snapshots; separate the default-category blue role from gray empty-track roles; bind Dayline growth to the authoritative running timer session and checkpoint the existing endTime field so crashes cannot create endlessly growing orphan records; then rerun exact-bundle visual, lifecycle, and regression gates at one manifest digest.
---

# Draft: dayline-five-day-density-timer-truth

## Components (topology ledger)
<!-- Lock the SHAPE before depth. One row per top-level component that can succeed or fail independently. -->
<!-- id | outcome (one line) | status: active|deferred | evidence path -->
| id | outcome | status | evidence path |
|---|---|---|---|
| C1 | Measure the real padded `MainPanelView` proposal and reduce inner density without shrinking text, hit targets, or the hardware-notch shell | active | `NotchView.swift:71-85`, `NotchGeometry.swift:4-9`, `MainPanelView.swift:21-78,146-194`, visual explorer report |
| C2 | Give the default/no-category identity one stable blue role across timer, ring, Dayline, summary, and category picker while gray remains untracked/empty time | active | `Colors.swift:4-33,62-74`, `TimerView.swift:284-305`, `NotchTimerState.swift:4-8` |
| C3 | Expanded Dayline displays exactly five local calendar days from Core Data with DST-aware boundaries, empty days, category patterns, totals, and one live current day | active | `HeatmapViewModel.swift:259-500`, `HeatmapView.swift:522-674`, `MultiDayHeatmapView.swift:1-19,255-266` |
| C4 | A Dayline record grows only for the timer's authoritative active session; pause/stop/finish/reset/quit/category switch/relaunch/crash cannot leave an endlessly growing orphan | active | `TimerViewModel.swift:82-188`, `ManagedObjects.swift:34-64`, `HeatmapViewModel.swift:301-500`, lifecycle explorer report |
| C5 | Reconcile the active Dayline Boulder plan and keep the approved hardening plan queued; all new work and final evidence bind to one fresh 40-file-or-updated manifest | active | `.omo/boulder.json`, `.omo/plans/daily-time-narrative-redesign.md`, `.omo/plans/product-hardening-efficiency-audit.md` |

## Open assumptions (announced defaults)
<!-- Record any default you adopt instead of asking, so the user can veto it at the gate. -->
<!-- assumption | adopted default | rationale | reversible? -->
| assumption | adopted default | rationale | reversible? |
|---|---|---|---|
| Default blue | `#4DABF7`, exposed as a named default-category role; do not recolor gray elapsed/untracked tracks | Already present in `CategoryPalette`; stable sRGB value avoids dynamic system-blue drift | yes |
| Storage | No new Core Data entity/attribute; reuse `SessionEntity.endTime` as a periodic durable checkpoint and use an in-process authoritative active session ID for live projection | Avoids migration while bounding crash recovery and eliminating nil-ended orphan growth | yes |
| Historical source | Query `SessionEntity` directly; do not use `MultiDayHeatmapView` or the unfinished `DailyLogReader` hook | Existing historical grid is a stub and conflicts with Dayline truth | yes |
| Test strategy | TDD for confirmed geometry/orphan defects; tests-first contracts for five-day projection and default color; exact-bundle QA after green | Prior approved project strategy is TDD for defects and characterization-first changes | yes |
| Accessibility | Keep all meaningful text at least 11pt and native controls at least 24pt; make the UI feel smaller through padding/gap/track density, not global scale | Required by `DESIGN.md` and current AX contract | yes |
| Existing data | Preserve closed historical sessions byte-for-byte; never auto-delete nil-ended legacy rows; reconcile their displayed endpoint conservatively and report recovery | Prevents silent user-data loss | no, once data is rewritten |

## Findings (cited - path:lines)
- The live shell is fixed at 816×384pt plus 20pt shadow, while `NotchView` applies horizontal 20pt, top `notchHeight + 10`, and bottom 16pt around `MainPanelView` (`NotchGeometry.swift:4-9,92-99`; `NotchView.swift:71-85`). Existing production-host evidence fed 776×384 to `MainPanelLayoutMetrics`; with the observed 37pt notch, the likely live child is 776×321. Exact runtime measurement must precede density changes.
- `MainPanelView` currently expands one current-day snapshot from a rolling lane into three same-day lanes and reallocates the right column (`MainPanelView.swift:7-78`; `HeatmapView.swift:522-607`). The new five-day requirement supersedes `DESIGN.md`'s current-day/history exclusion and requires a contract update first.
- `DayActivityStore` performs one current-day overlap fetch, caches immutable records, and reprojects every second without refetch (`HeatmapViewModel.swift:301-370`). Its private projector already handles overlap winners, stable IDs, totals, and 23/25-hour days; this is the reusable truth boundary for five per-day snapshots.
- `MultiDayHeatmapView` is a legacy 15-minute grid. Its −1…−6 history loader always sets an empty dictionary and leaves `DailyLogReader` as TODO (`MultiDayHeatmapView.swift:4-19,255-266`); it must remain compatibility code, not become the new source of truth.
- The default category is currently gray because nil and malformed colors resolve to `nsDefaultSlot #3A3A3A`; the same value feeds the category picker and collapsed ring (`Colors.swift:10,18,25-33`; `TimerView.swift:291-305`; `NotchTimerState.swift:4-8`). Empty/untracked gray and default-category blue need separate semantic roles.
- Session creation is centralized after `TimerEngine.start()` succeeds; pause and stop close the current row, category change closes and opens, and natural finish schedules a close (`TimerViewModel.swift:82-188`). But direct reset/configure, graceful termination, crash, and relaunch can leave nil-ended rows.
- `SessionEntity.isRunning` means only `endTime == nil` (`ManagedObjects.swift:34-52`). `DayActivityStore` and legacy projections use `end ?? asOf`, so an orphan grows every second with no running engine (`HeatmapViewModel.swift:219-229,327-345,405-451`). Existing tests explicitly demonstrate nil-ended records growing independently of TimerEngine (`HeatmapLiveTests.swift:111-176`).
- Metis pre-plan review found that `endTime` cannot simultaneously remain the live-state flag and become a durable checkpoint. The executable contract therefore makes `TimerViewModel.activeSessionID` the sole live authority, creates an initial zero-length durable checkpoint, and includes the active ID explicitly in range fetches.
- The active Boulder predecessor, queued hardening P0, and this successor cannot all own the same unfinished lifecycle work. Execution must transfer predecessor Task 8/F1–F4 without marking them complete and make hardening depend on this successor.
- There are 62 XCTest methods in four files and no UI-test/performance/sanitizer/CI target. Current Boulder still owns `daily-time-narrative-redesign` Task 8 with F1-F4 pending; the approved hardening plan forbids parallel activation.

## Decisions (with rationale)
- Compact remains today's rolling eight-hour Dayline. The five-day view exists only while Dayline's own disclosure is expanded; expanding the outer notch alone does not show history. The old three-lane same-day expanded view is removed from the production path rather than nested beneath history.
- Expanded history shows exactly five thin horizontal 24-hour lanes at once, ordered newest first (`Today`, then the previous four local dates). The lanes share one time axis so five full-size cards or a carousel are unnecessary.
- Keep the 816×384 outer notch shell. After measuring the real padded child proposal, reduce expanded-only timer/summary height below its current 128pt allocation, preserve all labels and at least 24pt hit targets, and transfer the reclaimed height to the five-lane Dayline. Do not globally scale the UI.
- Five-day data uses one lazy range fetch covering five local calendar days, then a shared pure per-day projector. Older days are stable; only today's snapshot ticks. No five independent fetch loops and no 15-minute grid conversion.
- Default blue is a category identity token. Gray elapsed/future/untracked tracks are unchanged, preserving semantic contrast.
- Live growth is authorized by the timer-owned active session ID, not by nil `endTime`. The existing `endTime` is periodically checkpointed and finalized synchronously on every running→not-running transition; arbitrary legacy nil-ended rows never extend to the current time.
- While a timer runs, checkpoint its existing `endTime` every 10 seconds. Normal transitions finalize the exact timestamp; abnormal termination can lose at most the last checkpoint interval but cannot count offline time.
- Lock expanded geometry to a 96pt timer/summary row plus 6pt gap; at the canonical real 776×321 child proposal the Dayline receives the remaining height. Five rows are 20pt each with 10pt tracks, 8pt expanded card inset, and one shared axis/detail row.
- Preserve unauthoritative nil-ended legacy rows byte-for-byte, project their end as `startTime` (zero duration), and surface a recovery warning/count. Do not fabricate a later endpoint or auto-rewrite history.
- Initial create/save failure stops the engine and publishes no live authority. Checkpoint failure keeps the running authority and retries at the next boundary. Final failure clears live authority, retains a retryable reference/last durable checkpoint, and exposes an error; quit retries once synchronously, then logs/terminates at the last durable checkpoint.
- Category switching captures one boundary, closes the old row and creates the new zero-length checkpoint in one save, and changes category/authority only after success; failure rolls back the replacement.
- Test and QA evidence must use the real padded child geometry and exact app shell, not a Dayline-only host with an assumed 384pt child height.
- The new plan supersedes the unfinished visual-only completion of the current Dayline plan. Execution must explicitly rebind Boulder before edits and leave product hardening queued until this plan's final wave passes.

## Scope IN
- Update `DESIGN.md` for five-day expanded history, default blue, timer-authoritative recording, and measured live content geometry.
- Live geometry measurement seam and compact inner density for Dayline/right column without reducing accessibility floors.
- Named default-category blue role and all consumers/tests.
- Five-day immutable history window/projector, one fetch, DST/empty/error/live-current behavior, five-row visual/accessibility presentation.
- Timer session ownership, checkpoint/finalization, legacy-orphan reconciliation without silent deletion, graceful termination, save-failure handling.
- SwiftPM/Xcode tests, exact-source host, native AX/pointer/keyboard/menu/settings, state-preservation, performance/write-frequency checks, dual visual review, F1-F4.
- Boulder/ledger/manifest reconciliation with the active predecessor plan.

## Scope OUT (Must NOT have)
- No global UI scale transform, text below 11pt, hit target below 24pt, or speculative outer-notch resize without an independently measured requirement.
- No calendar navigation, editable history, more than five visible days, charts/streaks/goals, calendar import, app tracking, analytics, or new dependency.
- No reuse of legacy checkerboard/MultiDayHeatmap as Dayline truth and no DailyLog format rewrite.
- No automatic deletion of user sessions, no relaunch-time extension of orphan rows, and no per-second Core Data save loop.
- No parallel activation of `product-hardening-efficiency-audit`; no Developer ID/release work in this plan.

## Approval gate
status: approved-and-planned
<!-- When exploration is exhausted and unknowns are answered, set status: awaiting-approval. -->
<!-- That durable record is the loop guard: on a later turn read it and resume at the gate instead of re-running exploration. -->
