---
slug: native-scheduler-market-readiness
status: awaiting-approval
intent: unclear
review_required: true
scope_revision: 2
previous_approval_invalidated_by_scope_change: true
plan_path: .omo/plans/native-scheduler-market-readiness.md
plan_sha256: null
review_round_id: null
pending-action: write and review .omo/plans/native-scheduler-market-readiness.md
review:
  momus:
    status: pending
    workspace_root: null
    runtime_home: null
    target: .omo/plans/native-scheduler-market-readiness.md
    round_id: null
    plan_sha256: null
    launch_id: null
    session: null
    result: null
  independent:
    status: pending
    workspace_root: null
    runtime_home: null
    target: .omo/plans/native-scheduler-market-readiness.md
    round_id: null
    plan_sha256: null
    launch_id: null
    session: null
    result: null
approach: "Preserve the existing native SwiftUI/AppKit architecture and dark notch identity, make Core Data and one normalized category-color value the sources of truth, complete the evidenced v1.1 focus workflow, and prove a Mac App Store-ready artifact through runtime, recovery, accessibility, visual, and packaging QA."
---

# Draft: native-scheduler-market-readiness

## Components (topology ledger)
<!-- Lock the SHAPE before depth. One row per top-level component that can succeed or fail independently. -->
<!-- id | outcome (one line) | status: active|deferred | evidence path -->

| id | outcome | status | evidence path |
|---|---|---|---|
| C1 | Local data is durable, migration-safe, recoverable, and never reports success after a failed save. | active | `NativeScheduler/Sources/NativeScheduler/Models/CoreDataStack.swift:11-48`; `Models/ManagedObjects.swift:5-186` |
| C2 | The focus workflow has distinct pause/stop behavior, restores an interrupted timer, links one todo to a session through an explicit Focus action, carries the selected category identity into every active timer surface, and delivers permission-aware completion notifications. | active | `Features/Timer/TimerView.swift:76-94,244-263,402-432`; `Features/FloatingPanel/NotchView.swift:156-166`; `TimerViewModel.swift:73-179`; `TodoViewModel.swift:21-152`; `management_note.md:455-565` |
| C3 | Today and seven-day activity views use one tested, date-parameterized 15-minute Core Data aggregation path and render the same category identity used by timer, todo, and settings. | active | `Models/ManagedObjects.swift:155-185`; `HeatmapViewModel.swift:28-106`; `HeatmapView.swift:25-31`; `FloatingPanelController.swift:57-96`; `MultiDayHeatmapView.swift:255-266` |
| C4 | A documented native dark design system gives timer, todo, history, category, status, empty, future, disabled, focus, and error states consistent semantic colors while remaining keyboard- and VoiceOver-operable and never relying on color alone. | active | `Shared/DesignSystem/Colors.swift:4-52`; `Features/Timer/TimerView.swift:76-94,244-263`; `Features/Todo/TodoListView.swift:820-849`; `Features/Heatmap/TodayUsageSummaryView.swift:191-255`; `Features/Settings/CategoryEditorView.swift:14-49` |
| C5 | Tests, CI-ready commands, performance checks, and real app smoke scenarios protect persistence, lifecycle, permissions, UI, and migration boundaries. | active | `NativeScheduler/Package.swift:4-37`; `Tests/NativeSchedulerTests/*.swift`; current run: 25 tests, 0 failures on 2026-07-31 |
| C6 | `project.yml` produces a reproducible Mac App Store-ready sandboxed archive with valid metadata/privacy artifacts and complete operator/support documentation. | active | `NativeScheduler/project.yml:1-42`; `Resources/Info.plist:1-34`; Apple distribution/privacy requirements cited below |

## Open assumptions (announced defaults)
<!-- Intent is UNCLEAR: research resolves ambiguity, defaults are adopted (not asked), and each is surfaced in the plan's human TL;DR for veto. -->
<!-- assumption | adopted default | rationale | reversible? -->

