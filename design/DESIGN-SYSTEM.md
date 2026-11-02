# Showreel design system

Native macOS 26. System parts and colors come first. The tokens below cover
only what the system does not draw: the canvas, the timeline, the floating
recording chrome, and the Camera Bubble. Views never contain raw colors,
radii, durations, or springs. Layout decisions live in `docs/DESIGN.md`.

## Theme.swift (accent)
- `ThemeStore.defaultID = "system"`: the accent follows the Mac. No brand
  color (`ThemeStore.brand = nil`). People can pick one in Settings > Appearance.
- Use `.tint` or `Palette.accent` for fills, `Palette.accentText` for
  accent-colored text, and `Palette.onAccent` for text on an accent fill.
- The accent marks selection and focus: selected cards, selected timeline
  blocks, and toggles that are on. It is never a track color.
- Every custom color has light, dark, and two Increase Contrast values
  (`Color(light:dark:highContrastLight:highContrastDark:)`).

## Grid.swift (spacing)
- `Space`: 4 pt grid. 20 pt window margins (`Space.margin`), 8 between related
  controls, 20 between groups. Mark custom pages with `.gridArea` and `.gridProbe`.

## Surfaces.swift
- `Surfaces.surface` / `surfaceHover`: custom neutral areas (transport bar,
  card hover). They are translucent so they take the desktop tint.
- `Surfaces.hairline`: lines between timeline rows and around the transport.
- `Surfaces.warning`: the one warning color, always with an icon and words.
- `Surfaces.canvasBackdrop`: behind the editor canvas only.
- `Surfaces.scrim` + `Surfaces.onScrim`: text on video or the desktop (the
  Countdown hint, labels over thumbnails).
- `Media.record`: Start Recording, the recording dot, and the menu bar extra
  while recording. Never decoration.
- `Media.playhead`: the playhead line and its cap.
- `Media.Track.clip / zoom / blur / caption / audio`: timeline block fills. White
  text on each passes 4.5:1 in every mode, and labels use `Media.Track.label`.
  Each track's header shows its SF Symbol, so color is never the only cue.
  `Media.Track.lane` is the empty row behind blocks.
- Never copy a semantic color (`.separator` as text, a label color as a fill).

## Radius.swift
- `xs 6` timeline blocks and chips · `sm 8` hand-drawn controls ·
  `thumbnail 10` project card thumbnails · `md 12` cards and grouped
  surfaces · `lg 18` large previews · `xl 26` floating glass that is not a capsule.
- The Record Panel, the Recording Controls, and the Camera Bubble's hover
  controls are `Capsule()`. The Camera Bubble is a `Circle()` or a rounded
  square at `bubbleSquareRatio` of its size.
- Use `Radius.shape(_:)` (continuous corners). Inner = outer − inset.

## Layout.swift
- Library: `cardMinWidth`, `thumbnailAspect` (16:10).
- Editor: `inspectorWidth`, `timelineHeight`, `trackHeaderWidth`,
  `trackHeight`, `playheadWidth`, `selectionRing`.
- Recording chrome: `recordPanel`, `countdownCircle`, `controlsInset`.
- Camera Bubble: `bubbleSizes` (Small, Medium, Large) and `snapDistance`.
- Windows: `welcomeWidth`, `settingsWidth`.

## Motion.swift
- `hover` fills and lifts · `quick` presses and toggles · `ui` sections and
  the inspector swapping · `select` selection on the timeline and grid ·
  `appear` / `dismiss` panels and hover controls (dismiss is faster) ·
  `glide` the bubble snapping · `numberRoll` time and sizes ·
  `listChange` cards in and out · `countdownTick` each Countdown number ·
  `pulse` the recording dot (a loop).
- Animate with `withMotion(...)` or `.animation(Motion.resolved(...), value:)`.
  Under Reduce Motion, movement becomes `fade` and loops stop.
- Never animate a view's first layout. Search results never animate.
  Only numbers roll, never their units (`.contentTransition(.numericText())`).
- Timeline scrubbing and playback never animate: the preview follows the
  playhead in the same frame.

## Glass
- Glass only on floating controls: the Record Panel, the Countdown circle,
  the Recording Controls, the Camera Bubble's hover controls, and the system
  toolbar and inspector. Never on the canvas, cards, timeline blocks, or the
  bubble's video.
- Group neighbors in one `GlassEffectContainer`. Never glass on glass.
- Tint glass only to carry meaning: Start Recording uses `Media.record`.
- Leave about 3 times the shadow radius around floating glass.

## Controls
- Style controls with `ButtonStyle` / `ToggleStyle`. Never rebuild a control
  from shapes. One prominent button per surface (Start Recording, Export…).
- Hover never moves a selection. Only a click or a key does.
- Body text stays in the system font. Times use `.monospacedDigit()`.

## Check

```bash
grep -rnE 'cornerRadius: [0-9]{1,2}\b|duration: [0-9]|\.spring\(response|\.snappy\b|\.easeInOut|\.easeOut\(|Color\(hex:|Color\(red:' Sources/ \
  | grep -v 'Path(roundedRect' | grep -vE 'UI/(Theme|Motion|Surfaces|Radius)\.swift'
```
No output means no raw values outside the token files.
