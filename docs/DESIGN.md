# Showreel — Design plan

Native macOS 26. The system parts come first. Custom drawing is used only
where the system has nothing: the canvas, the timeline, the camera bubble,
and the floating recording chrome. `improve-loop` follows this file, and a
change to a decision is made here first.

## Feeling

**Confident.** You press one button, and what comes out looks like a
professional made it. The chrome stays quiet so the video stands out. Motion
is smooth and springy but brief, never playful. Words are short and calm.

## Archetype

A regular Dock app with three entry points:

| Entry point | What it is | Opens |
| --- | --- | --- |
| Global shortcut ⌃⌥⌘R | Starts or stops a recording from any app | Record Panel / stops |
| Menu bar extra | Always present. A red dot and the elapsed time while recording | Menu (see Command map) |
| Dock icon and Dock menu | New Recording, Open Library | Library window |

Windows and panels:

| Surface | SwiftUI / AppKit | Notes |
| --- | --- | --- |
| Library | `Window("Library", id: "library")` | One page, so no sidebar. A grid of project cards |
| Editor | `WindowGroup(id: "editor", for: UUID.self)` | One window per project. Reopens on relaunch |
| Welcome | `Window("Welcome to Showreel", id: "welcome")` | Permissions (S-001). Small and fixed size |
| Record Panel | `NSPanel` (non-activating, `.floating`) hosting SwiftUI | Floating glass control, never in Window menu |
| Countdown | Borderless full-screen `NSPanel` on the recorded display | Ignores mouse except click-to-cancel |
| Recording Controls | Borderless `NSPanel`, `.statusBar` level | Glass capsule. Excluded from capture |
| Camera Bubble | Borderless `NSPanel`, `.floating`, movable by background | Content, not glass. Excluded from capture |
| Area selector | Borderless full-screen `NSPanel` per display | Dims, draws the selection |
| Settings | `Settings` scene | Tabs: General, Recording, Export, Appearance |

Every Showreel panel sets `sharingType = .none`, and the `SCContentFilter`
excludes the app's own windows. Our chrome never shows up in a recording.

## Library (S-008, S-010)

- No `NavigationSplitView`. A `ScrollView` with an adaptive `LazyVGrid`
  (cards min 220 pt, 16:10 thumbnails), 20 pt margins, 20 pt gaps.
