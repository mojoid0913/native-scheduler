# NativeScheduler — Project Management Note

> Last updated: 2026-04-12
> Audience: Developer, Designer, Reviewer

---

## 현황 요약 (Project Status) — PM 업데이트 2026-04-12

### 완료된 작업 (Resolved)

이전 sprint에서 제기된 4개 이슈가 모두 해결되었습니다.

| 상태 | 항목 | 확인 위치 |
|---|---|---|
| DONE | 쉐브론 shake 연결 | `FloatingPanelController.swift:74–76`, `MainPanelView.swift:52` |
| DONE | 타이머 완료 사운드 | `TimerEngine.swift:92–108` (NSSound.Ping + beep fallback) |
| DONE | 패널 슬라이드 애니메이션 | `FloatingPanelController.swift:111–169` (spring bezier) |
| DONE | Settings 기본 타이머 필드 | `SettingsView.swift:13–14` (@AppStorage), `TimerViewModel.swift:29–44` |
| DONE | CategoryEditorView 파일 분리 | `Features/Settings/CategoryEditorView.swift` |

### 신규 발견 버그 (Critical — 즉시 수정 필요)

리뷰어 코드 검토 결과 추가 버그 1건이 발견되었습니다. 이는 PM이 **수용**하며 v1 블로커로 분류합니다.

| 우선순위 | 버그 | 위치 | 내용 |
|---|---|---|---|
| P0-BUG | `shakeChevron()` 레이어 nil | `FloatingPanelController.swift:174` | `chevronHosting.wantsLayer`가 `true`로 설정되지 않아 `chevronHosting.layer`가 항상 `nil` → shake 애니메이션 무음 실패 |

---

## Designer 과제

**담당 범위**: 애니메이션 스펙 확정, 현재 시간 마커 재설계, 설정 UI 레이아웃 설계

### 1. 패널 슬라이드 애니메이션
- 현재: `alphaValue` 페이드 인/아웃 (`FloatingPanelController.swift:110–126`)
- 스펙: "Panel slides down/up, spring easing, 0.3s"
- **필요 작업**: `NSPanel`의 `frame.origin.y`를 애니메이션하는 방식으로 전환. expand 시 쉐브론 바 바로 아래에서 내려오고, collapse 시 위로 올라가는 슬라이드 모션. 개발자에게 frame delta 수치 전달 필요.

### 2. 히트맵 현재 시간 마커
- 현재: 현재 슬롯 셀에만 흰색 strokeBorder 적용 (`HeatmapView.swift:43–44`)
- 스펙: "Current time marker: thin vertical line on the active column"
- **필요 작업**: 현재 열(column) 전체 6개 row를 가로지르는 1pt 흰색(60% opacity) 수직선 디자인. 개발자에게 geometry 수치 전달 필요.

### 3. Settings 누락 필드 레이아웃
- 스펙: Settings에 "Default timer duration"과 "Default timer mode (Duration / End Time)" 항목 필요
- **필요 작업**: 기존 launch-at-login 토글과 categories 섹션 사이에 두 필드 배치 디자인. duration은 분 단위 stepper, mode는 segmented control 형태 권장.

---

## Developer 과제

두 작업은 서로 독립적이므로 병렬 진행 가능합니다.

### Developer A — 핵심 기능 연결 및 애니메이션 수정

**작업 1: 쉐브론 shake 연결**
- `MainPanelView.swift:22`에서 `timerVM.onTimerFinished`가 빈 클로저로 방치됨
- `FloatingPanelController.shakeChevron()`은 구현되어 있으나 호출되지 않음
- `FloatingPanelController` 인스턴스를 `MainPanelView`에 전달하거나 `@EnvironmentObject`로 공유하여 연결할 것
- retain cycle 주의 (weak 캡처 확인)

**작업 2: 타이머 완료 사운드**
- `TimerEngine.swift:91` `finish()` 메서드 내에 사운드 추가
- `NSSound(named: .ping)?.play()` 또는 `NSSound.beep()` 사용
- AppKit 요구사항: 반드시 메인 스레드에서 호출

**작업 3: 패널 슬라이드 애니메이션**
- `FloatingPanelController.swift:110–126`의 `alphaValue` 애니메이션을 `frame.origin.y` 슬라이드로 교체
- expand 전 `orderFrontRegardless()` 호출 순서 확인 (frame 이동 전에 창이 visible 상태여야 함)
- 쉐브론 패널 offset 기준으로 frame 계산 (`positionPanels()` 로직 참고)

**작업 4: 기본 타이머 설정 UserDefaults 연동**
- UserDefaults key `defaultTimerDuration` (Int, 분), `defaultTimerMode` (String) 추가
- `TimerViewModel.init()`에서 읽어 `TimerEngine.durationSeconds` 및 `engine.mode`에 적용
- `SettingsView`에서 값 변경 시 즉시 UserDefaults에 저장

---

### Developer B — Settings UI 및 파일 구조 정리

**작업 1: Settings 누락 필드 추가**
- `SettingsView.swift`에 두 필드 삽입 (launch-at-login 토글 아래, categories 섹션 위)
  - `Stepper` — "Default duration: X min", 범위 1–120, UserDefaults `defaultTimerDuration`
  - `Picker(.segmented)` — "Duration" / "End Time", UserDefaults `defaultTimerMode`
- `.onDisappear`에서 UserDefaults 저장

**작업 2: CategoryEditorView 파일 분리**
- 스펙 파일 구조: `Features/Settings/CategoryEditorView.swift` 별도 파일 필요
- `SettingsView.swift:134–169`의 `CategoryRowView` 구조체와 관련 로직을 해당 파일로 이동
- `SettingsView.swift`에서 import 없이 같은 모듈 내 접근 가능한지 확인

---

## Reviewer 과제

Developer A, B 작업 완료 후 머지 전 검토. 아래 항목을 중점적으로 확인.

### 검토 항목

**1. 쉐브론 shake 연결 (Developer A)**
- `FloatingPanelController` 참조 방식이 retain cycle을 유발하지 않는지 확인
- `shakeChevron()` 호출이 메인 스레드에서 이루어지는지 확인

**2. NSSound 사운드 호출 (Developer A)**
- AppKit 요구사항: `NSSound.play()`는 메인 스레드에서만 안전
- `TimerEngine`은 백그라운드 큐에서 실행됨 → `DispatchQueue.main.async` 래핑 확인

**3. 패널 슬라이드 애니메이션 (Developer A)**
- frame 계산이 쉐브론 패널 위치 기준으로 정확한지 확인 (`positionPanels()` 참고)
- `orderFrontRegardless()` 호출이 frame 애니메이션 시작 전에 있는지 확인
- `nonactivatingPanel` 속성이 유지되어 다른 앱의 포커스를 빼앗지 않는지 확인

