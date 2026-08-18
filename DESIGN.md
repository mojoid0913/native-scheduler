# NativeScheduler Dayline Design Contract

Status: approved for the daily-time narrative redesign. This document is the
implementation contract for the current-day and expanded recent-five-day
`Dayline / 오늘의 흐름`; it is not
a general visual refresh.

## Product role and scope

Dayline is a quiet reflection layer beneath the existing task and timer flow.
It explains what happened today without becoming a second control surface.
Compact Dayline shows only the current local calendar day. Its own expanded
state shows exactly five newest-first local calendar days (Today plus four
locale dates). The existing date header remains visible. The labelled
expand/collapse control sits midway between the Dayline and timer cards,
centred in the right column and rotated 90 degrees to describe the horizontal
expansion.

The following are explicitly out of scope: history or day navigation, calendar
import, automatic app tracking, goals, streaks, coaching, billing, analytics
dashboards, record editing, drag/resize editing, Core Data migration, new
dependencies, horizontal scrolling, and changes to tasks, timer inputs,
categories, settings, notch geometry, or the collapsed timer ring.

## Dayline anatomy

### Compact

- Title: `오늘의 흐름`.
- Header metadata: `Today · <total tracked>`; the native labelled expand button
  remains between Dayline and the timer.
- One rolling eight-hour lane, calendar-clipped and centred on context: two
  elapsed hours, the current time, and five upcoming hours when the day has
  capacity. Tick labels occur every two hours.
- Exact session blocks, an explicit now marker, and a detail row are visible at
  the same time. The detail defaults to the **active or most recent** session.

### Expanded

- The same title, date header, total, detail row, and inter-card labelled
  collapse button.
- Exactly five newest-first 24-hour rows: Today plus the previous four local
  calendar dates. Every row is visible at once and uses proportional elapsed
  seconds, not a 15-minute grid.
- Rows have 20pt height with 10pt tracks, a shared `00 06 12 18 24` axis, and
  per-day totals. The card inset is 8pt; meaningful text is at least 11pt and
  controls are at least 24pt.
- Past, untracked, category, selected, and now-marker states remain
  distinguishable without interaction or horizontal scrolling. Only Today has
  future, now-marker, or active semantics.
- The category summary below is derived from the same immutable day snapshot.

## Fixed-shell density

The outer notch shell remains exactly `816×384`. `NotchView` applies 20pt
horizontal padding on each side, a top inset of `notchHeight + 10`, and a 16pt
bottom inset before `MainPanelView` is proposed. Therefore the real child is
`776 × (384 - (notchHeight + 10) - 16)`: at the canonical 37pt notch it is
`776×321` (and it is valid for 32–42pt notches).

The shell menu remains a 24pt circular control and does not reserve layout
height from the right-column cards. The expand/collapse control is integrated
into the 24pt inter-column disclosure rail, remains fully pressable, and does
not reserve vertical height from the right-column stack. Dayline and the timer
use a 10pt vertical gutter. When Dayline is expanded, the timer/summary row is
32% of the available stack content, with a 78pt floor and 92pt cap; Dayline
receives the remainder. In the compact state the timer is capped at 148pt and
the reclaimed height goes to today's Dayline card. Malformed undersized layout
proposals cap the gutter to available content and the timer to the remaining
stack content, so allocations never overflow.
No outer resize,
global scale, scrolling, text below 11pt, hidden day row, clipped timer control,
or target below 24pt is allowed.

## Data and rendering truth

The source of UI truth is one immutable current-day snapshot while compact, or
one immutable five-local-day window while expanded. Compact fetches sessions
whose exact ranges overlap the local day once per reload. Expanded fetches one
range `[startOfDay(today-4), nextDayStart(today))` once per reload; it does not
use five independent fetches. Both copy managed values into immutable records,
clip to day bounds and `now`, and derive chronological segments and category
totals from those records. One-second ticks reproject Today only and never
refetch; older four snapshots remain stable. Relevant saves and local-day
rollover reload once. A same-window fetch failure retains the last good data; a
rollover failure publishes an empty new-day snapshot with a visible
non-disruptive error state.

Ranges are half-open `[start,end)`. Invalid, zero/negative, future, and
out-of-day portions are ignored. Overlaps are partitioned at every valid
boundary; the latest start wins, and equal starts use the lexicographically
greatest lowercase session UUID. Adjacent winning pieces merge only when their
session/category identity matches. Totals sum winning pieces only, so overlap
cannot double-count. Stable segment identity is the source session UUID plus
the normalized piece start instant; a live piece keeps its identity while its
end advances.

