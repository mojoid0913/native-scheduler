# Final manual QA: frozen hover fix

Verdict: **PASS**. Privacy-safe owner-only captures were taken with `screencapture -x -l 80740`; no unrelated desktop content is present. Frozen binary SHA-256 `4358124481925bbf403a401098b7ada12a6f7f05628240ee5cb4e41ac81c3609`; source hashes matched freeze-manifest: NotchWindow `890c5daa5cd2e49e3958d261d7352f549c9fe2c5d8822282c3b84f37ed1d82ec`, NotchView `7fd5430ccf291e89011c3864da65776f0cc27a21133b992705ccb8c6c46c4ef7`, NotchShellTests `26e56e4dd06db0ef1869cc1f512d7c3ae9bb492f401643b18a1b4ba560d4e68d`.

Surface/invocation: persistent PTY launch `./NativeScheduler/.build/arm64-apple-macosx/debug/NativeScheduler`; PID `26646`; CoreGraphics resolved owner window ID `80740`, bounds `{552,0,816,404}`. Helper performed both `CGWarpMouseCursorPosition` and posted `CGEvent(mouseMoved)`. Each cycle used enter `(960,40)`, wait 1s, owner-only capture; exit `(80,800)`, wait 1s, owner-only capture.

## manualQa

### surfaceEvidence

| scenario | criterion | surface | exact invocation | verdict | artifactRefs |
|---|---|---|---|---|---|
| C001 | visible hover expands | Quartz owner window 80740 | move `(960,40)`; `screencapture -x -l 80740 cycle-1-expanded.png` | PASS | A1 |
| C002 | exit collapses | Quartz owner window 80740 | move `(80,800)`; `screencapture -x -l 80740 cycle-1-collapsed.png` | PASS | A2 |
| C003 | three complete cycles on one PID/window | Quartz owner window 80740 | repeated enter/exit for cycles 1-3 | PASS | A1-A6 |
| C004 | expanded surface content/CJK unclipped | owner-only screenshot | opened cycle-3-expanded.png in image viewer | PASS | A5 |
| C005 | process lives before cleanup | process/window | `pgrep -x NativeScheduler`; CoreGraphics window listing | PASS | A7 |

### adversarialCases

| scenario | criterion | adversarial class | expected behavior | verdict | artifactRefs |
|---|---|---|---|---|---|
| ADV-1 | repeated transitions | stability | all 3 enter/exit cycles transition correctly | PASS | A1-A6 |
| ADV-2 | CJK text | clipping/layout | Korean labels and task text remain readable | PASS | A5 |
| ADV-3 | lifecycle | cleanup | process exits, pointer restored, helper removed | PASS | A8 |
| ADV-4 | owner capture privacy | evidence isolation | PNG contains only NativeScheduler window | PASS | A1-A6 |

## Dimensions and hashes

Expanded captures are 1632x808; collapsed captures are 440x76. SHA-256: cycle-1-expanded `7a758ab4240971a7a2c7ac6a00bc8d4e9d443fbac4fe42b1e244265621b79ba6`; cycle-1-collapsed `eddffe085be61d3f50bbe9151ac61a14f869b333d8246e736867085e133a6356`; cycle-2-expanded `7a758ab4240971a7a2c7ac6a00bc8d4e9d443fbac4fe42b1e244265621b79ba6`; cycle-2-collapsed `eddffe085be61d3f50bbe9151ac61a14f869b333d8246e736867085e133a6356`; cycle-3-expanded `7a758ab4240971a7a2c7ac6a00bc8d4e9d443fbac4fe42b1e244265621b79ba6`; cycle-3-collapsed `eddffe085be61d3f50bbe9151ac61a14f869b333d8246e736867085e133a6356`.

### artifactRefs

| id | kind | path |
|---|---|---|
| A1 | owner-only PNG, cycle 1 expanded | `cycle-1-expanded.png` |
| A2 | owner-only PNG, cycle 1 collapsed | `cycle-1-collapsed.png` |
| A3 | owner-only PNG, cycle 2 expanded | `cycle-2-expanded.png` |
| A4 | owner-only PNG, cycle 2 collapsed | `cycle-2-collapsed.png` |
| A5 | owner-only PNG, cycle 3 expanded (final visual inspection) | `cycle-3-expanded.png` |
| A6 | owner-only PNG, cycle 3 collapsed | `cycle-3-collapsed.png` |
| A7 | runtime/window liveness | `process-live.txt` |
| A8 | cleanup receipt | `cleanup-receipt.txt` |

Cleanup verified: PID absent, pointer restored to `(500,500)`, `/tmp/native-scheduler-hover-final-manual` removed, and no helper source remains in the owned evidence directory.
