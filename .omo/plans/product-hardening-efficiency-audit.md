# product-hardening-efficiency-audit - Work Plan

## TL;DR (For humans)
<!-- Fill this LAST, after the detailed plan below is written, so it summarizes the REAL plan. -->
<!-- Plain English for a non-engineer: NO file paths, NO todo numbers, NO wave/agent/tool names. -->

**What you'll get:** A stable, data-safe, resource-measured NativeScheduler with reproducible tests, a direct-download app/DMG release pipeline, and a separately checked Mac App Store-compatible build configuration. The handoff will distinguish engineering readiness from legal/signing readiness and state exactly what still blocks commercial distribution.

**Why this approach:** First finish and re-prove the feature already under construction, then harden failure paths before optimizing or deleting code. Performance changes require measurements, and release claims require both Apple artifact evidence and positive ownership/license evidence.

**What it will NOT do:** It will not add unrelated features, silently reset damaged user data, change system permissions, or call an unsigned/ad-hoc build a commercial release. It will not invent a GitHub license or ownership conclusion where evidence is missing.

**Effort:** XL
**Risk:** High - persistence recovery, native UI automation, dual distribution configurations, and unavailable legal/signing inputs all sit on release-critical boundaries.
**Decisions to sanity-check:** Direct notarized download is primary; Store work is compatibility-only; damaged stores are preserved without automatic reset; current commercial-rights status is blocked until positive ownership or license evidence exists.

Your next move: Execution is approved. Finish the currently active feature gate first, then activate this hardening plan. Full execution detail follows below.

---

> TL;DR (machine): XL/high-risk; serialize active Dayline closure, then deliver persistence recovery, truthful lifecycle errors, measured efficiency cleanup, dual test/build quality gates, direct app/DMG automation, MAS compatibility, and an evidence-bound rights verdict.

## Scope
### Must have
- Before this plan becomes active, complete the approved successor `dayline-five-day-density-timer-truth` Boulder run on one exact recursive manifest digest. The successor absorbs the predecessor's unfinished Task 8/F1–F4 while preserving Tasks 1–7 as historical evidence only.
- Preserve user data and report failures truthfully: deterministic save completion, non-crashing store-load recovery, byte-for-byte preservation of SQLite/WAL/SHM, visible recovery actions, correct termination ordering, and consistent launch-at-login state.
- Measure resource behavior on production-owned paths before changing it; retain raw traces, fixed scenarios, three-run medians, hardware/OS/tool metadata, and before/after evidence for every optimization.
- Characterize before cleanup; remove only individually proven unreachable state/types or behaviorally identical duplication while preserving the compatibility surfaces named by `DESIGN.md`.
- Make `project.yml` the generated-project source of truth; add runnable unit/UI/lifecycle/performance gates, dual SwiftPM/Xcode validation, coverage, sanitizers, and CI-ready commands.
- Produce a reproducible direct-distribution development candidate (`.app` + DMG), secret-safe Developer ID/notary/staple automation, and a separate limited Mac App Store sandbox-compatibility configuration/report.
- Finish with an explicit rights verdict. `VERIFIED` requires a pinned upstream commercial license or written ownership/assignment; otherwise the release status is `BLOCKED — rights unproven` even if all engineering gates pass.

### Must NOT have (guardrails, anti-slop, scope boundaries)
- No new product features, accounts, sync, telemetry, analytics, updater, billing, calendar/notification/history expansion, or storage-engine rewrite.
- No silent deletion/reset/replacement of a corrupt store; no fresh store creation after a load failure without a later explicit user-confirmed action that still retains the recovery bundle.
- No TCC, VoiceOver, Full Keyboard Access, Reduce Motion, login-item, or other real user/system preference mutation in automated tests. Use disposable homes, injected services, owned test hosts, and honest `INCONCLUSIVE` results for permission-bound instruments.
- No optimization of uninstantiated legacy views as a runtime hotspot; no deletion of `HeatmapView`, `HeatmapViewModel`, `MultiDayHeatmapView`, `HeatmapSlot`, or DailyLog compatibility APIs based only on text search.
- No new runtime dependency, speculative protocol/factory, line-count refactor, broad reformat, repository initialization/relocation, parent-tree staging, or unrelated cleanup.
- No claim that an ad-hoc signature, unsigned archive, search miss, empty dependency list, newly added LICENSE, or successful local build is a commercially distributable notarized release.
- Never store Apple credentials, certificate private keys, API keys, passwords, notary profiles, database contents, or other secrets in source, command logs, evidence, or reports.