**4. UserDefaults 읽기 타이밍 (Developer A)**
- `TimerViewModel.init()`에서 UserDefaults 값이 `TimerEngine.durationSeconds`에 적용되는 시점이 `engine` 인스턴스 생성 이후인지 확인
- 기본값이 없을 경우(첫 실행) fallback이 올바른지 확인

**5. CategoryEditorView 분리 (Developer B)**
- 파일 분리 후 `SettingsView.swift` 빌드가 깨지지 않는지 확인
- `CategoryRowView`의 타입 가시성(internal/public) 확인

---

## 통합 테스트 체크리스트

모든 작업 완료 후 아래 시나리오를 수동으로 확인:

- [ ] 앱 실행 → 쉐브론만 화면 최상단 중앙에 표시
- [ ] 쉐브론 클릭 → 패널이 슬라이드 다운 애니메이션으로 열림
- [ ] 타이머 시작 → 카운트다운 동작 확인
- [ ] 타이머 0:00 도달 → 사운드 재생 + 쉐브론 shake 발생
- [ ] 히트맵 현재 열에 수직선 마커 표시 확인
- [ ] Settings 열기 → 기본 타이머 시간/모드 필드 표시 확인
- [ ] 기본 설정 변경 후 앱 재시작 → 설정값 유지 확인
- [ ] 쉐브론 우클릭 → "Quit NativeScheduler" 메뉴 표시 및 종료
- [ ] **[신규]** Settings ColorPicker 탭 → popover가 올바르게 열리는지 확인 (nonactivatingPanel 포커스 충돌 여부)
- [ ] **[신규]** 완료된 Todo 항목이 리스트 하단으로 이동하는지 확인

---

## 상업적/실용적 어드바이저 리뷰 (2026-04-12)

> 작성자: Project Advisor Reviewer
> 검토 기준: 상업적 실현 가능성, 실용성, 시장 포지셔닝, 리스크

---

### 프로젝트 개요 요약

NativeScheduler는 macOS용 네이티브 플로팅 패널 앱으로, 우선순위 기반 할 일 목록, 포모도로 스타일 타이머, GitHub 히트맵 스타일의 오늘 활동 추적기를 하나의 경량 인터페이스에 통합한다. NSPanel 기반의 항상-위 (always-on-top) 플로팅 UI로 백그라운드에서 지속 실행되며, Dock/메뉴바 아이콘 없이 최소 존재감으로 동작한다. 현재 v1 핵심 구현은 완료되어 있으며 4개의 미완성 항목이 잔존한다.

---

### 강점 (Strengths)

1. **UX 차별화가 명확하다**: 메뉴바 앱이나 Dock 앱이 아닌 화면 최상단 중앙 고정 패널이라는 포지션은 시장에서 보기 드문 접근이다. 포커스를 빼앗지 않으면서 항상 접근 가능한 UX는 특히 딥 워크 사용자에게 설득력이 있다.

2. **기술적 품질이 높다**: Swift 네이티브 구현, CoreData 로컬 퍼시스턴스, 바이너리 로그 포맷의 O(1) 슬롯 접근, 이벤트 드리븐 히트맵 리드로우, 0.1% 미만 유휴 CPU 목표 등 퍼포먼스 제약이 명확하게 설정되어 있고 실현 가능하다.

3. **확장 로드맵이 현실적이다**: iCloud 동기화, 멀티데이 히트맵, iPhone 컴패니언, Shortcuts 통합 등 v2 이후 훅이 데이터 모델과 아키텍처 수준에서 미리 고려되어 있다. 과도한 v1 스코프 없이 확장성을 확보한 설계다.

4. **타깃 사용자가 뚜렷하다**: 개발자, 디자이너, 프리랜서 등 Mac을 주력으로 사용하는 지식 노동자 중 포모도로 + 할 일 관리에 관심 있는 층. 이 세그먼트는 유료 앱에 대한 지불 의향이 높고 App Store 리뷰 기여도도 높다.

5. **최소 마찰 온보딩**: Dock/메뉴바 없이 로그인 시 자동 실행, 우클릭으로만 종료하는 설계는 앱이 환경의 일부가 되도록 의도된 것으로, 장기 리텐션에 유리하다.

---

### 개선 필요 사항 (Areas for Improvement)

#### 높음 (High Priority)

**문제점**: 타이머와 할 일 목록이 완전히 독립적이다.
- **영향**: 사용자는 "지금 이 태스크를 25분 집중하겠다"는 플로우를 기대하지만, 현재는 태스크 선택과 타이머 시작이 수동으로 분리되어 있어 실사용 마찰이 높다. 경쟁 앱(Toggl Track, Timery) 대비 핵심 플로우에서 열위다.
- **권고 사항**: v1 릴리스 직후 v1.1 과제로 "할 일 항목에서 타이머 시작" 연동을 최우선 추가할 것. 데이터 모델은 이미 `category` 링크를 갖고 있어 구현 비용이 낮다. 단순히 TodoItem을 탭하면 해당 카테고리로 타이머가 세팅되는 것만으로도 UX가 크게 개선된다.

**문제점**: 오늘 하루 히트맵만 볼 수 있다.
- **영향**: 일주일치 패턴을 보지 못하면 습관 형성의 피드백 루프가 약해진다. GitHub 히트맵 컨셉의 핵심 가치(시각적 연속성)가 현재 v1에서는 발현되지 않는다. 이것이 이 앱의 핵심 차별화 요소인 만큼, 단일 일자 뷰는 설득력이 낮다.
- **권고 사항**: 바이너리 로그 파일 포맷(`mmap` 지원)이 이미 멀티데이 분석을 위해 준비되어 있다. v1.1 또는 v1.2에서 최소 7일 스크롤 가능한 히트맵을 추가하는 것을 강력 권고한다. 이것이 App Store 스크린샷에서 가장 강력한 훅이 될 수 있다.

#### 중간 (Medium Priority)

**문제점**: 수익화 모델이 정의되어 있지 않다.
- **영향**: App Store 출시 시 가격 결정, 무료/유료, freemium 여부에 대한 방향 없이는 마케팅과 기능 우선순위 결정이 어렵다.
- **권고 사항**: 초기 유료 모델($4.99–$9.99 일회성)을 권장한다. 이 가격대는 파워 유저 세그먼트의 구매 저항이 낮고, 구독 피로를 피할 수 있다. iCloud 동기화나 iPhone 컴패니언이 추가될 경우 해당 기능을 번들한 업그레이드 버전($14.99)을 고려할 수 있다.