| assumption | adopted default | rationale | reversible? |
|---|---|---|---|
| Product position | Local-first, single-user macOS focus planner: todo → focused timer → visible seven-day history. No account or network. | Matches the implemented differentiator and current competitors' credible local/private positioning without adding a platform. | Yes |
| Heatmap granularity | Keep the current tested 15-minute × 96-slot model and update stale 10-minute documentation. Do not support both. | Runtime, UI, log v2, and tests agree on 15 minutes; 10-minute text is stale and dual compatibility adds no user value before first release. | Yes, by a later explicit migration |
| History source | Delete only `DailyLogWriter.swift` and the midnight/termination flush methods/calls; retain `AppDelegate` and `FloatingPanelController`. Query Core Data for all seven days through one aggregator. | Binary logs are unshipped, unread by the UI, duplicate Core Data, and introduce corruption/category-map drift. | No user migration is needed before first release; git can revert implementation |
| Pause/stop semantics | Pause closes the current focus segment; Resume creates the next segment; Stop/reset ends the timer. Render labels that match these actions. | Preserves accurate focused minutes with the smallest change and avoids pause-interval accounting. | Yes |
| Crash recovery | Persist a versioned atomic timer checkpoint only on state transitions; reconcile it with open Core Data sessions on launch. | A focus timer that silently disappears after restart is not trustworthy; transition-only writes avoid 1 Hz disk churn. | Yes |
| Todo integration | One explicit Focus action links one optional Todo to each Session; it may preselect the todo category but never auto-completes the todo. | Matches the accepted v1.1 backlog while keeping timer and completion intent under user control. | Yes |
| Notifications | Local completion notification only, opt-in and requested in context; denial keeps sound + chevron feedback and offers System Settings. | Solves the full-screen/background completion gap without server or push infrastructure. | Yes |
| Distribution | Prepare one canonical Mac App Store build from XcodeGen `project.yml`; direct DMG, custom updater, and credentialed store submission are out. | One channel is enough for a first releasable artifact and avoids maintaining two signing/update paths. | Yes |
| Dependencies | Use Apple frameworks and existing toolchain only; no new runtime packages, telemetry, crash SaaS, analytics, or accounts. | The app is currently dependency-free and local-only; native APIs cover the requested outcome. | Yes |
| Category color identity | Store one validated uppercase `#RRGGBB` value per category and resolve it through the existing design-system boundary. The same base color and category name appear in settings, todo, timer selection/running/notch, today summary, and seven-day records. Recoloring a category updates all related history; deleting an in-use category requires confirmation and makes its records explicitly Uncategorised/Default. | A single relationship-backed identity prevents timer/history drift and avoids duplicating color snapshots on every session. | Yes |
| Color contrast | Preserve the current `#000000`/`#111111` dark shell and category palette. Do not silently alter a chosen category color; add a deterministic contrasting outline plus text/icon/name when a swatch cannot meet 3:1 non-text contrast. Status colors remain independent from category colors. | Identity should be exact across surfaces without sacrificing perceivability or making red/yellow categories look like app errors. | Yes |
| Repository boundary | Preserve the current untracked parent worktree; do not run git reset/clean or create a nested repository. Remote/repository ownership is an operator prerequisite, not an implementation decision. | Parent git root has no commits and contains many unrelated projects; automatic git restructuring would risk user work. | Yes |

Test strategy default: tests-first for migration, persistence, timer recovery, aggregation, and notification state; tests-after for SwiftUI/AppKit composition; copy/config-only changes need no unit test but still require runtime/package QA.

## Findings (cited - path:lines)