## Verification strategy
> Zero human intervention - all verification is agent-executed.
- Test decision: TDD with XCTest for confirmed defects and trust boundaries; characterization-first for cleanup; baseline-first for performance. SwiftPM and generated Xcode targets must execute the named tests at the same source-manifest digest.
- Native QA: build into a fresh task-local DerivedData directory, prove executable/bundle/source identity, launch only with disposable application-support/preferences routing and the volatile login-item argument, exercise the real `.app` through the macOS UI/AX surface, capture owner-window evidence, and clean all owned processes/state. Never substitute a synthetic event success line for observed app state.
- Performance protocol: three fixed-duration runs per collapsed idle, expanded idle, active timer/Dayline, todo drag auto-scroll, save/reopen, and midnight-log simulation; record hardware, macOS, Xcode, power state, duration, raw `sample`/`footprint`/`vmmap`/available `xctrace` outputs, median, tolerance, and decision. Permission-bound tools may be `INCONCLUSIVE`, not PASS.
- Release proof: development candidate and commercial release are distinct. The candidate needs archive/app/DMG hashes and structural/signature/entitlement checks. A commercial release additionally needs rights clearance, Developer ID identity, notary submission/log, stapler validation, and Gatekeeper assessment.
- Evidence root: `$ATTEMPT_ROOT=.omo/evidence/start-work/product-hardening-efficiency-audit/a1`; every task records commands, exit codes, executed test counts, pre/post recursive allowlist manifests, artifact hashes, cleanup, and an executor DoneClaim followed by independent adversarial verification.

## Execution strategy
### Parallel execution waves
> Target 5-8 todos per wave. Fewer than 3 (except the final) means you under-split.

**External prerequisite P0 — serialize before activating this plan.** Keep this hardening plan queued while `.omo/boulder.json` is bound to `.omo/plans/dayline-five-day-density-timer-truth.md`. P0 passes only after that successor completes Todos 1–10 and F1–F4 at one final digest, including exact-app options/pointer/keyboard/AX/Reduce Motion QA. The approved transfer is explicit, not a silent supersession: predecessor Tasks 1–7 remain historical and its unfinished Task 8/F1–F4 move to the successor. This plan must consume the successor's timer save/termination evidence and narrow Todos 2/7 to uncovered hardening gaps instead of reimplementing conflicting ownership.

- Wave 1 — frozen baseline and deterministic seams: Todos 1-5. After P0, Todo 1 freezes truth; Todos 2-5 can proceed with disjoint owners.
- Wave 2 — reliability behavior: Todos 6-10. Recovery/save/login/settings/log work consumes Wave 1 seams and remains file-owner serialized where paths overlap.
- Wave 3 — measured quality and simplification: Todos 11-14. Measure before remediation; cleanup waits for characterization; quality gates then freeze the candidate tree.
- Wave 4 — distribution and rights: Todos 15-18. Direct and Store configurations share the frozen project source; the final candidate waits for rights/report/config outputs.
- Final wave — F1-F4 after every implementation todo. F1/F2 may run in parallel; F3 uses the native-QA lease; F4 starts only after F3 cleanup so release/runtime evidence cannot cross-contaminate.

### Dependency matrix
| Todo | Depends on | Blocks | Can parallelize with |
| --- | --- | --- | --- |
| P0 | Successful completion of `dayline-five-day-density-timer-truth` | 1-18 | none |
| 1 | P0 | 6-18 | none |
| 2 | 1 | 6, 7, 10 | 3, 4, 5 |
| 3 | 1 | 8 | 2, 4, 5 |
| 4 | 1 | 6, 8, 12, 14 | 2, 3, 5 |
| 5 | 1 | 10, 11 | 2, 3, 4 |
| 6 | 2, 4 | 11-18 | 8, 9, 10 |
| 7 | 2, 4 | 10-18 | 8, 9 |
| 8 | 3, 4 | 11-18 | 6, 7, 9, 10 |
| 9 | 1, 4 | 11-18 | 6, 7, 8, 10 |
| 10 | 2, 5, 7 | 11-18 | 6, 8, 9 |
| 11 | 5-10 | 12-18 | none |
| 12 | 4, 6-11 | 14-18 | 13 |
| 13 | 1, 4, 6-11 | 14-18 | 12 |
| 14 | 4, 6-13 | 15-18 | none |
| 15 | 14 | 18 | 16, 17 |
| 16 | 14 | 18 | 15, 17 |
| 17 | 1, 14 | 18 | 15, 16 |
| 18 | 15-17 | F1-F4 | none |

