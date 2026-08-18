---
slug: product-hardening-efficiency-audit
status: approved-for-execution
intent: clear
review_required: false
classification: architecture
plan_path: .omo/plans/product-hardening-efficiency-audit.md
plan_sha256: 11ef9bc108e432673b5585108b8b11e3206076e180c1f056fc8b80e99eccf096
metis_review: integrated-request-changes
adversarial_review: okay
pending-action: finish active daily-time-narrative-redesign prerequisite, then activate this plan
approach: close the active Dayline delivery on the current source digest first; freeze a verified baseline; then run measure-first stability, resource, code-health, and release hardening waves with characterization/TDD protection and an all-pass final verification wave
---

# Draft: product-hardening-efficiency-audit

## Components (topology ledger)
<!-- Lock the SHAPE before depth. One row per top-level component that can succeed or fail independently. -->
<!-- id | outcome (one line) | status: active|deferred | evidence path -->
C1 | Current product completion: Dayline time progression, options retention, category/timer/color continuity, accessibility/motion, and existing Todo 8/F1–F4 close on one current digest | active | `.omo/boulder.json`; `.omo/evidence/start-work/daily-time-narrative-redesign/a1/task-8-options-retention-fix/independent-r2-delta/report.md`
C2 | Stability and data integrity: deterministic timer/window lifecycle, observable persistence failures, safe store-load behavior, login-item consistency, and crash/concurrency gates | active | `NativeScheduler/Sources/NativeScheduler/Models/CoreDataStack.swift`; `NativeScheduler/Sources/NativeScheduler/App/AppDelegate.swift`; `NativeScheduler/Sources/NativeScheduler/Features/Settings/SettingsView.swift`
C3 | Resource efficiency: measured idle/expanded/timer/drag/persistence CPU, memory, wakeups, UI responsiveness, and I/O with fixes only on active measured paths | active | `NativeScheduler/Sources/NativeScheduler/Features/Timer/TimerEngine.swift`; `NativeScheduler/Sources/NativeScheduler/Features/FloatingPanel/NotchWindow.swift`; `NativeScheduler/Sources/NativeScheduler/Features/Heatmap/HeatmapViewModel.swift`
C4 | Code health: classify reachability, remove confirmed unreachable code, remove unused state, preserve explicit compatibility APIs, and consolidate only behaviorally identical duplication | active | `DESIGN.md`; `NativeScheduler/Sources/NativeScheduler/Features/FloatingPanel/ToggleChevronView.swift`; `NativeScheduler/Sources/NativeScheduler/Features/FloatingPanel/FocusablePanel.swift`
C5 | Verification and release readiness: reproducible dual build graphs, coverage/performance/sanitizer/UI gates, project-generation parity, and distribution artifact validation for the selected channel | active | `NativeScheduler/Package.swift`; `NativeScheduler/project.yml`; `NativeScheduler/NativeScheduler.xcodeproj/project.pbxproj`
C6 | Provenance and commercial-release rights: recover any upstream identity/license if possible, otherwise publish an explicit ownership blocker and third-party notice/name-clearance checklist | active | `prompt.md`; `.claude/agent-memory/cs-dev-optimizer/project_nativescheduler.md`; final release-readiness report

## Open assumptions (announced defaults)
<!-- Record any default you adopt instead of asking, so the user can veto it at the gate. -->
<!-- assumption | adopted default | rationale | reversible? -->
Build graph ownership | `project.yml` is the packaged app declaration; the checked-in Xcode project must be reproducibly generated from it; SwiftPM remains the unit/performance-test graph and both compile at one source digest | current tree already has both graphs and neither alone proves the other | yes
Compatibility cleanup | retain every compatibility/logging surface explicitly protected by `DESIGN.md`; remove only reachability-proven internal leftovers or unused state | prevents an audit from silently breaking log/slot contracts | yes
Performance policy | capture baselines first and optimize only active paths with reproduced cost; legacy grep-only paths are code-health candidates, not runtime incidents | Apple recommends measure → isolate → change → remeasure | yes
Workspace safety | do not initialize/move repositories or stage the parent `/Users/chan/Projects` tree; use manifests/digests/evidence checkpoints unless the user separately requests VCS restructuring | the entire project is currently untracked inside a broader parent Git root | yes
Permission safety | never reset/grant TCC, Reduce Motion, VoiceOver, or login-item state automatically; tests use owned UI-test/native-host seams and mark unavailable permission-bound observation honestly | avoids mutating user/system state | yes
Credential boundary | implement and validate a credential-free Release/archive/ad-hoc-DMG path locally; keep Developer ID, notary submission, stapling ticket, App Store Connect, and App Review as explicit credential/operator gates | secrets and Apple account authority are not available in this workspace | yes

