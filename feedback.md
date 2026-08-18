# NativeScheduler 코드 감사 및 최적화 피드백
**작성일**: 2026-04-26  
**범위**: `NativeScheduler/Sources`, `NativeScheduler/Tests`, `Package.swift`, `project.yml`  
**검증**: 정적 코드 분석 + `swift test`

---

## 1. Repository Shape

NativeScheduler는 SwiftPM executable target 기반의 macOS LSUIElement 앱이다.

| 영역 | 주요 파일 | 역할 |
|---|---|---|
| App | `NativeSchedulerApp.swift`, `AppDelegate.swift` | Dock 없는 앱 실행, 로그인 등록, midnight flush, smoke harness |
| FloatingPanel | `NotchWindow`, `NotchView`, `NotchGeometry`, `FloatingPanelController` | 최상단 플로팅 패널, hover/click expand, timer 상태 표시 |
| Timer | `TimerEngine`, `TimerViewModel`, `TimerView` | countdown 엔진, 세션 생성/종료, timer UI |
| Todo | `TodoViewModel`, `TodoListView` | CoreData todo CRUD, 완료/정렬, custom drag reorder |
| Heatmap | `HeatmapViewModel`, `HeatmapView`, `MultiDayHeatmapView` | 세션 기반 20분 슬롯 집계, 오늘 heatmap 표시, v1.1 stub |
| Settings | `SettingsView`, `CategoryEditorView` | 카테고리 편집, launch-at-login, timer 기본값 |
| Models | `CoreDataStack`, `ManagedObjects`, `DailyLogWriter` | 코드 기반 CoreData 모델, binary daily log |
| DesignSystem | `Colors.swift` | 공통 색상, palette, hex 변환 |

## 2. Entry Points and Execution Path

1. `NativeSchedulerApp`가 `AppDelegate`를 붙이고 `Settings { EmptyView() }`만 노출한다.
2. `AppDelegate.applicationDidFinishLaunching`이 `FloatingPanelController.setup()`을 호출한다.
3. `FloatingPanelController`가 `TimerViewModel`, `NotchTimerState`, `NotchWindow`를 구성한다.
4. `NotchWindow`의 `NSHostingView`가 `NotchView`를 띄우고, expanded content로 `MainPanelView`를 주입한다.
5. `MainPanelView`가 `TodoListView`, `HeatmapView`, `TimerView`, `SettingsView.sheet`를 연결한다.
6. `TimerViewModel`은 `TimerEngine` 콜백으로 CoreData `SessionEntity`를 열고 닫는다.
7. `HeatmapViewModel`은 CoreData save notification마다 세션을 다시 집계해 `HeatmapView`에 반영한다.
8. `AppDelegate`는 자정과 앱 종료 시 `FloatingPanelController.flushDailyLog()`로 binary log를 쓴다.

---

## 3. 높은 우선순위: 실제 동작 오류 가능성

### P0-1. TimerView가 기본 duration을 30분으로 덮어쓸 수 있음

**위치**
- `TimerView.swift:27-31`
- `TimerView.swift:502-512`
- `TimerEngine.swift:102-107`

`TimerView.onAppear`가 현재 timer mode와 무관하게 `seedEndTimeFromNow()`를 호출한다. 이 함수는 `vm.engine.targetEndTime`을 현재 시각 + 30분으로 설정한 뒤 `vm.engine.prepareEndTimeCountdown()`을 호출한다. `prepareEndTimeCountdown()`은 `durationSeconds`와 `remaining`을 end-time countdown 값으로 덮어쓴다.

**영향**
- Settings 기본 duration이 25분이어도 TimerView가 나타나는 순간 duration 모드 값이 30분으로 바뀔 수 있다.
- `TimerViewModel.applyDefaultTimerSettings()`가 읽은 UserDefaults 값이 UI 진입 시 무효화된다.
- duration 모드와 end-time 모드의 상태가 서로 섞인다.