## Todos
> Implementation + Test = ONE todo. Never separate.
<!-- APPEND TASK BATCHES BELOW THIS LINE WITH edit/apply_patch - never rewrite the headers above. -->
- [ ] 1. Freeze the post-Dayline product, workspace, provenance, and release baseline
  What to do / Must NOT do: After P0 closes, inventory every product/test/config/resource/document path, recursive SHA-256 manifest, build graph, toolchain, dependencies/system frameworks, bundled assets, data locations, entitlements/privacy files, signing identities, and successor completion receipts. Classify `prompt.md`/`.claude` notes as historical and non-authoritative. Do not edit product files, initialize Git, or accept stale evidence.
  Parallelization: Wave 1 | Blocked by: P0 | Blocks: 2-18
  References: `.omo/boulder.json`; `.omo/start-work/dayline-successor-transfer.md`; `.omo/plans/dayline-five-day-density-timer-truth.md`; `DESIGN.md`; `NativeScheduler/Package.swift:1`; `NativeScheduler/project.yml:1`
  Acceptance criteria: `rtk swift test --package-path NativeScheduler`, `rtk swift build --package-path NativeScheduler`, and a fresh `rtk xcodebuild -project NativeScheduler/NativeScheduler.xcodeproj -scheme NativeScheduler -configuration Debug -derivedDataPath "$ATTEMPT_ROOT/task-1-DerivedData" build` all exit 0 at the recorded manifest; old Todo 8/F1-F4 and ULW criteria are complete; `rtk security find-identity -v -p codesigning` output is recorded without secrets; no source changes occur.
  QA scenarios: happy — recompute the manifest twice and obtain identical hashes plus nonzero named tests in both relevant graphs; failure — inject a copied stale digest into the verifier and require rejection. Evidence: `$ATTEMPT_ROOT/task-1-baseline.md`, `task-1-source-manifest.txt`, `task-1-old-plan-closure.md`, `task-1-release-inventory.md`, `task-1-cleanup.txt`.
  Commit: N | evidence only; unborn/untracked repository

- [ ] 2. Add minimal persistence load/save/file-operation seams and typed failure state
  What to do / Must NOT do: TDD the smallest injectable persistent-store URL/description and file-copy/hash boundary needed to force load, save, and preservation failures; replace `fatalError`/print-only behavior with a finite observable state and typed error. Preserve the default production singleton call sites. Do not add a repository layer, migration framework, automatic reset, or expose database contents.
  Parallelization: Wave 1 | Blocked by: 1 | Blocks: 6, 7, 10
  References: `NativeScheduler/Sources/NativeScheduler/Models/CoreDataStack.swift:11-48`; `NativeScheduler/Sources/NativeScheduler/Models/ManagedObjects.swift`; `NativeScheduler/Tests/NativeSchedulerTests`
  Acceptance criteria: a new focused XCTest file first proves RED for load/save/copy failures, then passes for in-memory/temporary normal store and each injected error; the app no longer has a persistent-store-load `fatalError`; errors remain structured across the UI boundary; full SwiftPM and Xcode unit tests pass.
  QA scenarios: happy — temporary store loads, mutates, explicitly saves, closes, and reopens; failure — invalid SQLite and forced save/copy errors return exact states with zero deletion. Evidence: `$ATTEMPT_ROOT/task-2-red.log`, `task-2-focused.log`, `task-2-full.log`, `task-2-manifest.txt`, `task-2-review.md`.
  Commit: N | feat(persistence): expose minimal recoverable store state

- [ ] 3. Add a truthful, injectable launch-at-login service boundary
  What to do / Must NOT do: Replace direct `SMAppService.mainApp` decisions with the smallest closure/value adapter that can report current status and register/unregister results to startup and Settings. A failed operation must not write success defaults or leave the UI toggle enabled. Do not create a service hierarchy or mutate the real login item in tests.
  Parallelization: Wave 1 | Blocked by: 1 | Blocks: 8
  References: `NativeScheduler/Sources/NativeScheduler/App/AppDelegate.swift:14-19`; `NativeScheduler/Sources/NativeScheduler/Features/Settings/SettingsView.swift:195-256`
  Acceptance criteria: failing-first tests cover first-run register failure, Settings register/unregister failure, external status drift, and success; production still delegates to `SMAppService.mainApp`; automated tests use only fakes and never alter the host login item.
  QA scenarios: happy — fake status transitions update defaults/UI once; failure — thrown registration keeps prior displayed/status value and exposes actionable error text. Evidence: `$ATTEMPT_ROOT/task-3-red.log`, `task-3-focused.log`, `task-3-login-item-before-after.txt`, `task-3-review.md`.
  Commit: N | fix(login-item): keep persisted and visible state truthful

- [ ] 4. Make generated Xcode tests and isolated native UI smoke runnable
  What to do / Must NOT do: Extend `project.yml` with the minimal unit/UI-test targets, shared scheme/test plan, disposable launch arguments/home routing, and stable accessibility identifiers for the already required shell/options/recovery paths; regenerate the checked-in project reproducibly. Reuse existing tests and native identifiers; do not build a second QA app or automate TCC/system preferences.
  Parallelization: Wave 1 | Blocked by: 1 | Blocks: 6, 8, 12, 14
  References: `NativeScheduler/project.yml:1-42`; `NativeScheduler/NativeScheduler.xcodeproj`; `NativeScheduler/Package.swift:4-37`; `NotchView.swift:137-247`; `MainPanelView.swift:5-115`
  Acceptance criteria: preflight `rtk xcodegen --version` succeeds and is recorded; if unavailable the task is BLOCKED with the exact missing prerequisite and cannot claim parity. Two isolated XcodeGen generations then have identical project manifests; `rtk xcodebuild test` executes named unit and UI smoke cases against a disposable store; a wrong bundle ID/home/digest negative control is rejected; SwiftPM tests remain green.
  QA scenarios: happy — launch exact app, expand, open/close Options while the shell stays expanded, then terminate with disposable state; failure — invalid isolation argument or stale payload fails before UI actions. Evidence: `$ATTEMPT_ROOT/task-4-project-parity.txt`, `task-4-xcode-tests.log`, `task-4-ui-smoke.md`, `task-4-cleanup.txt`, `task-4-review.md`.
  Commit: N | test(xcode): add generated unit and native UI smoke gates

