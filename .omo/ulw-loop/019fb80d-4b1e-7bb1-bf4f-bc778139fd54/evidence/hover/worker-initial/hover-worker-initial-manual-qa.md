# NativeScheduler Hover Manual QA

Binary: `/Users/chan/Projects/native_schedular/NativeScheduler/.build/arm64-apple-macosx/debug/NativeScheduler`  
SHA-256: `40af10f8c1c97a5dd878a1550e8ca5780aa860d41b0be31ad3ba65a6448bc30f`  
Launch PID: `60767`; CGWindow owner ID: `80632`; initial bounds: `816x404`.

## Results

- **C001 FAIL** — invocation: `PointerHold hold 960 40 1800`, then `screencapture -x -l 80632 c001-expanded.png` after 500 ms. Captured owner-only PNG was `440x76` (black/no expanded content), not the required `1632x768` visible panel. Exact first failure.
- **C002 PASS** — invocation: `PointerHold hold 80 800 1400`, owner-only capture after 500 ms. PNG was `440x76`; PID remained alive.
- **C003 FAIL** — three cycles of enter `PointerHold hold 960 40 1100` and exit `PointerHold hold 80 800 1100`, captures after 500 ms. All three enter captures remained `440x76` instead of `1632x768`; exits were `440x76`; process remained alive before teardown.

## Artifact paths

- Captures: `/Users/chan/Projects/native_schedular/.omo/ulw-loop/019fb80d-4b1e-7bb1-bf4f-bc778139fd54/evidence/hover/worker-initial/c001-expanded.png`, `c002-collapsed.png`, and `c003-cycle{1,2,3}-{expanded,collapsed}.png`.
- Invocation/action logs: `action.log`, `c001-helper.log`, `c002-helper.log`, and `c003-cycle{1,2,3}-{enter,exit}-helper.log` in the same directory.
- Verification: `signatures.txt` (file, dimensions, SHA-256); `red-reference.txt` (pre-fix RED references).

## Cleanup receipt

`cleanup-receipt.txt` records PID `60767` terminated and absent, `/tmp/native-scheduler-ulw-hover-worker` absent, and repository temp helper directory absent. Cursor was restored by the helper after each hold.
