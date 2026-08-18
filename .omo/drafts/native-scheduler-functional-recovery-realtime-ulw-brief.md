# NativeScheduler realtime functional recovery

Create exactly one aggregate HEAVY goal that executes the approved plan at `.omo/plans/native-scheduler-functional-recovery-realtime.md`.

Outcome: preserve the approved design and all existing user data while restoring every accepted Tasks, Timer, Dayline, Settings, shell, persistence, and lifecycle behavior. Local Task and Settings mutations must become visible by the next main-loop render with deterministic persistence confirmation or visible rollback. Timer mutations must publish model authority before returning, and relevant Dayline state must update exactly once. The final exact Xcode app artifact must pass isolated and normal-profile real-app QA and remain running for the user.

Use exactly these four binary success criteria:

1. Persistence and realtime state ordering: failing-first deterministic XCTest coverage proves save completion, optimistic publish, rollback, mutation revision ordering, one ticker, and exactly-once relevant Dayline refresh with no sleeps or polling.
2. Complete product behavior: computer-use QA on an isolated HOME drives shell expansion/collapse, disclosure rail, every Task CRUD/folder/drag/reorder action, every Timer mode/lifecycle/category action, Dayline compact/five-day/detail/live behavior, Settings category/default/launch-at-login behavior, bad input/failure paths, quit/relaunch persistence, and captures non-empty action logs plus screenshots.
3. Engineering gates: changed-file LSP diagnostics are clean, `swift test --package-path NativeScheduler` passes all tests with zero failures including the two previously failing NotchShell tests, and the approved Xcode Debug build succeeds without weakening tests.
4. Exact final artifact and data safety: isolated and normal-profile QA use the same recorded app SHA-256 without rebuilding; before/after normal-profile data and preferences are preserved except cleaned QA records; temporary processes/stores are removed; independent reviewers approve; only the verified normal-profile app remains running.

Do not create separate goals for plan headings, references, commands, QA substeps, or final reviewers. Those are tasks/evidence inside the one aggregate goal.