- [ ] 5. Establish the reproducible performance and resource measurement protocol
  What to do / Must NOT do: Add a small script/documented command surface that records machine/OS/Xcode/power state, exact app digest/PID, warm-up, duration, three repetitions, raw and median CPU/memory/wakeup/I/O/responsiveness metrics, tolerance, and cleanup for six approved scenarios. Prefer installed Apple/stdlib tools; no dependency or inherited absolute target from stale `prompt.md`.
  Parallelization: Wave 1 | Blocked by: 1 | Blocks: 10, 11
  References: `prompt.md:224-234` (historical only); `TimerEngine.swift:48-132`; `NotchWindow.swift:193-235`; `FloatingPanelController.swift:59-97`; Apple performance/XCTest references in the approved draft
  Acceptance criteria: a dry run records complete metadata/raw files/derived median for a disposable exact app; two identical fixture inputs derive the same result; unavailable `xctrace`/permission-bound tools become `INCONCLUSIVE`; no `fs_usage` root escalation.
  QA scenarios: happy — three short fixture runs aggregate deterministically; failure — missing sample, mismatched PID/digest, or permission denial prevents PASS. Evidence: `$ATTEMPT_ROOT/task-5-protocol.md`, `task-5-dry-run/`, `task-5-negative-controls.txt`, `task-5-review.md`.
  Commit: N | test(performance): add a deterministic evidence protocol

- [ ] 6. Preserve corrupt stores byte-for-byte and present a non-crashing recovery surface
  What to do / Must NOT do: Before `NSPersistentContainer` attempts to open or mutate an existing store, enumerate and hash every `.sqlite`, `-wal`, and `-shm` member and create a raw preflight preservation snapshot. On load failure, promote that untouched snapshot into an app-owned timestamped recovery bundle, record names/sizes/SHA-256, and show a recovery panel with Reveal, Export, Retry, and Quit. A preservation failure must stop before the Core Data open attempt, leave recovery visible, and keep originals untouched. A successful normal load may clean only its temporary preflight snapshot. Do not offer or perform automatic deletion/start-fresh in this plan.
  Parallelization: Wave 2 | Blocked by: 2, 4 | Blocks: 11-18
  References: `CoreDataStack.swift:11-48`; `NativeScheduler/Sources/NativeScheduler/App/NativeSchedulerApp.swift`; `AppDelegate.swift:6-34`; `DESIGN.md`
  Acceptance criteria: temporary-directory tests prove source enumeration/hash and raw snapshot complete before any persistent-container load callback, originals and promoted recovery-bundle byte hashes match for database plus sidecars, preservation failure performs zero Core Data open/reset and deletes nothing, retry can load a repaired fixture, and a normal store cleans only the temporary snapshot; native UI smoke proves all actions and keyboard/AX labels without exposing data content.
  QA scenarios: happy — invalid store enters recovery, export copy matches manifest, repaired retry reaches normal shell; failure — forced insufficient-space/copy failure remains recoverable with zero source-member deletion. Evidence: `$ATTEMPT_ROOT/task-6-red.log`, `task-6-store-hashes.txt`, `task-6-ui-qa.md`, `task-6-cleanup.txt`, `task-6-review.md`.
  Commit: N | feat(recovery): preserve stores and expose recovery actions

- [ ] 7. Make saves and application termination durability-ordered
  What to do / Must NOT do: Provide an explicit completion/error result for context saves, route session close and termination through it, and flush the daily log only after the intended context state is durable. Keep normal UI work nonblocking and respect context queues. Do not insert arbitrary sleeps, global locks, or swallow errors.
  Parallelization: Wave 2 | Blocked by: 2, 4 | Blocks: 10-18
  References: `CoreDataStack.swift:34-40`; `TimerViewModel.swift:73-182`; `AppDelegate.swift:32-52`; `FloatingPanelController.swift:59-97`
  Acceptance criteria: TDD proves close-session save completion precedes reference release, quit ordering saves before log read, forced save failure suppresses success/log-finalization and surfaces an error, and repeated termination is idempotent; full tests and both builds pass.
  QA scenarios: happy — write/quit/reopen retains the final closed session and matching log; failure — injected save error leaves the session/store recoverable and records no false-success receipt. Evidence: `$ATTEMPT_ROOT/task-7-red.log`, `task-7-ordering.log`, `task-7-reopen.log`, `task-7-review.md`.
  Commit: N | fix(persistence): await durable state before lifecycle flush