**권장 수정**
- `onAppear`에서는 `engine.mode == .endTime`일 때만 `seedEndTimeFromNow()`를 호출한다.
- duration 모드에서는 `durationSeconds`를 건드리지 않고 `durationInput` 동기화만 한다.
- 이 케이스는 테스트를 바로 추가해야 한다. 예: duration default 25분 적용 후 `TimerView` appear 로직이 engine duration을 변경하지 않는지 검증.

### P0-2. Timer 기본값 범위가 Settings, ViewModel, TimerView에서 서로 다름

**위치**
- `SettingsView.swift:80` — `1...120`, step 5
- `TimerViewModel.swift:37` — `5...60`으로 clamp
- `TimerView.swift:101`, `TimerView.swift:126`, `TimerView.swift:482-486` — UI는 `5...60`

**영향**
- Settings에서 90분이나 120분을 선택할 수 있지만 앱 시작 후 `TimerViewModel`은 최대 60분으로 잘라낸다.
- Settings에서 1분을 선택할 수 있지만 runtime은 최소 5분으로 올린다.
- 사용자가 저장한 값과 실제 timer 값이 달라진다.

**권장 수정**
- `TimerDefaults` 같은 단일 상수를 만들고 min/max/step/default/mode key를 한 곳에서 관리한다.
- Settings UI와 TimerViewModel clamp가 같은 상수를 사용하게 한다.
- 정말 1~120분을 허용할 계획이면 TimerView duration picker도 1~120을 지원해야 한다.

### P1-1. 카테고리 삭제 설명과 CoreData delete rule이 불일치

**위치**
- `SettingsView.swift:164-166` — “Deleting a category cascades...”
- `SettingsView.swift:185` — 사용자 메시지는 unlink라고 안내
- `CoreDataStack.swift` relationship delete rule은 category -> sessions/todos 모두 `.nullifyDeleteRule`

**영향**
- 코드 주석은 cascade라고 쓰여 있지만 실제 모델은 nullify다.
- 사용자 메시지는 unlink라고 맞게 안내한다.
- 유지보수자가 주석을 믿고 잘못된 수정이나 테스트를 작성할 수 있다.

**권장 수정**
- `SettingsView.swift:164-166` 주석을 “nullifies category links”로 수정한다.
- 카테고리 삭제 후 todo/session category가 nil로 유지되는지 테스트를 추가한다.

### P1-2. collapsed hit rect가 progress ring 포함 폭을 완전히 중앙 기준으로 계산하지 않음

**위치**
- `NotchGeometry.swift:49-55`
- `NotchGeometry.swift:121-127`
- `NotchView.swift:32-35`

`idleShellWidth`는 timer progress 표시 중일 때 `notchWidth + ringAreaWidth`를 반환한다. 하지만 `idleShellMinX`는 `notchWidth`만 기준으로 중앙 정렬한다. 결과적으로 진행 링이 오른쪽으로 붙는 디자인이면 의도일 수 있지만, “전체 collapsed shell을 중앙 정렬”하려는 의도라면 hit rect와 시각 중심이 달라진다.

**영향**
- hover/click hit area가 사용자 기대보다 오른쪽으로 넓고 왼쪽으로 좁을 수 있다.
- 테스트도 이 동작을 현재 기대값으로 고정하고 있어 설계 의도 확인이 필요하다.

**권장 수정**
- 의도가 “notch 본체 중앙 고정 + progress ring 오른쪽 확장”이면 함수명을 `idleShellMinXAnchoredToNotch`처럼 명확히 한다.
- 의도가 “전체 shell 중앙 정렬”이면 `idleShellMinX(boundsWidth:idleWidth:)`로 바꾸고 테스트 기대값을 수정한다.

---

## 4. 중복 구현 및 같은 기능의 다른 사용

### D1. Heatmap 슬롯 집계 로직이 두 곳에 중복됨

**위치**
- `HeatmapViewModel.swift:28-73`
- `FloatingPanelController.swift:57-95`

두 위치 모두 `HeatmapSlot.all`을 순회하고 `SessionEntity.sessions(forSlot:)`로 세션을 가져온 뒤 category별 dominant minutes를 계산한다. 하지만 tie-break 처리가 다르다.