Legacy `HeatmapSlot`, `SessionEntity.sessions(forSlot:)`,
`DailyLogWriter`, `FloatingPanelController.flushDailyLog()`,
`AppDelegate`, and `MultiDayHeatmapView` remain compile-time or logging
compatibility infrastructure. They are not Dayline UI truth and are not
deleted, migrated, or used to infer timeline boundaries.

## Semantic tokens and states

Use existing dark surfaces (`#000000`, `#111111`, `#2A2A2A`) and existing
category colors. Add only named Dayline roles mapped to those primitives:

| Role | Meaning |
|---|---|
| `daylinePastTrack` | elapsed time without a recorded segment |
| `daylineFutureTrack` | time after `now` |
| `daylineCategory` | persisted category hue for a winning segment |
| `daylineDefaultCategory` | default/no-category fallback, exact `#4DABF7` |
| `daylineNowMarker` | current instant, independent of category color |
| `daylineSelected` | focus/selection treatment, never the category identity |
| `daylineError` | fetch warning, independent of category color |

Required states are empty day, open/active segment, closed segment, **active or
most recent** fallback, pointer/keyboard selected segment, overlapping or
invalid stored ranges after normalization, same-day error with retained data,
rollover error with an empty new day, past track, future track, and local
23-hour or 25-hour day. A default category remains labelled “Default”.

Every category has a stable **non-color pattern** or marker (for example a
short stroke pattern) paired with its name. The detail and summary text expose
category, range, duration, and active state; short blocks do not require
cramped inline text. Color is never the sole identifier.

## Interaction, accessibility, and motion

The visible title is `Stream`; its accessibility label is
`Stream, 오늘 기록 <duration>`. Accessibility order is header, labelled
toggle, then newest-day segments through oldest-day segments. Keyboard order
is toggle then blocks, with visible focus. Hover and focus may inspect a block;
click or Enter/Space pins it. Blur, pointer exit, or the explicit “Return to
current activity” action returns to the active-or-most-recent detail. Escape
remains owned by `NotchWindow` and closes the panel; Dayline installs no Escape
handler.

All visible text styles are at least 11pt where the card carries meaning.
VoiceOver/AX labels include category/default, start/end, duration, and active
state. Decorative shapes are hidden from AX. Reduce Motion disables
non-essential springs, pulses, and selection transitions while preserving the
static timeline, endpoint, marker, labels, and focus state. Existing timer,
notch hover, completion, warning, and error semantics remain intact.

Disclosure expansion uses the existing weighted spring (`response: 0.28`,
`dampingFraction: 0.82`) as an interruptible shared-layout morph. The compact
Stream lane becomes the newest row while the four older rows reveal below it;
the Timer card retains its layout identity as Today enters from the leading
half. Reduce Motion snaps directly to the destination layout.

## Timer completion shell and Count Up activity mark

Status: approved presentation contract. This extends the retained notch shell
without changing timer arithmetic, persistence, dependencies, or shell geometry.
The interaction mechanism adapts beui.dev's `animated-badge` state pulse: opacity
and scale communicate active status, while Reduce Motion preserves the status as
a static endpoint.

### Completion outer-shell border

An accepted automatic Duration or End Time finish publishes one final **idle**
`NotchTimerSnapshot` synchronously, after session finalization, before activating
the completion effect. This atomic ordering ensures the first alert frame never
outlines the extended running-indicator rail. The retained `NotchTimerState`, not
view-local state, owns one generation-safe 3.0-second effect so SwiftUI root
reconstruction and collapsed/expanded retargeting preserve the original phase
and deadline.

The border is semantic red, 2pt, and drawn by a native shape layer using the
`NotchShape.inset(by: 1)` path, the raster-equivalent of `strokeBorder`, fully
inside the unchanged outer edge. Collapsed geometry follows the rendered
camera-attached idle shell. Expanded geometry follows the complete `816x384`
outer `NotchShape`; shadow padding is never outlined. Expansion and collapse
retarget only geometry and never restart timing.

Normal-motion phase endpoints use 0.5-second `easeInOut` opacity transitions:

| Time | Border opacity |
|---:|---:|
| 0.0s | 1.0 |
| 0.5s | 0.25 |
| 1.0s | 1.0 |
| 1.5s | 0.25 |
| 2.0s | 1.0 |
| 2.5s | 0.25 |
| 3.0s | removed |

Reduce Motion keeps a solid opacity-1.0 red border for the same 3.0-second
lifetime, then removes it without a transition. Starting, stopping, resetting,
pausing, changing category, changing mode, expanding, or collapsing during an
active effect neither cancels nor restarts it. Only a distinct accepted
automatic finish begins a fresh generation and 3.0-second deadline. Stale phase
callbacks cannot mutate a newer generation. Expiry and `NotchTimerState`
deinitialization cancel all owned scheduled work.