**문제점**: macOS 14(Sonoma) 최소 타깃으로 잠재 사용자 일부가 배제된다.
- **영향**: 2026년 기준 macOS 14+ 점유율은 높지만, 기업 환경에서 OS 업그레이드가 지연되는 경우 타깃 사용자(개발자/디자이너)의 일부가 누락될 수 있다.
- **권고 사항**: macOS 13(Ventura)으로 최소 타깃을 낮추는 것을 검토한다. `SMAppService`는 macOS 13+에서 지원되므로 기술적 제약은 없다. 단, SwiftUI API 호환성을 재검토해야 한다.

**문제점**: 알림(Notification) 부재가 v1 범위에서 누락됨.
- **영향**: 패널이 접혀 있고 다른 앱에 집중하는 상황에서 타이머 완료를 쉐브론 shake로만 알리는 것은 시각적 인지가 어렵다. 소리(NSSound)는 있지만 macOS 알림 센터 연동이 없으면 전체화면 앱 사용 시 알림을 놓칠 수 있다.
- **권고 사항**: v1 완성 직후 `UserNotifications` 프레임워크를 통한 타이머 완료 알림을 v1.1에 추가할 것. 이미 Out of Scope 항목으로 인지되어 있으나, 이것은 "있으면 좋은" 수준이 아닌 기본 기대치에 가깝다.

#### 낮음 (Low Priority)

**문제점**: 멀티모니터 환경에서 기본 스크린만 지원한다.
- **영향**: 2개 이상의 모니터를 사용하는 파워 유저 중 보조 모니터를 주 작업 화면으로 쓰는 경우 쉐브론이 눈에 띄지 않는 위치에 고정된다.
- **권고 사항**: v2에서 "쉐브론이 따라올 스크린 선택" 설정을 추가하는 것을 로드맵에 포함시킬 것. `NSScreen.screens` 열거를 통해 구현 가능하다.

---

### 전략적 제언 (Strategic Recommendations)

**1. "집중 세션 기록" 스토리를 전면에 내세워라**

현재 스펙은 기능 목록에 가깝다. 마케팅 관점에서는 "오늘 내가 무엇에 몇 시간을 썼는지 한 눈에 본다"는 스토리가 핵심이다. App Store 소개문, 스크린샷, 마케팅 카피 모두 이 핵심 가치 제안을 중심으로 구성해야 한다. 히트맵이 채워져 가는 모습 자체가 가장 강력한 데모 자산이다.

**2. v1 출시와 동시에 피드백 채널을 확보하라**

Twitter/X, 인디해커스(Indie Hackers), 해커뉴스 "Show HN" 등에서 얼리어답터 피드백을 조기에 수집하는 것이 필수적이다. 특히 "타이머-할 일 연동", "멀티데이 히트맵" 요구가 얼마나 강한지 실사용자 데이터로 검증해야 v1.1 우선순위를 확정할 수 있다.

**3. 히트맵 데이터를 외부 내보내기 가능하게 하라**

바이너리 로그 포맷이 이미 준비되어 있다. CSV 또는 JSON 내보내기 기능을 v1.1에 추가하면, Notion/Obsidian 사용자 커뮤니티에서 자연스러운 확산이 일어날 수 있다. 이것은 유기적 바이럴 훅이 될 수 있다.

**4. TestFlight 베타를 통한 단계적 출시를 계획하라**

macOS 앱의 특성상 App Store 심사 없이 TestFlight로 먼저 50–100명의 베타 테스터를 모집할 수 있다. 이를 통해 실제 사용 패턴과 버그를 사전에 수집하고, 출시 시 리뷰 씨앗(seed reviews)을 확보할 수 있다.

---

### 종합 평가 (Overall Assessment)

**상업적 잠재력: 7/10**

macOS 네이티브 생산성 도구 시장은 단단한 수요가 존재하며, 앱의 기술적 완성도와 UX 차별화 포인트는 실제 판매로 이어질 기반이 있다. 단, 현재 v1 스펙만으로는 타이머-할 일 연동 부재와 오늘 히트맵만 지원한다는 제약이 첫인상을 약화시킬 수 있다. v1.1에서 이 두 항목이 보완되면 8–9점 수준으로 올라갈 수 있다.

**실용적 유용성: 8/10**

포모도로 타이머와 일일 활동 시각화의 조합은 실사용에서 검증된 생산성 패턴이다. 플로팅 패널 UX는 실제로 다른 앱과 함께 사용할 때 방해가 최소화되어 있어 실용적이다. 다만 타이머 완료 알림의 신뢰성(전체화면 앱 상황)이 사용성의 약점이 될 수 있다.

**핵심 성공 요인**:
- v1 출시 품질(현재 4개 버그 해결)이 App Store 첫 리뷰를 결정한다
- 멀티데이 히트맵이 "킬러 스크린샷"이 될 수 있으며, 이것이 다운로드 전환율을 좌우한다
- 타이머-할 일 연동은 리텐션을 결정하는 핵심 플로우다

**모니터링해야 할 리스크**:
- Apple이 `NSPanel` floating level 정책을 변경하거나 macOS 업데이트에서 동작이 깨질 위험 (macOS 앱의 고질적 취약성)
- 유사 컨셉 앱(Klokki, Timing, Session)이 유사 기능을 선점하거나 업데이트할 위험
- App Store 심사에서 "LSUIElement" 앱에 대한 특이 심사 기준 적용 가능성 (전례는 있으나 드뭄)

---

## 실용적 디자인 리뷰 (2026-04-12)

> 작성자: Project Advisor Reviewer
> 검토 기준: UI/UX 실용성, 레이아웃 효율성, macOS HIG 준수, 접근성, 경쟁 앱 대비 차별화
> 검토 대상 파일: MainPanelView.swift, HeatmapView.swift, TimerView.swift, TodoListView.swift, SettingsView.swift, Colors.swift, FloatingPanelController.swift

---

### 1. 플로팅 패널 전체 레이아웃 — 정보 밀도와 공간 활용

**현황 파악**

`MainPanelView.swift`의 루트 레이아웃은 `HStack(alignment: .top, spacing: 10)`으로 좌(Todo)·우(Heatmap+Timer)의 2컬럼 구조다. 전체 패널 사이즈는 860×460pt이며, Todo 영역은 `minWidth: 200, maxWidth: 240`으로 고정되고 나머지 공간을 Heatmap+Timer가 차지한다.

**문제점과 영향**

