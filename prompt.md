# Native macOS Scheduler App — Product Specification

## Overview

A native macOS floating panel app that combines a priority-based todo list, a Pomodoro-style timer, and a GitHub heatmap-style daily activity tracker. The app runs persistently in the background and surfaces as a compact toggle at the top-center of the screen.

---

## Tech Stack

- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI + AppKit (NSPanel for floating window)
- **Persistence**: CoreData (local SQLite-backed)
- **Minimum Target**: macOS 14 (Sonoma)
- **Architecture**: MVVM with Combine for reactive state
- **Extensibility**: Modular feature packages (SPM), protocol-driven data layer for future sync (iCloud, server)

---

## Window Behavior

### Collapsed State (always visible)
- `NSPanel` with `windowLevel = .floating` — always on top, even over full-screen apps
- Positioned: **top-center** of the **primary (main) screen** — `NSScreen.main`
- Multi-monitor: always anchors to the primary screen, does not follow cursor or active display
- Visible across all virtual desktops: `collectionBehavior = [.canJoinAllSpaces, .stationary]`
- Height: exactly macOS status bar height (~28pt) + a small chevron (▾) that protrudes ~10pt below
- Width: ~120pt
- The chevron/toggle button is the only visible element
- Semi-transparent background so it blends near the camera notch area
- **No Dock icon**, **no menu bar icon** — `LSUIElement = YES` in Info.plist
- **Launch at Login**: registered via `SMAppService.mainApp` (macOS 13+)

### Expanded State (on toggle click)
- Panel animates downward, revealing the full UI
- Panel size: ~860pt × 480pt, centered horizontally
- Panels anchor to the top edge — expands downward only
- `NSPanel` with `.nonactivatingPanel` so it never steals focus from other apps
- Background color: **#000000** (pure black), corner radius 12pt
- Slight drop shadow

---

## Layout (Expanded)

```
┌─────────────────────────────────────────────────────────────────┐
│  ▾  (toggle — top center, always visible)                       │
├──────────────────────┬──────────────────────────────────────────┤
│                      │  TODAY'S HEATMAP (6 × 24)                │
│   TODO LIST          │  ┌──┬──┬──┬── ... 24 cols ──┬──┐        │
│   (priority order)   │  │  │  │  │                 │  │ row 1  │
│                      │  │  │  │  │                 │  │ row 2  │
│   [ ] Task A  ●red   │  │  │  │  │                 │  │ row 3  │
│   [ ] Task B  ●blue  │  │  │  │  │                 │  │ row 4  │
│   [ ] Task C         │  └──┴──┴──┴── ... ──────────┴──┘ row 5  │
│   + Add task         │                             row 6        │
│                      ├──────────────────────────────────────────┤
│                      │  TIMER                                   │
│                      │  Mode: [End Time ◉] [Duration ○]         │
│                      │  ┌─────────────────────────────────┐     │
│                      │  │        00 : 25 : 00              │     │
│                      │  └─────────────────────────────────┘     │
│                      │  Category: ● [select]   [▶ Start]        │
└──────────────────────┴──────────────────────────────────────────┘
```

---

## Feature Specifications

### 1. Heatmap (Today View)

**Grid**: 6 rows × 24 columns = 144 cells, each representing **10 minutes** of the current day.

- Column index = hour (0–23)
- Row index = 10-min slot within that hour (0–5)
- Cell at `[row][col]` represents time: `col:row*10` → e.g., `[2][14]` = 14:20–14:30

**Color logic per cell**:
- If multiple category sessions overlap a 10-min slot, the **dominant category** (most minutes within that slot) wins
- Tie → the category that started first wins
- No activity → default gray (`#3A3A3A`)

**Display**:
- Each cell is a rounded rect, ~22×18pt, with 2pt gap
- Color = category's assigned color at full opacity
- Hover tooltip: "14:20–14:30 · Deep Work (18 min)"
- Current time marker: thin vertical line on the active column

**Updates**: Redraws only on timer tick events, not on a polling loop.

---

### 2. Category System

- User-defined categories, max **12**
- Each category has: **name** (string) + **color** (HSB color picker)
- **Default category**: "Default" — color `#808080` (gray)
- Managed in a settings sheet accessible from the main panel
- Categories persist in CoreData

---

### 3. Todo List (Priority List)

- Items ordered by **manual priority** (drag-to-reorder)
- Each item: `title` (string), `isCompleted` (bool), `category` (optional, links to Category), `createdAt` (Date)
- Completed items move to the bottom with strikethrough
- "+ Add task" inline text field at the bottom
- Swipe left to delete (NSGestureRecognizer / SwiftUI `.onDelete`)
- No due dates in v1 (extensibility hook left in data model)
- Tapping a todo item does **not** auto-start the timer — they are independent

---

### 4. Timer

**Two modes** (toggle switch in UI):

| Mode | Behavior |
|------|----------|
| **Duration** | User sets a length (e.g., 25 min). Countdown from that value. |
| **End Time** | User sets a clock time (e.g., 17:30). Countdown to that moment. |

**Controls**:
- `▶ Start` / `⏸ Pause` / `⏹ Stop` buttons
- Category selector: color dot + dropdown of user categories (can change **while timer is running**)
- When running, each elapsed 10-min boundary writes a `Session` record to CoreData, triggering a heatmap cell update

**Timer implementation**:
- `DispatchSourceTimer` on a background queue, fires every **1 second**
- UI updates dispatched to main queue only for visible second changes
- When app is in collapsed state, timer continues running; no UI redraws until expanded

**Completion**:
- On reaching 0:00 → play a subtle system sound (`NSSound.beep` or custom)
- The **toggle chevron button** plays a **shake animation** (horizontal oscillation, 3–4 cycles, ~0.4s duration, `CAKeyframeAnimation`)
- Session is automatically saved