- [ ] 8. Keep launch-at-login UI and first-run behavior consistent under failure
  What to do / Must NOT do: Apply Todo 3's service state to startup and Settings, render concise actionable errors, refresh from actual status when Settings opens, and ensure the volatile QA argument bypasses registration. Do not open System Settings or change the real service during automated QA.
  Parallelization: Wave 2 | Blocked by: 3, 4 | Blocks: 11-18
  References: `AppDelegate.swift:14-25`; `SettingsView.swift:195-256`; `Info.plist`; `project.yml:28-42`
  Acceptance criteria: named tests and native UI smoke cover enabled/disabled/requires-approval/not-found/failure states; failure reverts the toggle and preserves the stored first-run flag; the host login-item before/after record is identical.
  QA scenarios: happy — fake registration succeeds and is reflected after reopen; failure — fake register/unregister throws and the prior state plus error remain visible. Evidence: `$ATTEMPT_ROOT/task-8-focused.log`, `task-8-ui-qa.md`, `task-8-host-state.txt`, `task-8-review.md`.
  Commit: N | fix(settings): reflect real login-item results

- [ ] 9. Unify persisted timer-duration bounds and malformed-default behavior
  What to do / Must NOT do: Choose one existing supported range and use it in Settings, `TimerViewModel`, and parsing/initialization; normalize malformed/out-of-range persisted values once and show the actual effective value. Do not create a settings schema or migrate unrelated defaults.
  Parallelization: Wave 2 | Blocked by: 1, 4 | Blocks: 11-18
  References: `SettingsView.swift` duration Stepper; `TimerViewModel.swift:41-60`; `TimerEngineTests.swift`
  Acceptance criteria: failing-first boundary tests cover minimum, maximum, zero, negative, over-max, missing, and malformed mode; Settings and runtime expose the same range/value; restart UI smoke preserves it.
  QA scenarios: happy — boundary values round-trip across restart; failure — out-of-range defaults normalize predictably without crash or hidden UI/runtime mismatch. Evidence: `$ATTEMPT_ROOT/task-9-red.log`, `task-9-focused.log`, `task-9-restart.md`, `task-9-review.md`.
  Commit: N | fix(timer-settings): share one supported duration range

- [ ] 10. Characterize DailyLog v2, failure behavior, and measured lifecycle cost
  What to do / Must NOT do: Lock binary magic/version/96-slot/category-map/roundtrip/truncation/write-failure behavior before any change; measure the current 96-fetch midnight/termination path using Todo 5; optimize only if the reproduced median/tail breach is material, preferably by reusing already fetched session data. Keep DailyLog compatibility required by `DESIGN.md`.
  Parallelization: Wave 2 | Blocked by: 2, 5, 7 | Blocks: 11-18
  References: `FloatingPanelController.swift:59-97`; `DailyLogWriter.swift:16-79`; `ManagedObjects.swift:155-185`; `DESIGN.md:61-65`
  Acceptance criteria: new tests prove exact roundtrip, bad magic/version, truncated data, atomic write failure, cross-midnight boundaries, and no user-file overwrite; baseline and any after trace use the same protocol; no change is made when cost is below declared tolerance.
  QA scenarios: happy — fixture writes/reads equal 96 slots and category metadata; failure — truncated/corrupt/output-denied fixtures fail without replacing a prior valid log. Evidence: `$ATTEMPT_ROOT/task-10-red.log`, `task-10-roundtrip.log`, `task-10-performance/`, `task-10-review.md`.
  Commit: N | test(log): characterize and conditionally optimize lifecycle logging

- [ ] 11. Measure production scenarios and remediate only reproduced active-path regressions
  What to do / Must NOT do: Run Todo 5's full six-scenario three-run protocol on the exact candidate, rank costs, identify production constructor/caller ownership, and apply only the smallest fix for a reproduced regression; remeasure identical scenarios. If no regression is established, make no product edit and record the baseline. Never optimize legacy unmounted heatmap code as runtime work.
  Parallelization: Wave 3 | Blocked by: 5-10 | Blocks: 12-18
  References: active path `NativeScheduler/Sources/NativeScheduler/App/NativeSchedulerApp.swift` → `AppDelegate.swift` → `FloatingPanelController.swift` → `NotchWindow.swift`/`MainPanelView.swift`; `TimerEngine.swift:48-132`; `TodoListView.swift:1131-1513`
  Acceptance criteria: every scenario has three valid raw runs and median/tolerance; any changed path has a before/after improvement outside tolerance with behavior tests green; idle timer/observer counts remain stable over repeated expand/timer/drag/save cycles; permission gaps are labelled `INCONCLUSIVE`.
  QA scenarios: happy — baseline completes and either proves no edit or a measured improvement; failure — wrong PID, missing repetition, stale payload, or unowned path prevents remediation/approval. Evidence: `$ATTEMPT_ROOT/task-11-baseline/`, `task-11-ranking.md`, `task-11-after/`, `task-11-review.md`.
  Commit: N | perf(runtime): remediate only measured production cost