- **좌측 Todo 패널 폭이 과소하다.** 최대 240pt는 12글자 안팎의 태스크 제목만 온전히 표시할 수 있다. 실사용자의 태스크 제목("Fix login redirect after OAuth token refresh")은 `lineLimit(1)` 트런케이션에 걸려 가독성이 떨어진다. 더 심각한 것은 드래그 핸들이나 삭제 스와이프를 위한 여유 공간이 부족해 인터랙션 정확도가 낮아진다는 점이다.
- **우측 영역의 수직 순서가 인지 흐름에 역행한다.** Heatmap(결과/기록)이 Timer(현재 행동) 위에 위치한다. 사용자의 실제 행동 순서는 "지금 무엇을 할지 결정(Todo) → 타이머 시작(Timer) → 완료 후 기록 확인(Heatmap)"이다. Timer를 Heatmap 위로 올리거나, 혹은 우측 상단에 Heatmap·하단에 Timer를 배치하더라도 시각적 강조를 Timer에 두는 방식이 맥락에 맞다.
- **12pt 패딩이 공간을 추가로 잠식한다.** `MainPanelView`의 `padding(12)`와 각 컴포넌트(`HeatmapView`, `TimerView`, `TodoListView`)의 내부 padding이 중첩되어 실제 콘텐츠 영역이 예상보다 협소해진다. 특히 Todo 리스트에서 리스트 항목과 Add task 필드 사이의 공간 배분이 어색하게 느껴질 수 있다.

**권고 사항**

- Todo 열 최대 폭을 `maxWidth: 280`으로 확대하거나, 패널 전체 폭을 920pt로 소폭 늘리는 방안을 검토한다. 860pt 제약은 스펙 고정값이지만, 패널을 중앙 정렬로 표시하는 특성상 10pt 내외 폭 확장은 시각적 변화가 거의 없다.
- 우측 컬럼의 VStack을 Timer → Heatmap 순으로 재배치한다. Timer가 우측 상단을 차지하면 시선이 자연스럽게 "좌(할 일) → 우(지금 집중할 타이머)"로 흐르고, Heatmap은 하단에서 배경 맥락으로 기능한다.

---

### 2. 히트맵 영역 — 시각적 계층 구조와 정보 전달

**현황 파악**

`HeatmapView.swift`는 6×24 그리드를 `VStack(spacing: 2)` + `HStack(spacing: 2)`로 구성하고, 상단에 시간 레이블(00, 06, 12, 18), 하단에 현재 시간 수직 마커를 ZStack으로 오버레이한다. 배경은 `Color.nsSurface(#111111)`, 비활성 셀은 `#3A3A3A`, 활성 셀은 카테고리 컬러 풀 오파시티다.

**강점**

현재 시간 마커 구현(`currentTimeMarker`)이 스펙 그대로 1pt 흰색 60% 오파시티 수직선으로 정확히 구현되어 있다. `allowsHitTesting(false)`로 마우스 이벤트를 그리드에 통과시키는 세심함도 좋다. `.help()` 툴팁 문자열도 "14:20–14:30 · Deep Work (18 min)" 형식으로 정보가 충분하다.

**문제점과 영향**

- **시간 레이블 밀도가 낮다.** 현재 0, 6, 12, 18시만 표시되며 나머지 20개 컬럼에는 레이블이 없다. 사용자가 특정 셀에 마우스를 올리지 않는 한 "이 색 블록이 몇 시 활동인지" 즉각 파악하기 어렵다. 작업 흐름 중 훑어보기(glance)가 주 사용 패턴인데 현재 레이블 밀도는 그 요구를 충족하지 못한다.
- **카테고리 풀 오파시티는 고밀도 환경에서 시각적 피로를 준다.** 다수의 카테고리가 활성화된 상태에서 히트맵이 채워지면, 여러 원색이 나란히 배치되어 눈이 피로해진다. GitHub 히트맵이 단일 색상의 채도 단계를 쓰는 이유가 이 때문이다. 카테고리 컬러 자체를 바꾸기 어려우므로, 활성 셀에 약한 오파시티(예: 85%)를 적용하고 hover 시 100%로 올리는 방식을 고려할 수 있다.
- **6×24 그리드의 세로 방향 의미가 직관적이지 않다.** row가 "같은 시간 내 10분 슬롯"을 뜻한다는 것을 처음 보는 사용자가 이해하기 어렵다. 좌측에 "0m, 10m, 20m, 30m, 40m, 50m"과 같은 10분 단위 row 레이블을 추가하면 이해도가 높아진다. 레이블 폭은 16pt 내외로 충분하며, 총 그리드 폭 증가는 최소화된다.
- **비활성 기간(미래 슬롯)과 활성 기간의 구분이 미흡하다.** 미래 시간의 셀은 `#3A3A3A`로 과거의 비활동 슬롯과 동일한 색상이다. 현재 시간 이후 슬롯에 더 어두운 색(`#252525`)을 적용해 "아직 일어나지 않은 시간"임을 시각적으로 구분하면 히트맵 읽기가 명확해진다.

**권고 사항**

- 시간 레이블을 매 3시간마다(00, 03, 06, ... 21) 표시하거나, 현재 시간 레이블만 강조 표시(컬러: `nsChevron`)하는 방식으로 밀도를 높인다.
- 좌측 row 레이블("0", "10", "20", "30", "40", "50") 또는 "m" 단위 표기를 추가해 그리드 의미를 명확히 한다.
- 미래 슬롯 색상을 `#252525`로 낮춰 과거·현재와 시각적으로 구분한다.

---

### 3. 타이머 영역 — 시각적 계층 구조와 인터랙션 패턴

**현황 파악**

`TimerView.swift`는 VStack으로 (1) 모드 토글, (2) 시간 입력, (3) 32pt 카운트다운 숫자, (4) 카테고리 셀렉터, (5) 제어 버튼을 수직 배열한다. 배경은 `nsSurface`, 패딩 12pt.

**강점**

- `.nonactivatingPanel` 환경에서 `DatePicker(.compact)`와 `TextField`를 사용한 것은 적절한 선택이다. 특히 DatePicker에 `.colorScheme(.dark)` 강제 적용은 라이트 모드 macOS에서의 렌더링 깨짐을 방지하는 실용적 처리다.
- 카운트다운 숫자 `32pt, .thin, .monospaced`는 흑색 배경 위 얇은 모노스페이스 폰트로 세련된 인상을 주면서 가독성도 충분하다.
- 타이머 완료 시 숫자를 `.red`로 전환하는 것은 간결하고 효과적인 피드백이다.

**문제점과 영향**