### Collapsed timer activity semantics

The retained snapshot has exactly three semantic states: idle, determinate
countdown, and active Count Up. Active Duration and End Time use the existing
category-colored determinate ring. Active Count Up never exposes zero trim,
fake progress, a percentage, or an infinity glyph; it uses the existing
`stopwatch` SF Symbol in the selected category color. Paused, stopped, and reset
Count Up are idle and do not animate.

With normal motion, the active stopwatch breathes through one full 1.6-second
round trip using `easeInOut`: from scale 0.94 / opacity 0.72 to scale 1.04 /
opacity 1.0 over 0.8 seconds, then back to scale 0.94 / opacity 0.72 over 0.8
seconds, repeating only while Count Up remains active. Its retained phase origin
survives SwiftUI root reconstruction and category-only snapshot updates. Reduce
Motion renders a static scale-1.0 / opacity-1.0 stopwatch. The ring, stopwatch,
and completion border are accessibility-hidden decoration; the collapsed shell
control exposes a textual timer status (`Idle`, `Countdown running`, or
`Count Up running`) so color and motion are never the only status cues.

No completion bounce, elastic scale, blur, rotation, internal Timer-card
keyline, full-screen overlay, host-window border, stroke around shadow padding,
or non-active Count Up motion is allowed. Existing Stream/Timer density tokens,
outer dimensions, hover/click behavior, sound, session finalization, and normal
profile data remain unchanged.

### Accessibility constraints and accepted debt

- Motion-sensitive users receive static completion and Count Up indicators with
  unchanged meaning and completion lifetime.
- VoiceOver receives status text from the shell control; decorative marks remain
  hidden to prevent duplicate announcements.
- The fixed camera-attached shell and 18pt activity mark are accepted geometry
  constraints. The shell control remains the operable target; the mark is not a
  separate target and therefore carries no standalone hit-area debt.

## Acceptance boundary

The old checkerboard and its 15-minute cells are retired as a production UI
concept. A passing implementation shows `Stream` in compact and expanded
surfaces, keeps totals equal between Dayline and summary, shows exactly the
specified five-day window only while expanded, and leaves every retained
logging and timer compatibility API compiling unchanged.

## Global panel balance refresh

Status: approved for the full-app balance pass. This section preserves the
existing compact, black, notch-attached visual direction while making Tasks,
Dayline, Timer, Settings, and supporting popovers feel like one system. It
extends the earlier Dayline-only scope; it does not change product behavior,
outer notch geometry, data density, or information architecture.

### Shared visual tokens

- Canvas stays `#000000`; card surfaces stay `#111111`; elevated sheets and
  popovers use `#161616`.
- Primary text stays `#EFEFEF`. Secondary text moves to `#8A8A8A` for reliable
  small-text contrast; tertiary labels use `#858585` so muted metadata does not
  compete with content.
- Product card titles are 12pt semibold. Body copy is 11pt regular, metadata is
  10pt medium, and compact numeric/date labels use monospaced 11pt medium.
- The spacing scale is 4, 6, 8, 10, 12, and 16pt. Product cards use 12pt content
  insets where width permits; adjacent cards use a 10pt gutter.
- Product cards use a continuous 10pt radius and a 0.5pt low-contrast keyline.
  Inputs and segmented controls use 6–8pt radii; compact hover rows use 6pt.
- Pointer controls retain at least a 24pt hit target. Visible glyphs may remain
  smaller when their hit regions satisfy the target.

### Balance rules

- The panel date is context, not a card title. It remains monospaced and muted.
- Tasks and Dayline share the same title weight, text baseline, and card inset.
- The task workspace remains wider than the timer column, but the timer column
  must not feel pinched; at the canonical shell it is 244pt wide.
- Internal dividers are tertiary structure: inset or reduced-opacity, never as
  visually strong as the card edge.
- Timer input, action, category, and mode controls align to the same vertical
  rhythm in compact and expanded Dayline states.
- Settings uses the same title, row, control-target, radius, and color hierarchy
  as the main panel rather than the default macOS form hierarchy.

### Accessibility and accepted debt

- No meaningful text is smaller than 10pt outside existing Dayline axis/minute
  labels whose compact geometry is contractually fixed.
- Secondary copy must meet normal-text contrast against its actual surface.
- Color is never the only state cue; existing pattern, label, icon, and
  accessibility semantics remain intact.
- The fixed `816×384` shell and compact 24-hour axis impose intentional density.
  This pass accepts that constraint and does not add scrolling or enlarge the
  outer shell to manufacture whitespace.
