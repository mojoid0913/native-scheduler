# Ultrawork Notepad — 카테고리 색상과 타이머 강조색 일치
Started: 2026-08-01T00:17:58+09:00

## Plan (exhaustively detailed)
1. CLI/Codex 목표, manifest, git, process 환경을 확인한다.
2. H1 expanded border, H2 VM ownership, H3 notch ring을 병렬 조사하고 root source로 대조한다.
3. 구현 전 Study/Default 실제 GUI를 RED로 캡처한다.
4. 기존 디자인 토큰을 DESIGN.md와 design state에 문서화한다.
5. 동일 카테고리 색상 source를 expanded/notch 표면에 연결하는 최소 구현을 위임한다.
6. diff, tests, build, diagnostics를 root가 독립 확인한다.
7. Study/Default 실제 GUI를 GREEN으로 캡처하고 색상 픽셀을 검증한다.
8. QA 자원을 정리하고 두 독립 visual review 및 final quality gate를 실행한다.
9. ulw-loop evidence/checkpoint와 Codex goal을 완료한다.

## Success criteria + QA scenarios
- Tier LIGHT: 기존 SwiftUI 배선 버그이며 스키마, 새 계층, 외부 통합이 없다.
- C001: 실제 앱에서 Study #FFA94D 선택 후 5분 타이머를 실행한다. 카테고리 점, 큰 타이머 진행 테두리, 접힌 notch 링이 같은 #FFA94D이면 PASS. RED/GREEN expanded/collapsed PNG와 pixel transcript를 남긴다.
- C002: Default로 타이머를 실행한다. 두 타이머 강조 표면이 #3A3A3A로 동일 폴백하고 Default label/상태 의미/안정성이 유지되면 PASS. RED/GREEN default PNG와 regression transcript를 남긴다.
- C003: `swift test --package-path NativeScheduler`, launchable app build, 실제 short timer start/pause/resume/finish가 모두 통과하고 완료 시 ring이 사라지며 기존 completion 의미가 유지되면 PASS.
- Failing-first: view wiring seam이 없으므로 구현 전 실제 GUI가 RED proof다.
- WHEN TO STOP: Study와 Default에서 expanded/notch 강조색이 동일하고 fresh GUI evidence, cleanup, independent review, final checkpoint가 모두 통과하는 즉시 멈춘다.

## Skills selected
- ultrawork, ulw-loop, debugging, frontend, visual-qa, git-master.
- perfection은 native SwiftUI에서 Lighthouse/React가 비적용이며 design-system compliance 원칙만 적용.
- programming은 Swift reference가 없어 비적용.
- image-to-code는 새 디자인 재현이 아닌 정확한 버그 수정이라 비적용.

## Team decision
OFF: 구현은 같은 상태 계약을 건드리는 하나의 작은 응집 단위다. 세 read-only hypothesis investigation만 병렬화한다.

## Now
구현 전 실제 macOS GUI RED 증거를 캡처한다.

## Todo
- RED Study/Default capture
- DESIGN.md/state
- delegated implementation
- root verification
- GREEN Study/Default + regression
- cleanup
- dual visual QA
- final quality gate/checkpoint

## Findings
- 2026-08-01 H1 confirmed: `TimerView.swift:84,88` hard-code blue.
- 2026-08-01 H2 stale VM refuted: controller owns one VM; NotchView cannot access category.
- 2026-08-01 H3 confirmed: `NotchTimerSnapshot` lacks category and `NotchView.swift:161,165` hard-code blue.
- 2026-08-01 root cause: both timer presentation paths bypass `CategoryEntity.colorHex`; category persistence itself is not at fault.
- 2026-08-01 environment: native macOS 14 SwiftUI/AppKit; parent git has no HEAD and unrelated untracked projects; PID 23887 predates QA and must be preserved.
- 2026-08-01 notepad location: mandatory mktemp path was created and initialized, but post-edit LSP cannot process paths outside cwd; this workspace continuation notepad is used for append-only state.

## Learnings
- Category color is data identity; completion/warning colors remain separate state semantics.
- A collapsed native shell needs explicit category state because it does not render the expanded TimerView.

## Transition 2026-08-01T00:31:00+09:00
- Completed: implementation-before RED capture.
- Evidence: `red-expanded.png`, `red-collapsed.png`, `red-pixels.txt`.
- Observed: Study swatch #F7BB72 versus expanded/notch #4DA3F9 after screenshot color management.
- Capture path for GREEN: ScreenCaptureKit `captureImage(in:)` on the 816x404 screen region after initializing `NSApplication.shared`; direct window capture is invalid.
- Cleanup: no QA-owned app process; pre-existing PID 23887 preserved.
- Now: extract existing dark tokens and relevant category/timer primitives into `DESIGN.md` and `.omo/frontend-design/state.md` before SwiftUI edits.

## PIN 2026-08-01T00:32:36+09:00
- Command: `swift test --package-path NativeScheduler --filter 'NotchShellTests|TimerProgressTests'`.
- Result: PASS, 7 XCTest cases, 0 failures, unchanged product code.
- Contract pinned: notch geometry/hover state and timer progress fraction.
## Design contract locked
- `DESIGN.md` and `.omo/frontend-design/state.md` now lock the existing #000/#111 shell, one resolved category hue across selector/expanded/collapsed progress, #3A3A3A default fallback, and independent status colors.
- Root independently read both files and verified all mandatory sections and exact RED/GREEN evidence paths before implementation.
## Implementation and automated verification
- RED: `test-red.txt` records the regression test failing on the pre-fix snapshot API (`extra argument 'categoryColorHex'`, exit 1).
- GREEN: selected category hex now drives `TimerView` progress and travels through `NotchTimerSnapshot` to `NotchView`; nil uses `Color.nsDefaultSlot.hexString`.
- Root reran `swift test --package-path NativeScheduler` on final source: 26 tests, 0 failures, exit 0 at 2026-08-01 00:49:57 KST.
- Worker reports SourceKit clean on all changed Swift files and `swift build --package-path NativeScheduler` exit 0.
- Xcode DerivedData build attempt owned by root stalled at external clang discovery with no compilation after ~2 minutes; root terminated only owned PID 3871. GUI QA uses the verified SwiftPM executable instead.
## GUI QA correction
- Round-1 `green-*` files are not valid GREEN: CGWindow ownership proved the QA clicks/capture targeted pre-existing PID 23887 after the new direct executable exited.
- Root restored user window PID 23887 from QA-moved `{400,300}` to original `{552,0}` and verified it. Next run must use a uniquely bundled QA app and bind every capture to its owner PID.