- [ ] 12. Add sanitizer and lifecycle stress gates for timers, observers, persistence, and UI tasks
  What to do / Must NOT do: Configure Address/Thread sanitizer test schemes where supported and deterministic stress loops for timer start/pause/stop/finish, shell expand/options/settings locks, save/reopen, drag auto-scroll, and teardown. Fix only reproduced violations in the owning path. Do not suppress sanitizer output or add sleeps to hide races.
  Parallelization: Wave 3 | Blocked by: 4, 6-11 | Blocks: 14-18 | Parallel with: 13
  References: `TimerEngine.swift:48-132`; `NotchWindow.swift:193-235`; `TodoListView.swift:1131-1513`; `CoreDataStack.swift`; `project.yml`
  Acceptance criteria: supported sanitizer commands exit 0 with logs; unsupported combinations are explicitly documented; stress tests prove stable owner/observer/timer/task counts and no crash/hang/data drift; any failure receives a failing test before a minimal fix.
  QA scenarios: happy — repeated lifecycle loop cleans every owned resource; failure — injected late callback/save error is observed and cannot mutate torn-down state. Evidence: `$ATTEMPT_ROOT/task-12-sanitizers/`, `task-12-stress.log`, `task-12-cleanup.txt`, `task-12-review.md`.
  Commit: N | test(runtime): gate lifecycle and concurrency faults

- [ ] 13. Remove only characterized dead state and proven duplicate responsibility
  What to do / Must NOT do: Build a candidate ledger with constructor/caller evidence, `DESIGN.md` compatibility status, characterization, and deletion risk. Remove confirmed unreachable `ToggleChevronView`, `FocusablePanel`, and write-only `TimerView.durationInput` only if fresh references and tests confirm; classify `newBackgroundContext`, `chevronString`, palette/default/log APIs individually. Do not delete protected legacy heatmap/log/slot surfaces.
  Parallelization: Wave 3 | Blocked by: 1, 4, 6-11 | Blocks: 14-18 | Parallel with: 12
  References: `ToggleChevronView.swift`; `FocusablePanel.swift`; `TimerView.swift:12-14,537-572`; `CoreDataStack.swift:28-32`; `TimerEngine.swift:167`; `DESIGN.md:61-65`
  Acceptance criteria: each deletion has a zero-production-reference proof plus characterization and pre/post dual builds; candidate ledger records keep/delete rationale; source/test LOC decreases or stays neutral; no compatibility symbol named by the design contract is removed.
  QA scenarios: happy — removed types/state have zero references and all app/test scenarios remain green; failure — deliberately include a protected symbol in the candidate checker and require rejection. Evidence: `$ATTEMPT_ROOT/task-13-ledger.md`, `task-13-characterization.log`, `task-13-reference-proof.txt`, `task-13-review.md`.
  Commit: N | refactor(cleanup): delete only proven unreachable code

- [ ] 14. Freeze dual build/test parity, coverage, project generation, and CI commands
  What to do / Must NOT do: Make `project.yml` reproducibly generate the checked-in project; add CI-ready clean SwiftPM/Xcode test/build, coverage, Release build, sanitizer, and manifest checks using existing tools. Set coverage expectations around risky persistence/lifecycle/domain modules, not an arbitrary whole-UI percentage. Do not add a hosted service credential or make SwiftPM success stand in for Xcode.
  Parallelization: Wave 3 | Blocked by: 4, 6-13 | Blocks: 15-18
  References: `Package.swift`; `project.yml`; `NativeScheduler.xcodeproj`; `Tests/NativeSchedulerTests`
  Acceptance criteria: clean commands execute named tests in both graphs at one digest; two XcodeGen runs are identical; coverage report includes the new failure/state transitions; Release and Debug compile under Swift 6; CI script exits nonzero on stale generated project or digest mismatch.
  QA scenarios: happy — clean checkout-equivalent copy runs the full command set; failure — mutate a copied generated project and require parity gate failure. Evidence: `$ATTEMPT_ROOT/task-14-quality-gates.md`, `task-14-coverage/`, `task-14-project-diff.txt`, `task-14-review.md`.
  Commit: N | build(quality): make both project graphs reproducible

- [ ] 15. Build a secret-safe direct-distribution archive and DMG pipeline
  What to do / Must NOT do: Add minimal release scripts/config/docs for Release archive/export, nested signing order, DMG staging/creation/signing, `notarytool submit --wait`/log, stapling, `codesign`/`spctl` validation, and final hashes. Support an explicit development/ad-hoc mode for local verification and a Developer ID mode that requires operator-provided non-secret identifiers plus keychain-held credentials. Never log secrets or label ad-hoc output releasable.
  Parallelization: Wave 4 | Blocked by: 14 | Blocks: 18 | Parallel with: 16, 17
  References: `project.yml:9-42`; Apple notarization, packaging, Developer ID, and Code Signing Guide URLs recorded in the draft; local `0 valid identities found` baseline
  Acceptance criteria: shell syntax/static checks pass; development mode produces deterministic `.xcarchive`, `.app`, and read-only DMG hashes and verifies its declared signature class; missing identity/notary profile fails before packaging with a clear non-secret message; Developer ID mode commands preserve notarization request/log/staple/Gatekeeper evidence when credentials exist.
  QA scenarios: happy — build/mount/copy/launch the disposable development DMG and verify exact payload; failure — missing identity, post-sign mutation, wrong bundle/version, or rejected notary result prevents release status. Evidence: `$ATTEMPT_ROOT/task-15-dev-candidate/`, `task-15-negative-controls.txt`, `task-15-secret-scan.txt`, `task-15-review.md`.
  Commit: N | build(release): add direct archive notarization and DMG workflow