- **카운트다운 숫자(32pt)가 시각적 계층에서 압도적이어야 하는데, 모드 토글과 시간 입력이 그 위에 위치해 사용자 시선이 분산된다.** 타이머의 핵심 정보는 "지금 얼마나 남았는가"인데, 이 정보가 3번째 요소로 내려가 있다. 이상적인 순서는 카운트다운 숫자 → 카테고리 → 제어 버튼 → (접히는 섹션으로) 모드/시간 입력 이다.
- **제어 버튼(Start/Pause/Stop)이 32×32pt 아이콘 전용 버튼으로만 구성되어 있다.** `.help()` 툴팁이 있지만 tooltip은 hover 후 지연 시간이 있어 즉각 인지가 어렵다. "Start"와 같은 레이블을 아이콘 아래에 배치하거나, 적어도 Start 버튼은 텍스트 레이블 포함 버튼으로 만드는 것이 macOS HIG에 더 부합한다. 특히 처음 사용하는 사용자에게 Play 아이콘이 "Start"를 의미함은 자명하지만, Stop과 Pause의 구분은 아이콘만으로는 혼동 가능성이 있다.
- **카테고리 셀렉터의 컬러 닷(10pt Circle)이 너무 작다.** 12개 카테고리 각각의 컬러가 주요 구분 기준인데, 10pt 원으로는 색상을 신속하게 인식하기 어렵다. 14pt 이상이 권장되며, 선택된 카테고리의 색상을 모드 토글 배경이나 Start 버튼 배경에 약하게 반영(tinted highlight)하면 현재 세션 카테고리를 상시 인지할 수 있어 실용적이다.
- **타이머가 실행 중일 때 시간 입력(TextField/DatePicker)이 `.disabled`로 회색 처리되지만, 시각적으로 명확하지 않다.** SwiftUI의 기본 disabled 스타일은 `.opacity(0.6)` 수준이라 검은 배경 위에서 disabled 상태가 충분히 구분되지 않는다. 실행 중에는 입력 필드를 숨기거나 "Running" 배지로 대체하는 방식이 더 명확하다.

**권고 사항**

- 타이머 영역 VStack의 순서를 카운트다운 → 카테고리 → 제어 버튼 → (조건부 표시) 모드/시간 입력으로 재배치한다. 타이머 실행 중에는 모드/입력 필드를 숨겨 인터페이스를 단순화한다.
- Start/Pause/Stop 버튼에 레이블 텍스트를 추가하거나, 최소한 Pause와 Stop을 레이블로 구분한다. `controlButton`의 VStack(icon + text) 형태로 전환하면 된다.
- 선택된 카테고리의 컬러를 Start 버튼 배경(낮은 오파시티)에 반영하여 현재 세션 컨텍스트를 가시화한다.

---

### 4. Todo 목록 영역 — 시각적 계층 구조와 인터랙션 패턴

**현황 파악**

`TodoListView.swift`는 상단 "Tasks" 헤더, SwiftUI `List` (plain 스타일, hidden separator), 하단 "+ Add task" 텍스트필드로 구성된다. `TodoRowView`는 체크박스(13pt), 제목(12pt), 카테고리 닷(6pt)을 HStack으로 배열한다.

**강점**

- hover 시 `nsBorder.opacity(0.5)` 배경 전환과 `onHover` 처리가 macOS 네이티브 느낌을 잘 살리고 있다.
- 완료 항목의 strikethrough + `.nsTextSecondary` 컬러 전환은 간결하고 명확한 완료 상태 피드백이다.
- `.transition(.asymmetric(...))` 추가/삭제 애니메이션 정의가 있는 점은 좋은 세심함이다. 단, transition이 실제로 발화하려면 `withAnimation` 블록 안에서 상태 변경이 일어나야 한다는 점을 구현 시 주의해야 한다.

**문제점과 영향**

- **드래그 핸들 UI가 없다.** `.onMove`가 선언되어 있어 드래그 리오더가 가능하지만, macOS의 plain List에서 이 기능은 기본적으로 드래그 핸들을 표시하지 않는다. 사용자가 "드래그해서 순서를 바꿀 수 있다"는 것을 발견하기 어렵다. 각 행 좌측에 6개 점 그리드(`"line.3.horizontal"` 또는 `"grip.horizontal"`) 아이콘을 약한 불투명도(30%)로 상시 표시하고 hover 시 강조하는 방식이 필요하다.
- **카테고리 닷이 6pt로 너무 작다.** 색상으로 카테고리를 빠르게 인식하려면 최소 8pt, 이상적으로는 10pt 이상이 필요하다. 현재 6pt는 클릭 대상도 아니고 시각적 인식 기준도 되기 어렵다.
- **완료된 항목들이 리스트 하단으로 내려가지 않는 것으로 보인다.** 스펙("Completed items move to the bottom")이 있으나 `TodoViewModel`의 정렬 로직이 어떻게 구현되어 있는지 View 레벨에서는 보이지 않는다. 시각적으로 완료 항목이 하단 그룹으로 이동하는 것은 중요한 인지 단서인데, 이것이 실제로 동작하는지 통합 테스트 체크리스트에 추가되어야 한다.
- **"Add task" 필드에 카테고리 선택 옵션이 없다.** Todo 항목을 추가할 때 카테고리를 즉시 지정하려면 현재 구조에서는 불가능하고, 항목 추가 후 별도 편집이 필요하다. 이것은 특히 카테고리 중심으로 작업을 구분하는 사용자에게 마찰이다. 최소한 마지막 사용 카테고리를 기본값으로 자동 지정하는 처리가 있으면 좋다.

**권고 사항**

- TodoRowView 좌측에 드래그 핸들 아이콘(`"line.3.horizontal"`)을 추가한다. hover 시 `.nsTextSecondary` → `.nsTextPrimary` 전환으로 인터랙션 힌트를 준다.
- 카테고리 닷을 `width: 8, height: 8` 이상으로 확대하고, 카테고리명을 tooltip(`.help(cat.name)`)으로 제공한다.
- Add task 필드 우측에 카테고리 선택 버튼(미니 컬러 닷)을 추가하거나, `vm.newTitle`에 카테고리 상태를 함께 관리하는 구조를 고려한다.

---

### 5. Settings 화면 — 레이아웃과 usability

**현황 파악**

`SettingsView.swift`는 320×460pt 시트로, 상단 헤더(Settings + X 버튼), 스크롤 뷰 내에 (1) launch-at-login 토글, (2) Timer defaults 섹션(duration stepper + mode picker), (3) Categories 섹션 순으로 배열된다.

**강점**