| 항목 | `HeatmapViewModel` | `flushDailyLog` |
|---|---|---|
| category key | `CategoryEntity?` / objectID | `NSManagedObjectID?` |
| tie-break | earliest start 고려 | minutes만 비교 |
| output | `SlotInfo(color/name/minutes)` | `HeatmapSlotData(categoryIndex/minutes)` |

**영향**
- 화면에 보이는 dominant category와 daily log에 저장되는 dominant category가 tie 상황에서 달라질 수 있다.
- 버그 수정 시 한쪽만 고치기 쉽다.

**권장 수정**
- `HeatmapAggregator` 같은 순수 로직을 분리한다.
- 입력: `[SessionEntity]`, slots, now/date, category index map.
- 출력: category objectID, name/color, dominant minutes를 포함한 중립 DTO.
- `HeatmapViewModel`과 `flushDailyLog`는 같은 aggregator 결과를 각자 UI/log 타입으로 변환만 한다.

### D2. HeatmapView와 MultiDayHeatmapView가 grid UI를 거의 복사함

**위치**
- `HeatmapView.swift:57-139`
- `MultiDayHeatmapView.swift:150-253`

hour label, minute row label, cell grid, future slot 판단, current marker, tooltip 생성이 중복되어 있다. `MultiDayHeatmapView` 주석도 “mirrors HeatmapView exactly”라고 명시하지만 실제로는 고정 cell size와 responsive metrics가 다르다.

**영향**
- Heatmap UI를 수정하면 두 파일을 함께 고쳐야 한다.
- v1.1에서 `MultiDayHeatmapView`를 켜면 오늘 heatmap과 historical heatmap의 cell 크기/반응형 동작이 달라진다.

**권장 수정**
- `HeatmapGridView`와 `HeatmapMetrics`를 공통 컴포넌트로 분리한다.
- `HeatmapView`는 `displayedHours`, `slots`, `isToday`, `dateLabel`만 전달한다.
- `MultiDayHeatmapView`는 navigation shell만 담당하게 한다.

### D3. Timer default 설정 키와 범위가 흩어져 있음

**위치**
- `SettingsView.swift:15-16`
- `TimerViewModel.swift:31-47`
- `TimerView.swift:482-486`

`defaultTimerDuration`, `defaultTimerMode`, duration min/max/default가 문자열과 숫자 literal로 여러 곳에 있다.

**권장 수정**
- `TimerDefaults` enum 또는 struct:
  - `durationKey`
  - `modeKey`
  - `defaultDurationMinutes`
  - `minDurationMinutes`
  - `maxDurationMinutes`
  - `durationStepMinutes`
- Settings, TimerViewModel, TimerView가 모두 이 타입을 사용하게 한다.

### D4. 카테고리 추가 UI가 Settings와 Timer popover에 따로 구현됨

**위치**
- `SettingsView.swift:126-151`, `SettingsView.swift:218-230`
- `TimerView.swift:279-328`
- `TimerViewModel.swift:55-69`

Settings는 `ColorPicker`로 임의 색을 고르게 하고, Timer popover는 `CategoryPalette.quickAdd`만 제공한다. 기능 차이가 의도라면 괜찮지만, “카테고리 추가”라는 같은 도메인 작업이 validation, max count, trimming, 색상 선택 UX를 서로 다르게 가진다.

**권장 수정**
- category 생성은 `CategoryViewModel` 또는 `CategoryRepository`로 통합한다.
- Timer popover의 quick-add는 간단 모드로 유지하되, validation/max count/error 상태는 동일 API를 사용한다.

### D5. Time/date formatting이 여러 곳에서 즉석 생성됨

**위치**
- `MainPanelView.swift:105-109`
- `TimerView.swift:546-550`
- `DailyLogWriter.swift:84-87`
- `MultiDayHeatmapView.swift:41-47`

`DateFormatter`는 생성 비용이 큰 편이고 locale/timezone 정책이 흩어진다.

**권장 수정**
- `DateFormatters` 유틸을 만들고 `yyyy-MM-dd`, `HH:mm`, `EEE, MMM d`를 static cached formatter로 제공한다.
- log filename formatter는 locale/timezone 정책을 명시한다.

### D6. Timer progress ring과 countdown border progress 계산은 같은 도메인인데 UI별로 흩어짐