---

### 5. Daily Log File

At **midnight** (day boundary) and on **app quit**, the current day's heatmap data is flushed to a log file:

**Filename**: `YYYY-MM-DD_log.bin` (e.g., `2026-04-12_log.bin`)  
**Location**: `~/Library/Application Support/NativeScheduler/logs/`

**Binary format** — chosen for O(1) random access by time slot and minimal parse overhead:

```
Header (16 bytes):
  [0..3]   Magic: 0x4E534C47 ("NSLG")
  [4..7]   Version: UInt32 = 1
  [8..11]  Date: UInt32 = days since Unix epoch
  [12..15] Reserved

Slot table (144 × 8 bytes = 1152 bytes):
  Per slot (index = hour*6 + minute/10):
    [0]    categoryIndex: UInt8   (0 = default/gray, 1–12 = user categories)
    [1]    dominantMinutes: UInt8 (minutes the dominant category was active, 0–10)
    [2..7] Reserved (zero-padded, for future fields like mood/intensity)

Category index map (appended, variable length):
  [0]    count: UInt8
  Per entry:
    [0]    index: UInt8
    [1..6] colorHex: 6 ASCII bytes  (e.g., "FF5733")
    [7]    nameLen: UInt8
    [8..]  name: UTF-8 bytes
```

**Access pattern**: Slot lookup = seek to `16 + slotIndex * 8` → O(1).  
**File size**: ~1.2 KB per day (negligible; 1 year ≈ 430 KB).  
**Future analysis**: Multiple days can be memory-mapped (`mmap`) and scanned as a flat array — no JSON parsing, no SQLite overhead.

---

### 6. Session Data Model

```swift
// CoreData entities

Session {
    id: UUID
    startTime: Date
    endTime: Date?          // nil while running
    category: Category?
    timerMode: String       // "duration" | "endTime"
}

Category {
    id: UUID
    name: String
    colorHex: String        // stored as "#RRGGBB"
    createdAt: Date
    sessions: [Session]
}

TodoItem {
    id: UUID
    title: String
    isCompleted: Bool
    priority: Int32         // lower = higher priority
    category: Category?
    createdAt: Date
    completedAt: Date?
}
```

---

## Auto-Start & Lifecycle

- Registered with `SMAppService.mainApp.register()` on first launch
- On macOS login, the app launches silently in collapsed state
- `applicationShouldTerminateAfterLastWindowClosed` → `false`
- App never appears in Dock, never shows in Cmd+Tab switcher
- Quit only via right-click context menu on the toggle button

---

## Performance Constraints

| Area | Constraint |
|------|------------|
| Timer tick | Background thread only; 1 Hz |
| Heatmap redraws | Event-driven only (not polling) |
| CoreData writes | Batched, async context |
| Idle CPU | < 0.1% when collapsed |
| Memory | < 30 MB baseline |
| Energy impact | "Low" in Activity Monitor |

---

## Animations

| Trigger | Animation |
|---------|-----------|
| Toggle open/close | Panel slides down/up, spring easing, 0.3s |
| Timer completion | Toggle chevron shakes horizontally (CAKeyframeAnimation) |
| Todo item add | Slide-in from bottom, 0.2s |
| Todo item complete | Strikethrough fade, 0.15s |
| Heatmap cell fill | Color crossfade, 0.3s |

---

## Settings (v1 scope)

Accessible via gear icon in expanded panel:

- Manage categories (add / rename / recolor / delete)
- Toggle launch-at-login on/off
- Default timer duration
- Default timer mode (Duration / End Time)

---

## Out of Scope (v1) — Extensibility Hooks

These are intentionally excluded from v1 but the data model and architecture should not block them:

- Multi-day heatmap history (scroll left for past days)
- iCloud sync via CloudKit
- Stats / analytics view (weekly focus hours by category)
- Notification Center integration
- iPhone companion app
- Shortcuts app integration (`AppIntents`)

---

## File Structure

```
NativeScheduler/
├── App/
│   ├── NativeSchedulerApp.swift      # App entry, SMAppService registration
│   └── AppDelegate.swift             # NSPanel setup, window level
├── Features/
│   ├── FloatingPanel/
│   │   ├── FloatingPanelController.swift
│   │   └── ToggleChevronView.swift
│   ├── Heatmap/
│   │   ├── HeatmapView.swift
│   │   └── HeatmapViewModel.swift
│   ├── Timer/
│   │   ├── TimerView.swift
│   │   ├── TimerViewModel.swift
│   │   └── TimerEngine.swift         # DispatchSourceTimer wrapper
│   ├── Todo/
│   │   ├── TodoListView.swift
│   │   └── TodoViewModel.swift
│   └── Settings/
│       ├── SettingsView.swift
│       └── CategoryEditorView.swift
├── Models/
│   └── NativeScheduler.xcdatamodeld
├── Shared/
│   ├── Extensions/
│   └── DesignSystem/
│       ├── Colors.swift              # #000000 base + category palette
│       └── Typography.swift
└── Resources/
    └── Info.plist                    # LSUIElement = YES
```

---

## Resolved Design Decisions

| Question | Decision |
|----------|----------|
| Multi-monitor | Anchors to `NSScreen.main` (primary screen) only |
| Mission Control / Spaces | `collectionBehavior = [.canJoinAllSpaces, .stationary]` — visible in all virtual desktops |
| Heatmap scope | Today only (v1). Past days accessible only via log files |
| Timer–Todo relationship | Fully independent — no auto-linking in v1 |
| Log format | Fixed-width binary (`.bin`), O(1) slot access, `mmap`-friendly for future analysis |