- `@AppStorage`로 `defaultTimerDuration`과 `defaultTimerMode`를 직접 바인딩한 것은 UserDefaults 읽기/쓰기 코드를 없애는 깔끔한 구현이다. `.onDisappear` 저장 없이도 자동 동기화된다.
- Categories 섹션의 `ColorPicker + TextField + Plus 버튼` 3요소 인라인 추가 패턴은 직관적이다.
- 전체 높이 460pt에 스크롤을 사용한 것은 카테고리가 12개까지 늘어날 경우를 고려한 적절한 대비다.

**문제점과 영향**

- **320pt 폭에서 Stepper 레이블 + 값 + stepper 버튼이 동일 행에 있어 좁다.** "Default duration" 텍스트(약 120pt) + 값 표시(최소 52pt) + Stepper 버튼(약 50pt) = ~222pt이며, 나머지 여유가 14pt 패딩 양쪽을 제외하면 거의 없다. 현재는 `Spacer()`로 분리했으나, macOS에서 Stepper 버튼이 HIG 최소 크기(44pt)에 맞게 렌더링될 경우 레이아웃이 깨질 수 있다. 별도 행에 값과 stepper를 내려놓는 2행 배치를 고려한다.
- **카테고리 삭제 시 확인 다이얼로그가 없다.** 카테고리를 삭제하면 해당 카테고리에 연결된 모든 TodoItem과 Session의 category 참조가 영향받는다. 데이터 손실 가능성이 있는 작업에 대해 destructive 확인 단계가 없는 것은 UX상 위험하다. `confirmationDialog` 또는 최소한 `.destructive` role의 버튼 스타일 적용이 필요하다.
- **Settings 시트가 메인 패널 위에 `.sheet`로 표시되는 방식이 `.nonactivatingPanel` 환경에서 예측 불가능한 동작을 유발할 수 있다.** `NSPanel.nonactivatingPanel`에서 SwiftUI `.sheet`의 포커스 처리는 AppKit 레이어와 충돌할 수 있다. 특히 `ColorPicker`(자체 popover를 띄우는 컴포넌트)가 Settings 시트 안에 있을 때 포커스 체인이 끊기는 사례가 보고되어 있다. Settings를 별도 `NSWindow`(일반 document window)로 분리하는 방식이 더 안전하다.

**권고 사항**

- Stepper 행을 2행으로 분리하거나, 320pt를 360pt로 확대하여 여유 공간을 확보한다.
- 카테고리 삭제 버튼에 `.confirmationDialog`를 적용한다. 다이얼로그 메시지: "'{name}' 카테고리를 삭제하면 연결된 기록도 함께 삭제됩니다. 계속하시겠습니까?"
- Settings 시트를 `NSWindow` 기반의 별도 창으로 분리하는 것을 v1.1 과제로 등록한다. v1에서는 현재 방식을 유지하되, `ColorPicker` popover 충돌 여부를 통합 테스트에서 반드시 수동 확인한다.

---

### 6. macOS Human Interface Guidelines 준수 여부

**준수 항목**

- `NSPanel.nonactivatingPanel` 사용으로 다른 앱 포커스를 빼앗지 않는 것은 HIG "Non-activating panels" 가이드라인에 정확히 부합한다.
- `contextMenu`를 통한 "Quit" 제공은 Dock이 없는 앱의 표준 종료 패턴이다.
- `collectionBehavior = [.canJoinAllSpaces, .stationary]` 설정은 Mission Control에서 앱이 적절히 동작하도록 하는 올바른 설정이다.

**HIG 위반 또는 개선 필요 항목**

- **최소 터치/클릭 영역 미준수.** `ToggleChevronView`의 버튼 영역은 36×20pt이며, HIG는 최소 44×44pt(또는 macOS에서는 적어도 22pt 높이)를 권장한다. 쉐브론이 화면 최상단 좁은 영역에 위치한다는 점을 감안하면 클릭 오류가 빈번할 수 있다. 배경 Color.black.opacity(0.01)로 히트 영역 확장이 구현되어 있긴 하지만, 명시적 `.contentShape(Rectangle())`을 사용한 44pt 확장이 더 명확하다.
- **색상 대비율(Contrast Ratio) 검증 필요.** `nsTextSecondary(#707070)`와 `nsBackground(#000000)` 조합의 대비율은 약 5.4:1로 WCAG AA 기준(4.5:1)을 충족하지만 AAA(7:1)에는 미달한다. 11pt 이하의 소형 텍스트(HeatmapView 시간 레이블 8pt, TimerView 카테고리 레이블 11pt)에서 가독성이 낮아질 수 있다. 소형 텍스트에는 `#909090` 이상의 밝기를 적용하는 것을 권고한다.
- **키보드 접근성이 검증되지 않았다.** VoiceOver 및 Full Keyboard Access 환경에서 플로팅 패널이 포커스를 올바르게 처리하는지 확인이 필요하다. `nonactivatingPanel`은 키보드 포커스를 수신하지 않는 경우가 있어 접근성 사용자가 앱을 전혀 사용하지 못할 수 있다.

---

### 7. 경쟁 앱 대비 디자인 차별화 포인트

**Toggl Track 대비**

Toggl Track은 메뉴바 앱 + 풀 기능 웹앱 조합으로, 메뉴바 드롭다운이 매우 좁고 기능 접근을 위해 브라우저로 이동해야 한다. NativeScheduler의 860pt 와이드 패널은 핵심 기능을 이탈 없이 제공하는 점에서 명확한 우위다. 다만 Toggl의 팀 기능, 보고서, 연동(Jira, GitHub)은 개인 사용자 이상을 타깃으로 한다. NativeScheduler는 개인 딥 워크 세션 최적화라는 좁은 니치를 더 잘 파고들 수 있다.

**Timery 대비**

Timery(iOS 퍼스트 + macOS 메뉴바)는 Toggl API를 래핑한 앱으로 데이터를 Toggl 서버에 저장한다. NativeScheduler의 완전 로컬 네이티브 처리는 개인정보 민감 사용자(법률, 의료, 금융 분야 프리랜서)에게 강력한 소구점이다. 이 차별화 포인트를 앱 소개에서 명시적으로 언급해야 한다("Your data never leaves your Mac").

**Things 3 대비**

Things 3은 할 일 관리에 특화되어 있고 타이머/시간 추적 기능이 없다. NativeScheduler는 "할 일 + 타이머 + 시간 시각화" 통합 패키지라는 점에서 Things 3을 보완하는 위치다. Things 3 사용자에게 "타이머와 집중 기록을 Things와 별개로 관리하기 귀찮으신가요?"라는 메시지로 접근하는 마케팅이 효과적일 수 있다. 단, Things 3과의 연동(URL Scheme)을 v1.1에서 지원하면 이 사용자층을 직접 흡수할 수 있다.