## Findings (cited - path:lines)
- The active existing delivery is incomplete: `.omo/boulder.json` keeps Task 8 in progress and F1–F4 pending. Current options-fix source/build tests are fresh at digest `36f2ba01235523b557baed3b323d6148735baf89f7157b5de313a873fc00dd11`, but the independent report explicitly excludes physical menu/pointer validation (`.omo/evidence/start-work/daily-time-narrative-redesign/a1/task-8-options-retention-fix/independent-r2-delta/report.md`).
- `DayActivityStore.tick()` reprojects cached active records without refetching, but there is no production caller; `MainPanelView` constructs the store and view only (`HeatmapViewModel.swift:344-351`; `MainPanelView.swift:14-18,55-60`). This leaves active Dayline time progression stale between saves and violates the approved one-second projection contract (`DESIGN.md:40-45`).
- Active Dayline does not have the old grid's recurring fetch storm. Legacy `HeatmapView`, `HeatmapViewModel`, and `MultiDayHeatmapView` have no production constructor; optimize/delete decisions must follow the compatibility contract (`DESIGN.md:61-65`).
- Timer ownership is singular and cancellation is present (`FloatingPanelController.swift:7-10`; `TimerEngine.swift:48-132`). Global event monitors and observers also have one owner and deinit cleanup (`NotchWindow.swift:193-235`). Static evidence does not support timer/monitor leak claims.
- Persistence failure handling is not production-safe: persistent-store load uses `fatalError`; saves are asynchronous and print-only (`CoreDataStack.swift:18-20,34-40`). Launch-at-login startup ignores registration failure but still records success, while Settings prints toggle failures without reverting visible state (`AppDelegate.swift:14-19`; `SettingsView.swift:250-256`).
- Daily logging is a bounded midnight/termination path, but performs 96 synchronous per-slot fetches and an atomic write on the main path (`FloatingPanelController.swift:59-97`; `AppDelegate.swift:32-52`; `DailyLogWriter.swift:37-47`). It needs measurement and a roundtrip/failure contract, not speculative steady-state optimization.
- Current tests are 60 methods across four files, with no UI-test target, performance metrics, coverage threshold, sanitizer gate, persistence-file tests, login-item tests, DailyLog tests, CI, shared test plan/scheme, or release/notarization workflow (`NativeScheduler/Tests/NativeSchedulerTests`; `NativeScheduler/project.yml`; `NativeScheduler/Package.swift`).
- The project has two compilation surfaces: SwiftPM tools 5.9 and an XcodeGen Swift 6 hardened app. Both must build at the same digest; `swift test` alone cannot prove the packaged app (`Package.swift:1-37`; `project.yml:11-42`).
- Confirmed unreachable current types are `ToggleChevronView` and `FocusablePanel`; `TimerView.durationInput` is written but never read (`TimerView.swift:12-14,537-540,568-572`). Compatibility-retained candidates such as `MultiDayHeatmapView`, `DailyLogWriter.read`, and legacy slot APIs must not be blindly deleted (`DESIGN.md:61-65`).
- Official measurement basis: Apple recommends Time Profiler for hangs, Allocations/Leaks for memory, Energy Log for power, and File Activity for I/O; Xcode sanitizers cover memory/thread faults, XCTest supports CPU/memory/storage/clock metrics, and SwiftPM supports code coverage. Sources: https://developer.apple.com/documentation/xcode/improving-your-app-s-performance ; https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early ; https://developer.apple.com/documentation/xctest/performance-tests ; https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/swifttest/
- Local availability is confirmed for `xctrace`, `sample`, `vmmap`, `footprint`, `log`, `xcodebuild`, and `swift`; `xctrace` may remain TCC-bound and `fs_usage` requires root, so neither can be a silent mandatory pass when permission is unavailable.
- Direct distribution is structurally incomplete: hardened runtime is enabled, but no entitlements/privacy manifest, archive/export workflow, DMG packaging, Developer ID verification, notary submission, stapling, or Gatekeeper gate exists. Mac App Store compatibility additionally requires a separately verified App Sandbox variant and container/login-item behavior. Official sources: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution ; https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution ; https://developer.apple.com/documentation/security/app-sandbox
- Provenance research found no recoverable GitHub remote, commit/tag, license/SPDX/NOTICE, matching public repository, source archive, or download URL for the app. The parent Git repository is unborn and the project is untracked; `prompt.md` predates the first app source and local command history is consistent with creating the directory before starting Claude, but that does not legally prove ownership. Without an identifiable license, commercial-use permission is not established. GitHub's license guidance: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository
- A plaintext API credential exists in local shell history outside the repository. It must never be copied into evidence; the final handoff must require revocation/rotation, while any history edit remains user-authorized/destructive work outside this plan.