- Repository shape: one macOS 14 Swift executable plus XCTest target in `NativeScheduler/Package.swift:4-37`; XcodeGen app configuration lives in `NativeScheduler/project.yml:1-42`.
- Runtime path: `NativeSchedulerApp` delegates to `AppDelegate`, which creates `FloatingPanelController`; it builds `NotchWindow` with `MainPanelView` (`App/NativeSchedulerApp.swift:4-11`, `AppDelegate.swift:8-25`, `Features/FloatingPanel/FloatingPanelController.swift:6-25`).
- Implemented journey: timer start creates a Core Data `SessionEntity`; heatmap and usage views aggregate sessions; todo and category CRUD also use the same view context (`TimerViewModel.swift:73-99`, `HeatmapViewModel.swift:28-106`, `TodoViewModel.swift:21-152`).
- Release blockers: store load calls `fatalError`, save errors are printed and swallowed, directory creation errors are ignored, and fetch errors frequently collapse to empty arrays (`CoreDataStack.swift:18-48`, `ManagedObjects.swift:30,63,104,137`, `HeatmapViewModel.swift:58-65`).
- Lifecycle blocker: the engine is memory-only and startup loads categories/defaults but never restores an open session or timer (`TimerViewModel.swift:8-25,89-99,175-179`).
- Concrete UX defect: the running control is labeled Stop and uses `stop.fill`, but calls `vm.pause()` (`TimerView.swift:402-413`).
- Evidence-backed expansion: the existing project decision log explicitly accepts timer–todo linking, seven-day heatmap, and local notifications for v1.1 (`management_note.md:455-565`); these are not invented adjacent features.
- Historical UI is currently nonfunctional and unmounted: `MainPanelView` renders `HeatmapView`, while `MultiDayHeatmapView` clears historical slots and leaves a reader TODO (`MainPanelView.swift:49-65`, `MultiDayHeatmapView.swift:255-266`).
- Category color already starts from `CategoryEntity.colorHex` and reaches timer selection, todo dots, current heatmap slots, settings, and usage summaries, but it is stored without validation and malformed values silently parse as black (`ManagedObjects.swift:5-24`, `Shared/DesignSystem/Colors.swift:14-36`, `TimerView.swift:244-263`, `TodoListView.swift:839-849`, `HeatmapViewModel.swift:68-105`).
- Running timer surfaces break that identity: timer progress and notch progress use hard-coded blue rather than the selected category color (`TimerView.swift:76-94`, `NotchView.swift:156-166`). Fallbacks also drift across `.nsDefaultSlot`, literal `#3A3A3A`, `.gray`, and summary `#8A8A8A`.
- Color cannot be the only category signal. Existing timer/todo/history text and tooltips supply a usable base, but the completed, empty, future, disabled, low-contrast custom color, and VoiceOver states need explicit design-system and QA coverage.
- Data duplication: today UI and daily flush contain separate slot aggregation loops (`HeatmapViewModel.swift:28-106`, `FloatingPanelController.swift:57-96`); the binary reader has no caller and discards category metadata (`DailyLogWriter.swift:60-79`).
- Specification drift: `prompt.md:72-94,143-178` describes 10-minute/144-slot logs, but executable code and tests use 15-minute/96 slots (`ManagedObjects.swift:155-185`, `HeatmapSlotTests.swift:40-45`).
- Runtime drift also exists inside the current heatmap: compact mode aggregates 20-minute/3-row cells while the full-day and model contract use 15-minute/4-row cells (`HeatmapView.swift:25-31`, `ManagedObjects.swift:155-185`). The release path will use one 15-minute convention.
- Current quality baseline: `swift test --package-path NativeScheduler` completed on 2026-07-31 with 25 tests and 0 failures; no persistence, migration, notification, UI, app-launch, archive, or release tests exist.
- Release surface is incomplete: no CI workflow, README, entitlements file, privacy manifest, export/archive config, release checklist, support/privacy docs, or explicit release signing identity exists. `project.yml` enables hardened runtime and automatic signing only.
- Apple currently requires App Sandbox for Mac App Store distribution and a correct distribution configuration: https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution and https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox
- Apple documents privacy manifests and their macOS bundle location under `Contents/Resources`: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files and https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk
- Apple requires notification authorization before local scheduling and says authorization may change in Settings: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:)
- Accessibility baseline uses keyboard operation, visible focus, meaningful names/roles/values, non-text contrast, and target-size guidance from WCAG 2.2 as cross-platform criteria: https://www.w3.org/TR/WCAG22/
- Market evidence supports the chosen product story rather than a broad project manager: current macOS focus products emphasize always-visible timers, local/private history, explicit controls, notifications, and export/history (https://www.kofeflow.com/, https://www.stayinsession.com/, https://timingapp.com/help/reports).
- Dirty-worktree risk: the git root is `/Users/chan/Projects`, has no commits, and the entire project plus unrelated sibling projects are untracked. Execution must never clean/reset or claim a trustworthy git baseline.

## Decisions (with rationale)

1. Preserve the current SwiftUI/AppKit/MVVM/Core Data structure; no rewrite, sync backend, service layer, or third-party runtime dependency.
2. Establish one source of truth before feature work: reliable Core Data saves, pre-migration backup, real legacy-store migration fixture, user-visible recovery, and a versioned atomic timer checkpoint written via temporary file, fsync, and same-directory rename.
3. Before changing UI, write root `DESIGN.md` from the existing dark implementation: semantic neutral/action/status/empty/future/disabled/focus roles, the category identity contract, state mappings, contrast behavior, typography/spacing already in use, and the requirement that every category color also has a name, icon, label, or tooltip.
4. Keep the implementation small: validate/canonicalize category hex in the existing design-system/model boundary, use one category-color resolver at every consumer, replace timer/notch progress blue with the resolved category accent, and consolidate ad-hoc fallback colors into semantic tokens. Do not create a theme engine or add a dependency.
5. Consolidate all heatmap/usage computations into one pure date-parameterized 15-minute aggregator, delete the unused duplicate binary-log path and compact 20-minute branch, and mount a seven-day view on that same logic.
6. Complete the focus journey with exact control semantics, explicit one-todo Focus action, crash/relaunch restoration, completion notification, honest empty/error/recovery states, and native help/about/privacy entry points.
7. Make `project.yml` the release source; regenerate the Xcode project in an isolated directory and test/archive the generated artifact rather than trusting a stale committed project.
8. Finish with independent runtime, visual, accessibility, and package gates. Source search and success-looking log lines do not count as proof.

### Completion criteria

- Functional: todo CRUD/reorder, explicit Focus start, category changes, duration/end-time modes, pause/resume/stop/reset, today/7-day history, settings, launch-at-login, and notification granted/denied paths work in the built `.app`.
- Recovery: SIGKILL during a running timer followed by relaunch restores remaining time and reconciles exactly one open session; elapsed checkpoints close at their target; paused timers restore paused; corrupt/mismatched checkpoints and stores are preserved/quarantined and shown as recoverable errors rather than crashes.
- Data: a real pre-change SQLite fixture migrates without losing todos/categories/sessions; a forced migration failure leaves a reopenable backup; session/todo delete rules and relationship nullification are tested.
- Aggregation: one implementation passes today, seven distinct dates, cross-midnight, spring-forward, fall-back, tie, nil-category, running-session, and empty-day cases at the canonical 15-minute resolution.
- Color system: `DESIGN.md` matches the shipped UI; a valid category round-trips as uppercase `#RRGGBB`; its exact base color and name remain consistent through category edit, todo, timer selection, active timer/notch, today summary, today heatmap, seven-day history, and relaunch. Recolor propagation, deletion confirmation/defaulting, malformed input fallback, low-contrast outline, completed todo, empty/future/disabled, paused/finished, warning/error, and uncategorised states are covered without using color alone.
- UX/accessibility: screenshot and macOS Accessibility tree evidence prove keyboard-only operation, visible focus, correct control names/actions, empty/error/recovery states, readable labels/targets, and reduced-motion behavior. Icon-only controls may remain only where their accessible name and visible context are unambiguous.
- Performance: the release app meets the existing `prompt.md:224-234` gates: collapsed idle CPU below 0.1%, baseline memory below 30 MB, no polling heatmap reload, and event-driven UI updates, measured by repeatable CLI capture rather than visual judgment.
- Quality: all unit/integration/UI/smoke tests pass from a clean derived-data location; regression failures cannot be suppressed or weakened. `swift test` remains green.
- Distribution: an isolated XcodeGen regeneration, `xcodebuild test`, sandboxed archive, bundle/Info/privacy/entitlement/signature inspection, clean install/update/uninstall, and macOS 14 minimum-target smoke all pass on the produced `.app`.
- Operations: README, changelog, privacy statement, support/troubleshooting, data location/backup/reset/recovery, release checklist, and App Store metadata/review notes are present and consistent with the actual artifact.

## Scope IN

- Add root `DESIGN.md`, semantic color tokens/state mappings, validated canonical category colors, one shared resolver, and exact category identity across settings, todo, timer/notch, today, and seven-day history without an unrelated visual redesign.
- Resolve confirmed timer/control/default/category/launch-at-login error semantics; keep category, status, action, empty, future, disabled, warning, and error colors semantically separate and pair all color signals with text/icons/accessibility labels.
- Core Data error propagation, migration backup/rollback, recovery UI, single-source session history, and active-timer checkpoint reconciliation.
- Optional nullify `SessionEntity` ↔ `TodoEntity` relation plus explicit Focus action; no automatic todo completion.
- Seven-day history using the existing 15-minute/96-slot convention and one reusable aggregator; remove only the unused binary log implementation and flush scheduling/calls.
- Local completion notification with permission settings and sound/chevron fallback.
- Empty/loading/error/recovery states, first-run discoverability, Help/About/privacy/data controls, keyboard/focus/VoiceOver/reduced-motion polish.
- Targeted decomposition only where the existing 1,055-line `TimerView.swift` and 1,664-line `TodoListView.swift` block testing or accessibility; no broad refactor quota.
- Focused tests, real app lifecycle smoke, accessibility/screenshot QA, performance measurement, CI-ready commands, release metadata, sandbox/privacy configuration, and operator docs.

## Scope OUT (Must NOT have)

- Cloud/iCloud sync, accounts, server/API, collaboration, cross-device/mobile apps, calendar/EventKit integration, Shortcuts, global hotkeys, team analytics, billing, subscriptions, or telemetry.
- Direct Developer ID DMG/PKG distribution, notarization pipeline, Sparkle/custom updater, marketing website, pricing decision, or credentialed App Store submission.
- Multi-monitor behavior changes, macOS 13 backport, broad statistics beyond the seven-day focus history, auto-tracking of apps/websites, or website blockers.
- Dual 10-minute and 15-minute history formats, compatibility shims for an unshipped binary log, speculative protocol/factory/repository layers, or new runtime packages.
- Git cleanup/reset, parent-repository restructuring, nested repository creation, or edits outside `/Users/chan/Projects/native_schedular`.
- Any acceptance claim based only on grep, a printed success line, a subagent report, or inspection of a stale generated Xcode project.

## Open questions

None blocking. The route is intentionally open-ended; defaults above are adopted for the plan and can be vetoed at this gate. Apple Developer credentials, distribution team, public support/privacy URLs, remote repository ownership, pricing, and actual store submission are operator-owned inputs outside implementation scope.

## Approval gate
status: awaiting-approval
revision: 2
reason: Category color continuity across timer, todo, and recorded history was added after the previous approval.
approach: Preserve the native architecture and dark notch identity; repair durability and recovery first; establish the documented semantic/color contract; carry one category identity through timer, todo, and records; consolidate 15-minute history; complete the explicit v1.1 user journey; then prove visual consistency, accessibility, performance, and a Mac App Store-ready XcodeGen artifact with runtime evidence.
pending-action: write and review `.omo/plans/native-scheduler-market-readiness.md`
approval-authorizes: plan creation and the already-required dual high-accuracy review only; never product implementation
<!-- When exploration is exhausted and unknowns are answered, set status: awaiting-approval. -->
<!-- That durable record is the loop guard: on a later turn read it and resume at the gate instead of re-running exploration. -->