**디자인 차별화의 핵심 주장**

현재 NativeScheduler의 가장 강력한 디자인 차별화는 "화면 최상단 중앙에 항상 존재하는 단일 쉐브론"이다. 이것은 경쟁 앱 중 어디에도 없는 포지션이다. 이 디자인 결정의 가치는 "열지 않아도 존재감을 느낀다, 열면 모든 것이 있다"는 것인데, 현재 쉐브론 자체에 상태 정보가 전혀 없다. 쉐브론 아이콘 옆에 타이머 실행 중일 때 1–2자리 남은 시간(예: "23m")을 극소형 텍스트로 표시하는 것을 강력히 권고한다. 이것이 이 앱이 항상 보여야 하는 이유를 완성하는 핵심 요소다.

---

### 8. 접근성(Accessibility) 고려사항

**현재 미비한 항목**

- 히트맵 셀에 `accessibilityLabel`이 없다. VoiceOver 사용자는 144개의 컬러 셀이 무엇인지 파악할 수 없다. 각 셀에 `.accessibilityLabel(tooltipText(...))` 추가가 필요하다.
- 타이머 카운트다운이 매 초 변경되는 텍스트라서 VoiceOver가 매 초 읽어주면 매우 시끄러워진다. `.accessibilitySortPriority` 또는 `accessibilityValue`를 사용해 VoiceOver가 포커스 시에만 읽도록 처리해야 한다.
- 카테고리 컬러 닷이 색상만으로 정보를 전달하고 있어 색약 사용자에게 구분이 어렵다. 카테고리 목록에서 색상 외에 패턴 또는 문자 약어를 보조 식별자로 추가하는 것을 v2 과제로 검토한다.

**즉시 개선 가능한 항목**

- 모든 아이콘 전용 버튼(`gearshape`, `play.fill`, `pause.fill`, `stop.fill`)에 `.accessibilityLabel("설정 열기")`, `.accessibilityLabel("타이머 시작")` 등을 명시적으로 추가한다. SwiftUI `.help()` 툴팁과 별개로 accessibility label은 필수다.
- `ToggleChevronView`의 토글 버튼에 `.accessibilityLabel(isExpanded ? "패널 닫기" : "패널 열기")`를 추가한다.

---

### 9. 디자인 리뷰 종합 점수 및 우선순위 요약

**디자인 성숙도: 6.5/10**

검은 배경 + 카테고리 컬러 히트맵 조합의 시각적 방향성은 명확하고 세련되어 있다. 핵심 컴포넌트들의 SwiftUI 구현 품질도 높다. 그러나 정보 계층 구조의 비직관적 배열, 드래그 핸들 부재, 쉐브론 상태 정보 부재 등 실사용에서 마찰을 주는 항목들이 v1 출시 전 보완이 필요하다.

| 우선순위 | 디자인 개선 항목 | 예상 공수 |
|---|---|---|
| P0 | 쉐브론에 타이머 잔여 시간 표시 | 소 (1일) |
| P0 | TodoRowView 드래그 핸들 아이콘 추가 | 소 (0.5일) |
| P1 | 타이머 VStack 순서 재배치 (카운트다운 최상단) | 소 (1일) |
| P1 | 히트맵 row 레이블 및 미래 슬롯 색상 구분 | 소 (1일) |
| P1 | 아이콘 버튼 accessibilityLabel 추가 | 소 (0.5일) |
| P2 | 카테고리 삭제 confirmationDialog | 소 (0.5일) |
| P2 | Settings Stepper 행 레이아웃 2행 분리 | 소 (0.5일) |
| P3 | Settings 별도 NSWindow 분리 | 중 (2–3일) |
| P3 | 색약 사용자 대비 카테고리 보조 식별자 | 중 (3일) |

---

## PM 결정 사항 (2026-04-12)

> 작성자: Project Manager
> 목적: 리뷰어 2인(상업/실용 어드바이저, 디자인 리뷰어)의 의견에 대한 수용·거절·보류 판단 및 다음 스프린트 방향성 확정

---

### 1. 리뷰어 의견에 대한 PM 판단

#### 상업/실용 어드바이저 리뷰 — 판단

| 항목 | 판단 | 이유 |
|---|---|---|
| 타이머-할 일 연동 부재 | **v1.1 수용** | 스펙에 명시적으로 독립으로 결정됨. 단, v1 출시 직후 1순위 과제로 등록 |
| 멀티데이 히트맵 부재 | **v1.1 수용** | 바이너리 로그가 이미 준비됨. 출시 후 KPI로 삼을 것 |
| 수익화 모델 미정 | **보류** | 현재 스프린트 범위 밖. 별도 PRD에서 결정 |
| macOS 13 타깃 하향 | **거절 (v1)** | SwiftUI API 호환성 재검토 비용 대비 효과가 v1 일정에 맞지 않음. v1.1에서 재검토 |
| 알림센터 연동 | **v1.1 수용** | 전체화면 앱 상황에서의 신뢰성 갭은 실사용 허들. 우선순위 높음 |
| 멀티모니터 지원 | **v2 보류** | 스펙 일치. 로드맵에만 기록 |
| 전략적 제언 전체 | **정보 수용** | 코드 변경 없음. 마케팅/출시 준비 단계에서 참조 |

#### 디자인 리뷰 — 판단

| 항목 | 판단 | v1 포함 여부 |
|---|---|---|
| 쉐브론 타이머 잔여 시간 표시 | **수용** | YES — 핵심 차별화 UX, 공수 소 |
| TodoRow 드래그 핸들 아이콘 | **수용** | YES — 기능 발견성 필수 |
| 타이머 VStack 순서 재배치 (카운트다운 최상단) | **수용** | YES — 인지 흐름 개선 |
| 히트맵 row 레이블 + 미래 슬롯 색상 구분 | **수용** | YES — 가독성 핵심 |
| 아이콘 버튼 accessibilityLabel | **수용** | YES — 최소 접근성 요건 |
| 카테고리 삭제 confirmationDialog | **수용** | YES — 데이터 안전성 |
| Settings Stepper 2행 레이아웃 | **보류** | 리뷰어가 실제 렌더링 확인 후 결정. 레이아웃 깨짐 없으면 유지 |
| Settings 별도 NSWindow 분리 | **조건부 수용** | v1에서 ColorPicker popover 충돌 테스트 후 결정. 충돌 시 v1 블로커로 상향 |
| 색약 사용자 보조 식별자 | **v2 보류** | 공수 대비 우선순위 낮음 |
| 히트맵 시간 레이블 밀도 향상 | **수용** | YES — 매 3시간 레이블 |
| 타이머 제어 버튼에 텍스트 레이블 | **수용** | YES — Pause/Stop 혼동 방지 |
| 카테고리 닷 크기 확대 (6pt→8pt, 10pt→14pt) | **수용** | YES — 시각적 인식 개선 |