- [ ] 16. Add a separate, limited Mac App Store compatibility configuration
  What to do / Must NOT do: Add the minimum App Sandbox entitlements/configuration and truthful privacy manifest/metadata needed to compile and inspect a Store candidate; map Core Data/log container paths and `SMAppService` behavior; keep direct distribution configuration separate. Do not claim App Store Connect upload, App Review, purchase receipt logic, or actual Store release.
  Parallelization: Wave 4 | Blocked by: 14 | Blocks: 18 | Parallel with: 15, 17
  References: `project.yml`; `Resources/Info.plist`; `CoreDataStack.swift`; `DailyLogWriter.swift`; `AppDelegate.swift:14-19`; Apple App Sandbox/privacy manifest/SMAppService sources recorded in the draft
  Acceptance criteria: generated Store configuration has `com.apple.security.app-sandbox=true`, minimum entitlements, no debug entitlement, correct privacy manifest placement, container-safe temporary persistence/log tests, and a compile-time/credential-free archive inspection; compatibility matrix lists every unverified credential/App Review behavior.
  QA scenarios: happy — sandbox test build writes only inside its disposable container and passes structural entitlement/privacy inspection; failure — an out-of-container fixture or forbidden entitlement is rejected. Evidence: `$ATTEMPT_ROOT/task-16-mas-matrix.md`, `task-16-entitlements.txt`, `task-16-privacy.txt`, `task-16-sandbox-smoke.md`, `task-16-review.md`.
  Commit: N | build(macos): add a separate Store compatibility variant

- [ ] 17. Produce the provenance, rights, third-party, name-screening, and secret-hygiene release report
  What to do / Must NOT do: Re-run exact local Git/session/metadata/public identifier searches, inventory source/dependencies/assets/system symbols, and publish one of two verdicts: `VERIFIED` only with positive upstream-license or written-ownership evidence, otherwise `BLOCKED — rights unproven`. Record the plaintext shell-history credential incident as “rotate/revoke and remove with user authorization” without copying its value. Product-name search is screening only. Do not add a LICENSE or claim ownership.
  Parallelization: Wave 4 | Blocked by: 1, 14 | Blocks: 18 | Parallel with: 15, 16
  References: `prompt.md`; `.claude/agent-memory/cs-dev-optimizer/project_nativescheduler.md:50`; parent Git root; GitHub licensing guidance; final provenance investigator report
  Acceptance criteria: report includes search methods/date, exact negative evidence, frozen source manifest, dependency/asset inventory, unresolved ownership and trademark risks, distribution decision, and required next legal evidence; secret scan of the repository/evidence is clean and never prints secret values. Fixture verdicts are parser/test results only and can never change the real workspace verdict. Real `VERIFIED` requires positive evidence tied to this project's source/authorship/license.
  QA scenarios: happy (test-only) — feed an isolated fixture repository with a pinned permissive license and obtain the expected fixture verdict/obligations while the workspace verdict stays unchanged; failure — the current no-license workspace must produce BLOCKED and cannot be overridden by a fixture, new LICENSE, empty inventory, or search miss. Evidence: `$ATTEMPT_ROOT/task-17-provenance-rights.md`, `task-17-inventory.txt`, `task-17-verdict-fixtures.log`, `task-17-secret-scan.txt`, `task-17-review.md`.
  Commit: N | docs(release): publish evidence-bound rights and hygiene status

- [ ] 18. Assemble and audit the final development candidate and conditional commercial-release chain
  What to do / Must NOT do: From the frozen Todo 14 digest, build the direct development candidate and Store compatibility candidate, run all structural/runtime/package checks, and generate a release-status manifest. Run Developer ID signing/notarization/stapling only if Todo 17 is VERIFIED and required identities/profiles exist; otherwise keep the commercial row BLOCKED while marking completed engineering evidence separately. Never weaken the gate to finish.
  Parallelization: Wave 4 | Blocked by: 15-17 | Blocks: F1-F4
  References: Todo 15/16 pipelines; Todo 17 rights verdict; Apple packaging/notarization/Gatekeeper sources; `project.yml`
  Acceptance criteria: development app/DMG mount/copy/launch on a disposable account/home, exact source/archive/app/DMG hashes, entitlements/no-`get-task-allow`, nested signature, version/bundle metadata, and cleanup all pass. Commercial release is `READY` only with Developer ID identity, accepted notary ID/log, stapler validation, Gatekeeper approval, and rights VERIFIED; otherwise it is explicitly BLOCKED with no distributable claim.
  QA scenarios: happy — exact development DMG survives mount/copy/first launch and retains data/recovery behavior; failure — tamper copied DMG/app, mismatch source digest, missing rights, or missing credentials and require release rejection. Evidence: `$ATTEMPT_ROOT/task-18-release-manifest.json`, `task-18-dev-qa.md`, `task-18-commercial-gate.md`, `task-18-cleanup.txt`, `task-18-review.md`.
  Commit: N | build(release): freeze the audited candidate chain