- Card: the thumbnail is content (rounded 10 pt, no glass), with the title
  below in `.headline`, and length and date in `.secondary` ("0:42 · Today,
  10:14"). Selection is an accent ring of 3 pt outside the thumbnail. Hover
  slightly lifts the thumbnail shadow.
- Toolbar: title "Library", subtitle "3 projects". Trailing: New Recording
  (`record.circle`, ⌘N) and search (`.searchable`, ⌘F filters by title).
  New Recording is not prominent.
- Empty: `ContentUnavailableView("No Recordings Yet")` with the line from the
  UX block and a "New Recording" button. No results:
  `ContentUnavailableView.search`.

## Record Panel (S-002 to S-006)

A horizontal glass bar about 600 × 56 pt, centered near the top of the
active display, which you can drag by its background. One
`GlassEffectContainer`:

```text
[ Display | Window | Area ▾ ]  ·  [🎙 Mic ▾ ▮▮▯]  [📷 Camera ▾]  [🔊 System Audio]  ·  [● Start Recording]  [×]
```

- The source is a segmented control. Display and Window open a popover with
  thumbnails (Display shows when there is more than one display).
- Toggles are glass buttons that show their state with a symbol (`mic` /
  `mic.slash`) and a word. They never show state by tint alone. The chevron
  opens a device `Menu`.
- Start Recording is the only prominent control, tinted `.red` (red carries
  the meaning "record"). It says "Start Recording", not just a dot.
- The close button (`xmark`) is at the trailing edge. Escape closes.
- Problems (no access, device lost) show inline under the bar in a second
  glass row. They are never alerts.

## Countdown and Recording Controls (S-007)

- Countdown: a 160 pt glass circle with the number in `.system(size: 72,
  weight: .semibold, design: .rounded)`, centered on the recorded display.
  Each number scales from 0.9 to 1 and fades. With Reduce Motion it only
  fades. "Click anywhere or press Escape to cancel" shows under it in
  `.callout` on a scrim.
- Recording Controls: a glass capsule at the bottom center of the recorded
  display, 24 pt from the edge:
  `[● 1:12] | [Pause] [Stop] | [Restart]`. Monospaced digits. The red dot
  pulses (fades instead with Reduce Motion). Paused: the time blinks, and
  "Paused" replaces the dot.
- The menu bar extra mirrors the state, so the capsule can be hidden.

## Camera Bubble (S-011 to S-014)

- Content, not chrome: the live camera in a circle (or a rounded square of
  24% radius), mirrored, with a 1 pt `.separator` stroke and a soft shadow.
  Sizes: Small 120, Medium 180, Large 240 pt.
- On hover, a small glass capsule fades in below the bubble: size (S M L) and
  shape. It hides again 1 s after the pointer leaves.
- Dragging snaps to corners and edge midpoints (24 pt inset) with a short
  spring.

## Editor (S-015 onward)

Native layout, not a copy of the reference. The reference's left section
rail becomes a **trailing inspector**, the way Keynote, Final Cut Pro, and
Pixelmator Pro do it. The canvas gets the most space, and the inspector
toggles with ⌃⌘I.

```text
┌ toolbar: Title · 0:42     [↶ ↷]                 [Export…]  [⎅] ┐
│                                              │ [🖼 ▭ ✨ 👤 💬 〰] │ inspector
│               canvas (preview)               │ Background         │ 280–340 pt
│                                              │  …grouped Form…    │
├──────────────────────────────────────────────┤                    │
│ ✂ Split  ⊕ Add Zoom   ▶ 0:00.0 / 0:42.0   − ━━● + Fit │          │
│ ▭ clip  ████████████████████                 │                    │
│ 🔍 zoom   ▓▓▓     ▓▓▓▓    ▓▓                  │                    │
│ 💬 captions ▒▒ ▒▒▒ ▒▒                         │                    │
│ 〰 audio  ∿∿∿∿∿∿∿∿∿∿∿∿∿∿                      │                    │
└──────────────────────────────────────────────┴────────────────────┘
```

- **Structure:** a `VSplitView` with the canvas on top and the timeline below
  (min 212 pt, which fits the transport, the ruler, and four lanes). `.inspector` sits on the outer view.
- **Inspector:** at the top, a segmented `Picker` with six symbols, each with
  a title and `.help`: Background `photo`, Screen `macwindow`, Effects
  `cursorarrow.rays`, Camera `person.crop.circle`, Captions `captions.bubble`,
  Audio `waveform`. Below it, one grouped `Form` per section, using
  `Section`s that collapse like the reference's cards. Selecting a zoom or a
  caption on the timeline swaps the inspector to that item ("Zoom" with
  Scale and Focus, Delete at the bottom). Esc returns to the section.
- **Toolbar** (3 groups): leading title plus subtitle (the length). Center:
  Undo and Redo (`arrow.uturn.backward` / `.forward`). Trailing: Export…
  (prominent, the completing action), then the inspector toggle. No Share
  button: sharing happens after export (S-038).
- **Canvas:** centered in `Color(nsColor: .underPageBackgroundColor)`,
  aspect-fit, Metal-backed. The preview is content: no glass, no chrome
  over it. Crop and camera dragging draw handles directly on it.
- **Timeline:** custom drawn. A 28 pt header column with each track's
  symbol (meaning never rests on color alone). Track blocks are 6 pt
  radius, filled with the track token from `design-system`. Selected blocks
  get a 2 pt accent ring and edge handles. The playhead token is a
  contrasting line with a cap.
- **Transport row** above the tracks: Split (`scissors`), Add Zoom
  (`plus.magnifyingglass`), then centered Play/Pause with the time in
  monospaced digits, then trailing timeline zoom `−` slider `+` and Fit.
  `.controlSize(.small)`.
- **Inspector empty states:** Captions with no mic track shows "No Voice
  Recorded" and "Turn on the mic for your next recording to get captions."
  Camera with no camera track shows "No Camera in This Recording". The zoom
  track with no zooms shows the inline hint "Click to add a zoom".

## Command map

Every command is in the menu bar. Toolbar and context menu items repeat it.

| Menu | Item | Shortcut | Story |
| --- | --- | --- | --- |
| Showreel | About Showreel, Settings…, Quit Showreel | ⌘, ⌘Q | — |
| File | New Recording | ⌘N | S-002 |
| File | Open | ⌘O (Return in Library) | S-009 |
| File | Close | ⌘W | — |
| File | Duplicate | ⌘D | S-010 |
| File | Rename… | — (Return on a card) | S-010 |
| File | Show in Finder | ⌥⌘R | S-010 |
| File | Export… | ⌘E | S-036 |
| File | Move to Trash | ⌘⌫ | S-010 |
| Edit | Undo / Redo <action> | ⌘Z / ⇧⌘Z | S-020 |
| Edit | Cut, Copy, Paste, Delete, Select All | standard | S-032 |
| Clip | Delete Section / Delete Zoom (follows the selection) | ⌫ | S-019, S-031 |
| View | Show/Hide Toolbar, Show/Hide Inspector | ⌥⌘T, ⌃⌘I | S-015 |
| View | Zoom In / Zoom Out / Zoom to Fit (timeline) | ⌘+ / ⌘− / ⇧Z | S-017 |
| View | Enter Full Screen | ⌃⌘F | — |
| Record | Start Recording / Stop Recording | ⌃⌥⌘R | S-007 |
| Record | Pause Recording / Resume Recording | ⌃⌥⌘P | S-007 |
| Record | Restart Recording | — | S-007 |
| Record | Hide Camera Bubble / Show Camera Bubble | ⌃⌥⌘C | S-014 |
| Clip | Split at Playhead | S | S-019 |
| Clip | Trim Start to Playhead / Trim End to Playhead | ⌥[ / ⌥] | S-018 |
| Clip | Add Zoom | Z | S-032 |
| Clip | Generate Captions… | — | S-039 |
| Playback | Play / Pause | Space | S-016 |
| Playback | Previous Frame / Next Frame | ← / → | S-016 |
| Playback | Back 1 Second / Forward 1 Second | ⇧← / ⇧→ | S-016 |
| Playback | Go to Start / Go to End | Home / End | S-016 |
| Window | Library | ⌘0 | S-008 |
| Help | Showreel Help, Check Access… | — | S-001 |

- **Menu bar extra:** New Recording (⌃⌥⌘R), Open Library, a separator, up to
  three recent projects, a separator, Settings…, Quit Showreel. While
  recording, the top item becomes "Stop Recording 1:12", followed by Pause
  Recording.
- **Dock menu:** New Recording and Open Library.
- **Project card context menu:** Open · Rename · Show in Finder · Duplicate ·
  Export… · Move to Trash. No shortcuts are shown.
- **Timeline block context menu:** Delete · Split at Playhead (clip) or
  Edit Zoom (zoom).

## Rules for improve-loop

- Glass only on the Record Panel, the Countdown, the Recording Controls, the
  Camera Bubble's hover controls, and the toolbar and inspector chrome. Never
  on the canvas, cards, or timeline blocks.
- Colors, radii, track colors, and motion come from `design-system` tokens,
  never literals in views.
- Every floating panel opens without taking focus from the app being
  recorded, except when opened with the global shortcut (S-002).
- Snapshot pages in `docs/STORIES.md` cover every surface above, in light and
  dark, captured as the key window.