**위치**
- `NotchTimerState.swift:8-13`
- `FloatingPanelController.swift:34-48`
- `TimerView.swift:420-439`

`TimerProgress.fraction`을 공유하는 점은 좋다. 다만 `NotchTimerState`는 running일 때만 progress를 받고, `TimerView`는 paused도 progress로 표시한다. 의도된 차이면 유지 가능하지만 정책을 명시해야 한다.

**권장 수정**
- progress 정책을 enum으로 분리한다. 예: `.runningOnly`, `.activeOrPaused`.
- UI별 차이가 의도임을 코드에서 드러내면 리그레션이 줄어든다.

---

## 5. 성능 최적화 후보

### O1. Heatmap reload가 CoreData save마다 72회 fetch를 수행함

**위치**
- `HeatmapViewModel.swift:32-33`
- `ManagedObjects.swift:50-58`
- `HeatmapViewModel.swift:78-88`

현재 `HeatmapViewModel.reload()`는 72개 슬롯마다 `SessionEntity.sessions(forSlot:)`를 호출한다. 게다가 observer가 `object: nil`이라 Todo 저장, Category 이름 변경, Settings 조작 등 모든 context save에서 reload가 발생한다.

**영향**
- 작은 데이터에서는 괜찮지만 세션이 누적되면 UI thread에서 fetch 72회가 반복된다.
- Todo 추가/삭제만 해도 heatmap 재집계가 돈다.

**권장 수정**
- 하루 범위 session을 한 번만 fetch하고 메모리에서 슬롯별 overlap을 계산한다.
- notification의 inserted/updated/deleted object에 `SessionEntity` 또는 category 색/name 변경이 있을 때만 reload한다.
- running session 때문에 현재 slot만 갱신할 수 있다면 full reload 대신 incremental update를 고려한다.

### O2. `flushDailyLog()`도 72회 fetch + 중복 집계를 수행함

**위치**
- `FloatingPanelController.swift:57-95`

daily flush는 빈번하지 않지만 앱 종료/자정에 main actor에서 실행된다. 세션 수가 많으면 종료 시 지연이 생길 수 있다.

**권장 수정**
- O1의 `HeatmapAggregator`를 재사용하고, 하루 세션 fetch 1회로 줄인다.
- log write는 Data 생성 후 파일 쓰기만 background queue로 넘길 수 있다. 단 CoreData object 접근은 context queue에서 끝내고 DTO만 넘겨야 한다.

### O3. TimerViewModel이 slot boundary마다 저장하지만 실제 변경이 없을 수 있음

**위치**
- `TimerViewModel.swift:167-173`

`checkSlotBoundary()`는 `lastSlotIndex`가 바뀌면 `stack.save()`를 호출한다. 하지만 현재 running `SessionEntity`의 속성을 갱신하지 않으므로 context에 변경이 없을 가능성이 높다. `CoreDataStack.save()`가 `hasChanges` guard를 갖고 있어 DB write는 피하지만, save 호출 자체가 heatmap notification 설계와 엮여 있다.

**권장 수정**
- heatmap refresh를 CoreData save에 의존하지 말고 timer tick/slot boundary event를 명시적으로 publish한다.
- running session을 화면에 반영하려는 목적이면 `HeatmapViewModel`에 `reload()` 호출 또는 domain event를 직접 전달하는 편이 명확하다.

### O4. MainActor timer engine이 UI 부하에 영향을 받을 수 있음

**위치**
- `TimerEngine.swift:16-18`

주석상 Swift executor assertion 회피를 위해 `DispatchSourceTimer`를 main queue에 둔다. 구현은 단순하고 안전하지만, SwiftUI layout이나 CoreData reload가 main thread를 오래 점유하면 countdown tick이 밀릴 수 있다.

**권장 수정**
- 현재는 v1에서 허용 가능하다.
- 장기적으로는 monotonic clock 기반으로 남은 시간을 계산하고, UI publish만 main actor에서 수행하는 구조가 더 견고하다.

### O5. DateFormatter 생성 캐싱