---

### 2. v1 현재 스프린트 — 리뷰어 지시사항

> 아래 항목은 리뷰어가 코드 수준에서 검증해야 하는 구체적 포인트입니다.

#### [CRITICAL] Bug Fix 검증 — 쉐브론 레이어 nil

**배경**: `FloatingPanelController.swift:174`의 `shakeChevron()`에서 `chevronHosting.layer`를 사용하는데, `setupChevronPanel()`에서 `chevronHosting.wantsLayer = true`가 설정되지 않아 레이어가 항상 `nil` → shake 무음 실패.

**리뷰어 검증 포인트**:
- `setupChevronPanel()` 내에서 `chevronHosting`에 `wantsLayer = true` 설정이 추가되었는지 확인
- 또는 `shakeChevron()` 내에서 `guard`로 빠져나가기 전에 `chevronHosting.wantsLayer = true`를 선제적으로 설정하는 방식도 허용
- 수정 후 실제로 타이머를 1분 미만으로 설정하고 완료시켜 shake가 발생하는지 직접 확인

#### [VERIFY] 사운드 main thread 이중 dispatch

**배경**: `TimerEngine.finish()`는 이미 `DispatchQueue.main.async` 블록(`setEventHandler` 내부, line 49) 안에서 호출됨. 그런데 `finish()` 내부에 다시 `DispatchQueue.main.async` (line 101)가 있어 이중 dispatch 구조.

**리뷰어 검증 포인트**:
- 이중 dispatch는 기능적으로는 안전하지만 `isRunning = false`, `isFinished = true`, `remaining = 0` 상태 변경(동기)과 사운드 재생(비동기 hop)이 분리되어 사운드가 미세하게 지연될 수 있음
- 이를 허용 가능한 수준으로 판단하면 PASS. 단, 코드에 이유를 주석으로 명시했는지 확인 (`// already on main` 등)

#### [VERIFY] Settings Stepper 레이아웃 실제 렌더링

**배경**: `SettingsView.swift`의 Duration stepper 행이 320pt 내에서 깨질 수 있다는 디자인 리뷰어 우려.

**리뷰어 검증 포인트**:
- 앱 실행 후 Settings 창을 열고 Stepper 행이 시각적으로 깨지지 않는지 확인
- 깨지지 않으면 현재 레이아웃 유지 허용. 깨지면 PM에게 즉시 보고하여 2행 분리 작업 진행 여부 결정

#### [VERIFY] Settings ColorPicker popover 충돌

**배경**: `nonactivatingPanel` 환경에서 SwiftUI `.sheet` 내부의 `ColorPicker`가 자체 popover를 열 때 포커스 체인 충돌 가능성이 있다는 디자인 리뷰어 우려.

**리뷰어 검증 포인트**:
- Settings 시트 열기 → ColorPicker 클릭 → 색상 선택 popover가 올바르게 열리는지 확인
- 문제없으면 현재 방식 유지(Settings NSWindow 분리를 v1.1으로 보류). 충돌/동작 불가 시 PM에 보고하여 v1 블로커로 상향

#### [VERIFY] Todo 완료 항목 하단 이동

**배경**: 스펙에 "Completed items move to the bottom"이 명시됨. `TodoViewModel`의 `fetchAll` 정렬은 `isCompleted ascending` + `priority ascending`으로 되어 있으나, view transition이 실제로 발화하는지 확인 필요.

**리뷰어 검증 포인트**:
- Todo 항목 추가 → 체크박스 클릭 → 항목이 실시간으로 하단으로 이동하는지 확인
- 이동 시 slide-out/slide-in 애니메이션이 발화하는지 확인 (현재 `withAnimation` 블록 없이 상태 변경 → transition이 발화 안 될 수 있음)

---

### 3. 다음 스프린트 과제 — v1 마무리 (우선순위 순)

아래 항목이 완료되어야 v1 출시 가능 상태로 간주합니다.

| 순번 | 담당 | 과제 | 기준 |
|---|---|---|---|
| 1 | Developer | `shakeChevron()` 레이어 nil 버그 수정 (`wantsLayer = true` 추가) | shake 실제 동작 확인 |
| 2 | Developer | 쉐브론에 타이머 잔여 시간 표시 (`ToggleChevronView`) | 타이머 실행 중 "23m" 형태 노출 |
| 3 | Developer | TodoRow 드래그 핸들 아이콘 (`"line.3.horizontal"`) 추가 | hover 시 강조 |
| 4 | Developer | 타이머 VStack 순서 재배치 (카운트다운 최상단) | — |
| 5 | Developer | 히트맵 row 레이블(0/10/20/30/40/50m) + 미래 슬롯 `#252525` | — |
| 6 | Developer | 아이콘 버튼 `accessibilityLabel` 전체 추가 | — |
| 7 | Developer | 카테고리 삭제 `confirmationDialog` | — |
| 8 | Developer | 히트맵 시간 레이블 매 3시간 표시 | — |
| 9 | Developer | 타이머 Pause/Stop 버튼 텍스트 레이블 추가 | — |
| 10 | Developer | 카테고리 닷 크기 확대 (`6pt→8pt`, `10pt→14pt`) | — |
| 11 | Reviewer | 위 검증 항목 5건 수동 테스트 및 결과 보고 | — |

---

### 4. v1.1 백로그 (v1 출시 후 즉시 착수)

1. **타이머-할 일 연동**: Todo 항목에서 해당 카테고리로 타이머 즉시 시작
2. **7일 히트맵**: 바이너리 로그 mmap 기반 멀티데이 스크롤 뷰
3. **알림센터 연동**: `UserNotifications`로 타이머 완료 알림
4. **macOS 13 타깃 하향 검토**: SwiftUI API 호환성 재검토 후 결정
5. **Settings NSWindow 분리** (ColorPicker 충돌 발생 시 우선 이동)

### 5. v2 로드맵

- iCloud 동기화 (CloudKit)
- iPhone 컴패니언 앱
- 멀티모니터 스크린 선택 설정
- Things 3 URL Scheme 연동
- 통계/분석 뷰 (주간 카테고리별 집중 시간)
- 색약 사용자 카테고리 보조 식별자
- CSV/JSON 데이터 내보내기