## Final verification wave
> Runs in parallel after ALL todos. ALL must APPROVE. Surface results and wait for the user's explicit okay before declaring complete.
- [ ] F1. Plan compliance audit
- [ ] F2. Code quality, security, persistence, and license review
- [ ] F3. Fresh exact-app manual, visual, accessibility, and performance QA
- [ ] F4. Release artifact, scope fidelity, and rights gate audit

F1 acceptance: an independent gate reviewer checks P0 and Todos 1-18 dependency order, TDD/characterization/measurement evidence, manifests, cleanup, and every Must/ Must-NOT item at the final digest. Evidence: `$ATTEMPT_ROOT/F1-plan-compliance.md`.

F2 acceptance: independent reviewers read every changed file/test/script/config and audit Swift concurrency/context ownership, store preservation, failure truthfulness, login state, lifecycle cleanup, shell/script secret safety, entitlements/privacy, dead-code proof, and the rights verdict. No high/medium unresolved finding. Evidence: `$ATTEMPT_ROOT/F2-code-security-license.md`.

F3 acceptance: a fresh QA executor builds the exact final app in new DerivedData, proves isolated routing and payload identity, then observes collapsed/expanded/hover/options/category-theme/Timer/Dayline live progression/todo/settings/restart/recovery/error/keyboard/AX/Reduce Motion and the six performance scenarios. Two independent visual reviewers pass owner-window raw/composite captures; production data/settings remain unchanged; every owned resource is cleaned. Evidence: `$ATTEMPT_ROOT/F3-manual-qa.md`, `F3-visual-a.md`, `F3-visual-b.md`, `F3-performance/`, `F3-cleanup.txt`.

F4 acceptance: after F3 cleanup, an independent gate reviewer rebuilds and audits source→archive→app→DMG hashes, signing class, entitlements/privacy/version, mount/copy/launch, tamper negatives, Developer ID/notary/staple/Gatekeeper evidence when available, MAS compatibility matrix, and the provenance verdict. It must report engineering PASS separately from commercial READY/BLOCKED and may never convert missing rights/credentials into READY. Evidence: `$ATTEMPT_ROOT/F4-release-rights-audit.md`.

## Commit strategy
- Do not stage or commit: `/Users/chan/Projects` has no `HEAD` and `native_schedular/` plus unrelated siblings are untracked.
- Every writer owns an explicit path allowlist and records recursive pre/post SHA-256 manifests. Independent verification rejects unowned additions, edits, deletions, generated drift, and evidence created before its input artifact.
- Preserve small reversible edits. No broad formatter/generator may write outside the isolated target; only the reviewed `project.yml` regeneration result is copied into the checked-in project.

## Success criteria
- The successor Dayline plan is genuinely complete at the current digest: live timer-owned sessions reproject once per second without refetching, options/category menus keep the shell expanded, shared category theme color reaches timer border/collapsed ring/Dayline, expanded-only five-day history is verified, and successor Todo 10/F1–F4 have fresh exact-bundle evidence.
- Normal persistence loads/saves/reopens; save and login-item errors are visible and truthful; termination orders durable session state before logging; an invalid store plus sidecars remains byte-identical in a recovery bundle and the app stays usable in a recovery surface without automatic reset.
- SwiftPM and generated Xcode unit/UI tests, clean Debug/Release builds, project parity, focused coverage, supported sanitizers, lifecycle stress, and native smoke all pass at one recursive source digest.
- All six resource scenarios have reproducible three-run baselines; only measured production regressions are changed and identical after-runs prove improvement without behavioral loss. No accumulating timer, observer, task, window, or helper remains.
- Dead/duplicate cleanup is candidate-by-candidate, characterization-protected, and smaller; every `DESIGN.md` compatibility surface remains unless separately proven and approved.
- A deterministic development `.app`/DMG and separate MAS compatibility candidate pass structural and real mount/copy/launch checks. Secret-safe Developer ID/notary/staple commands are ready, but commercial release is never declared without rights, credentials, notarization, and Gatekeeper evidence.
- The final provenance result explicitly reports that no GitHub upstream/license was recoverable unless new positive primary evidence appears. Current expected verdict is `BLOCKED — rights unproven`; commercial distribution requires documented authorship/assignment or written permission. The exposed shell-history API credential is reported for immediate revocation/rotation without value disclosure.
- F1-F4 unconditionally approve the engineering result at the frozen digest; temporary QA homes, processes, mounts, DerivedData, login/service fakes, and leases are cleaned, and user production persistence/preferences/TCC/system settings remain unchanged.