**위치**
- `MainPanelView.swift:105-109`
- `TimerView.swift:546-550`
- `DailyLogWriter.swift:84-87`
- `MultiDayHeatmapView.swift:41-47`

빈도는 높지 않지만 쉽게 정리 가능한 비용이다. `DateFormatters` 캐시로 통합하면 성능보다 일관성 이득이 더 크다.

---

## 6. 구조/유지보수 리스크

### S1. `TimerView.swift`가 886줄로 너무 많은 책임을 가진다

**위치**
- `TimerView.swift` 전체
- `MaskedTimeTextField`/`MaskedTimeInputView`: `TimerView.swift:592-817`
- `TimerCountdownBorder`: `TimerView.swift:819-886`

TimerView 한 파일에 timer layout, mode switching, category popover, category quick-add, end-time parsing, custom AppKit text input, countdown border shape가 모두 들어 있다.

**권장 분리**
- `TimerControlsView`
- `DurationPickerView`
- `EndTimePickerView`
- `MaskedTimeTextField.swift`
- `CategoryPopoverView`
- `TimerCountdownBorder.swift`
- pure parser/formatter: `EndTimeParser`

### S2. `TodoListView.swift`도 673줄로 drag/drop 상태가 view에 과도하게 많음

**위치**
- `TodoListView.swift:8-19`
- `TodoColumnDropDelegate`: `TodoListView.swift:392-583`
- `TodoScrollViewResolver`: `TodoListView.swift:607-659`

drag/drop 구현은 기능상 복잡할 수밖에 없지만, 현재는 view state, auto-scroll policy, row pitch, placeholder policy가 한 파일에 섞여 있다.

**권장 분리**
- `TodoDragState`
- `TodoColumnDropDelegate.swift`
- `TodoAutoScroller`
- `TodoRowView.swift`
- `TodoScrollViewResolver.swift`

### S3. 사용되지 않거나 stub 상태인 코드가 있음

**확인된 후보**
- `ToggleChevronView.swift`: 현재 `rg` 기준 참조 없음.
- `FocusablePanel.swift`: 현재 `rg` 기준 참조 없음. `NotchWindow`가 직접 `canBecomeKey/Main = true`를 override한다.
- `MultiDayHeatmapView.swift`: 현재 `MainPanelView`에서 사용하지 않으며 historical load도 TODO stub.
- `DailyLogWriter.read(date:)`: 현재 호출 없음. category map을 읽지 않아 historical UI 복원에도 부족하다.
- `TimeInterval.chevronString`: 현재 호출 없음.
- `TodoViewModel.move(from:to:)`: 현재 SwiftUI `.onMove` 경로가 없고 custom drop은 `moveActiveItem`을 쓴다.
- `CategoryPalette.defaults`: 현재 호출 없음.
- `TimerView.durationInput`: 값은 세팅되지만 UI binding으로 쓰이지 않는다.

**권장 판단**
- v1.1 예정 코드는 남기되 `Experimental`/`Backlog` 폴더나 명확한 TODO tracking으로 분리한다.
- 완전히 죽은 코드라면 제거한다. 특히 `ToggleChevronView`, `FocusablePanel`은 과거 구조의 잔재일 가능성이 높다.

### S4. NotificationCenter 기반 interaction lock이 문자열 전역 이벤트로 흩어짐

**위치**
- `MainPanelView.swift:112-115`
- `NotchView.swift:54-58`, `NotchView.swift:133-145`
- `TimerView.swift:237-248`, `TimerView.swift:553-558`

popover나 버튼 동작 중 hover collapse를 막는 목적은 타당하다. 하지만 문자열 notification으로 상태를 주고받으면 lock owner, 중첩 lock, 해제 누락을 추적하기 어렵다.

**권장 수정**
- `NotchInteractionState: ObservableObject`를 `NotchView`와 child views에 environment object로 주입한다.
- lock counter 방식으로 구현하면 popover A/B가 겹쳐도 안전하다.

### S5. CoreData 모델을 코드로 직접 구성하는 방식은 migration 추적이 어렵다

**위치**
- `CoreDataStack.swift:45-146`