## Decisions (with rationale)
- Finish and reconcile the active Dayline plan before any broad refactor, then freeze one accepted manifest/digest. This prevents stale Todo 7/C001 evidence from blessing the post-fix tree.
- Treat the R2 options source fix as intended current work, not drift to revert: its independent report binds 17/17 focused, 60/60 full, SwiftPM, and Xcode Debug at the current digest, while leaving real pointer/menu behavior as the open gate.
- Repair Dayline production tick ownership before declaring the current feature complete; tests already prove the cached projection API, so the smallest fix is to wire its lifecycle rather than add a second timeline engine.
- Use measure-first performance work and false-positive rejection. Do not optimize legacy uninstantiated heatmap code as if it were an active runtime hotspot.
- Characterize public/compatibility behavior before deletion or consolidation. Similar aggregation and drag/drop code with different contracts is not considered duplication.
- Add an agent-executable native UI-test surface for the real app so pointer/menu/keyboard/AX scenarios do not depend on informal human clicks; optional human inspection is not completion evidence.
- Primary release channel is a directly distributed Developer ID signed/notarized app inside a signed/notarized DMG. Maintain reasonable Mac App Store compatibility as a separately audited sandboxed distribution variant; actual App Store submission is not required.
- Preserve any corrupt/unopenable persistent store byte-for-byte, show an actionable recovery state, and never silently delete/reset user data.
- Use TDD for confirmed defects, characterization tests before cleanup/refactor, and baseline-first performance measurement.
- Treat commercial release as blocked until documented authorship/assignment or written permission establishes rights; adding a new LICENSE cannot cure unknown third-party ownership.

## Scope IN
- Complete, re-verify, and formally close the current Dayline/options/category/timer/color/accessibility/motion work on one exact source digest.
- Active production stability, persistence, lifecycle, error, concurrency, launch-at-login, and data durability audit plus fixes for confirmed defects.
- Baseline and post-change CPU/memory/wakeup/UI/I/O measurements for collapsed idle, expanded idle, active timer/Dayline, todo drag, save/reopen, and termination/midnight-log scenarios.
- Whole-product reachability/dead-state/duplicate responsibility audit, safe deletion, and only evidence-backed simplification.
- Dual build graph, coverage, performance, sanitizer, project parity, native UI-test, packaging, and selected distribution-channel gates.
- Direct Release archive/app/DMG automation, secret-safe Developer ID/notary/staple/Gatekeeper commands, and a separate Mac App Store compatibility report.
- A final provenance/license report with exact evidence, unresolved ownership risk, third-party notices, and product-name clearance status.

## Scope OUT (Must NOT have)
- No new product features, analytics, network service, telemetry upload, subscription, calendar integration, history navigation, or storage-engine migration unless separately approved.
- No deletion of `DESIGN.md` compatibility/logging APIs solely because current UI has no caller.
- No speculative rewrite, dependency addition, or file splitting based only on line count.
- No automatic deletion/reset of a corrupt user store, production persistence access during QA, or silent user/system preference/TCC mutation.
- No Git repository relocation/initialization or staging of unrelated parent-worktree files.

## Open questions
None. The user selected direct signed/notarized app + DMG with reasonable Mac App Store compatibility, preserve-and-recover persistence behavior, and TDD/characterization/measure-first validation.

## Approval gate
status: approved-for-execution
<!-- When exploration is exhausted and unknowns are answered, set status: awaiting-approval. -->
<!-- That durable record is the loop guard: on a later turn read it and resume at the gate instead of re-running exploration. -->