코드 기반 모델은 repo가 작을 때는 단순하지만, entity/attribute versioning이 늘어나면 lightweight migration 추적과 리뷰가 어려워진다.

**권장 수정**
- v1 이후에는 `.xcdatamodeld` 전환을 검토한다.
- 계속 코드 모델을 유지한다면 model version, attribute optional/default, migration test를 명시한다.

---

## 7. 데이터/도메인 일관성 이슈

### C1. Heatmap slot 스펙과 구현이 20분/3행 기준으로 바뀌어 있음

**위치**
- `ManagedObjects.swift:101-104`
- `HeatmapSlotTests.swift:36-45`

현재 구현은 3 rows/hour, 20 minutes/slot, 총 72 slots다. 과거 문서나 이전 feedback가 6 rows/hour, 10 minutes/slot 기준이라면 문서와 UI 기대치가 어긋난다.

**권장 수정**
- `prompt.md`, `management_note.md`, App Store 문구까지 20분 기준으로 갱신하거나, 요구가 원래 10분이면 구현을 되돌린다.

### C2. DailyLogWriter.read가 category map을 버림

**위치**
- `DailyLogWriter.swift:39-48`
- `DailyLogWriter.swift:60-80`
- `MultiDayHeatmapView.swift:261-265`

writer는 category index map을 append하지만 read는 slot table만 반환한다. 이 상태로는 과거 heatmap에서 category color/name을 복원할 수 없다.

**권장 수정**
- `DailyLogReader`를 별도 구현하거나 `DailyLogWriter`를 `DailyLogStore`로 rename한다.
- read 결과는 `DailyLog(day, slots, categories)`처럼 category map까지 포함해야 한다.

### C3. Category max count 12 정책이 여러 곳에 숨어 있음

**위치**
- `TimerViewModel.swift:58`
- `SettingsView.swift:220`
- `CategoryPalette.defaults`

12개 제한은 CoreData나 category service의 도메인 정책이다. View마다 직접 검사하면 나중에 제한 변경 시 누락된다.

**권장 수정**
- `CategoryPolicy.maxCount = 12`로 통합한다.
- add 실패 이유를 UI가 표시할 수 있게 `Result`를 반환한다.

### C4. Launch-at-login 자동 등록과 Settings toggle 상태가 분리됨

**위치**
- `AppDelegate.swift:15-19`
- `SettingsView.swift:187-190`
- `SettingsView.swift:239-245`

첫 실행 자동 등록 여부는 `didRegisterLaunchAtLogin` UserDefaults로 관리하고, Settings는 `SMAppService.mainApp.status`를 읽는다. 기능상 가능하지만 실패 시 `didRegisterLaunchAtLogin`이 true로 저장되는 문제가 생길 수 있다.

**권장 수정**
- `try SMAppService.mainApp.register()` 성공 시에만 `didRegisterLaunchAtLogin`을 true로 저장한다.
- Settings toggle 실패 시 UI state를 원래 값으로 되돌린다.

---

## 8. 테스트 갭

현재 테스트는 `TimerEngine`, `TimerProgress`, `HeatmapSlot`, `NotchGeometry` 일부를 커버한다. 핵심 UI/ViewModel 동작 중 테스트가 없는 부분이 많다.

| 갭 | 필요한 테스트 |
|---|---|
| TimerView appear가 duration을 덮어쓰는 문제 | duration mode에서 appear 후 `durationSeconds` 유지 |
| Settings duration 범위 | Settings 저장값과 TimerViewModel clamp 정책 일치 |
| Heatmap aggregation | tie-break, nil category, running session overlap |
| flushDailyLog | 화면 aggregation과 log aggregation 결과 동일 |
| DailyLog read/write | category map round-trip, version mismatch |
| Todo reorder | `moveActiveItem` before nil/target, completed item 제외 |
| Category delete | nullify behavior 확인 |
| Interaction lock | popover open 중 hover exit가 collapse하지 않는지 |
| Smoke harness | duration/endTime smoke mode가 session close와 app terminate를 정상 수행 |

---

## 9. 추천 리팩터링 순서

### 1단계: 동작 오류와 정책 불일치 수정

1. `TimerView.onAppear`에서 duration mode를 덮어쓰지 않게 수정.
2. `TimerDefaults` 단일 정책 도입.
3. Settings duration 범위와 TimerView duration picker 범위 통일.
4. 카테고리 삭제 주석 수정.

### 2단계: 중복 집계 제거

1. `HeatmapAggregator` 순수 타입 생성.
2. `HeatmapViewModel.reload()`와 `FloatingPanelController.flushDailyLog()`가 aggregator를 공유하게 변경.
3. 하루 session fetch를 1회로 줄임.
4. aggregation 테스트 추가.

### 3단계: 죽은 코드/stub 정리

1. `ToggleChevronView`, `FocusablePanel`, `chevronString`, `TodoViewModel.move(from:to:)`, `CategoryPalette.defaults`, `durationInput` 사용 여부 최종 판단.
2. 사용하지 않는 코드는 제거하거나 v1.1 backlog 폴더/문서로 이동.
3. `MultiDayHeatmapView`는 실제 연결 전까지 compile-only stub임을 명시하거나 feature flag로 관리.

### 4단계: 파일 분리

1. `TimerView.swift`를 입력/컨트롤/카테고리/shape로 분리.
2. `TodoListView.swift`에서 drag delegate와 scroll resolver 분리.
3. `HeatmapGridView` 공통 컴포넌트 도입.

### 5단계: 관찰/상태 전달 개선

1. NotificationCenter interaction lock을 `ObservableObject`로 교체.
2. Heatmap reload trigger를 CoreData save 전체 감시에서 domain event 또는 filtered notification으로 축소.

---

## 10. Confirmed Facts

- `swift test`는 통과했다.
- 전체 Swift 소스/테스트는 약 4,564줄이다.
- 가장 큰 파일은 `TimerView.swift` 886줄, `TodoListView.swift` 673줄이다.
- `HeatmapViewModel.reload()`와 `flushDailyLog()`는 슬롯 집계 로직을 중복 구현한다.
- `MultiDayHeatmapView`는 현재 사용되지 않고 historical data loading도 TODO다.
- `DailyLogWriter.read`는 category map을 읽지 않는다.
- `TimerView.onAppear`는 현재 mode와 무관하게 end-time seed 로직을 실행한다.
- Settings duration 범위와 runtime duration clamp가 서로 다르다.

## 11. Inferences

- `ToggleChevronView`와 `FocusablePanel`은 이전 패널 구조에서 남은 잔재일 가능성이 높다.
- Heatmap이 10분/6행에서 20분/3행으로 바뀐 것으로 보이며, 문서가 같이 갱신되지 않았을 가능성이 있다.
- Interaction lock은 hover collapse 문제를 막기 위해 후속으로 추가된 임시 전역 이벤트 구조로 보인다.
- `TimerViewModel.checkSlotBoundary()`의 `stack.save()`는 DB 저장보다 heatmap refresh trigger 목적으로 남아 있을 가능성이 있다.

## 12. Open Questions

1. duration timer의 공식 범위는 1~120분인가, 5~60분인가?
2. collapsed shell은 notch 본체를 중앙 고정하고 progress ring을 오른쪽으로 확장하는 디자인인가, 전체 shell을 중앙 정렬하는 디자인인가?
3. Heatmap 최종 스펙은 20분/3행인가, 10분/6행인가?
4. `MultiDayHeatmapView`는 v1에 포함할 예정인가, v1.1 backlog인가?
5. category 삭제 정책은 unlink(nullify)가 맞는가, cascade delete가 맞는가?

---

## 13. 가장 먼저 고칠 항목 Top 5

1. `TimerView.onAppear`의 `seedEndTimeFromNow()` 무조건 호출 제거.
2. `TimerDefaults` 도입으로 duration 범위/키 통일.
3. `HeatmapAggregator` 분리로 화면/log 집계 중복 제거.
4. `HeatmapViewModel` reload를 72 fetch에서 하루 session 1 fetch로 변경.
5. unused/stub 코드 정리: `ToggleChevronView`, `FocusablePanel`, `MultiDayHeatmapView`, `DailyLogWriter.read`, `durationInput`.
