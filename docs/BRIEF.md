# Showreel

A native Mac app that records your screen, voice, and face, then turns the
recording into a polished product demo with auto-zoom, styled frames, and
captions. Built for founders, PMs, and developers who make demo videos.

Bundle id: `com.momensherif.showreel`

## Replaces
Screen Studio, Recordio, FocuSee, or QuickTime plus a video editor.

## Main jobs
1. **Record**: pick a display, window, or area. Turn the mic, system audio,
   and camera on or off. Drag the round camera bubble anywhere, start and
   stop from the menu bar or a global shortcut.
2. **Polish**: in the editor, set the background, padding, rounding,
   shadow or glow, crop, and device frame. Auto-zoom follows your clicks and
   you can edit each zoom on the timeline. The cursor is smoothed and clicks
   show a ripple. Captions are made automatically.
3. **Export**: trim and cut, then export MP4, MOV, or GIF at 1080p or 4K and
   30 or 60 fps, and share with the macOS Share sheet.

## Data
- **Project**: title, created date, duration, source kind, style settings
  (background, padding, rounding, shadow/glow, device frame, crop), and
  camera bubble settings (position, size, shape, visible).
- **Recording assets** (files in the project folder): screen video without
  the cursor, camera video, mic audio, system audio, and a cursor and click
  event log (time, x, y, type).
- **ZoomSegment**: start, end, scale, focus point, follow-cursor flag, and
  whether it was made automatically or by hand.
- **TimelineEdit**: cuts and trims (start and end ranges), and speed.
- **CaptionSegment**: start, end, and text.

Every track is recorded separately, so the editor can redraw the cursor,
zoom, and camera without any loss in quality.

## Shape
A main window with a project library, plus an editor: an inspector sidebar
(Background, Screen, Effects, Camera, Captions, Audio), a canvas preview,
and a timeline with tracks for the clip, zooms, captions, and audio. A menu
bar item and a floating record panel. A camera bubble overlay is shown
while recording. macOS 26 or later. Local data, works offline, no accounts.

## System hooks
ScreenCaptureKit (screen and system audio), AVFoundation (camera and mic),
a global mouse monitor for the click and cursor log, a global start/stop
shortcut, a menu bar extra, on-device speech (SpeechAnalyzer) for captions,
and the Share sheet. Permissions needed: Screen Recording, Camera, and
Microphone.

## Reference
Recordio's editor (screenshot provided). Screen Studio for auto-zoom and
cursor feel.

## Look
Native macOS 26 with Liquid Glass, system sidebar and inspector, follows
light and dark mode, uses the system accent color. Uses the reference for
layout only, not for its look.

## Design plan
See `docs/DESIGN.md`: archetype, surfaces, editor layout, and command map.

## Not in version one
- Cloud upload, share links, accounts, teams
- Blur regions
- Recording an iPhone or iPad, multiple clips per project, background music

## Iterations
1. **Recorder core**: menu bar, record panel, source picker, mic, camera,
   and system audio toggles, separate track files, cursor and click log,
   project library.
2. **Camera bubble**: a live circle overlay you can drag and resize while
   recording, with its position saved to the project.
3. **Editor shell**: inspector, canvas preview, playback, timeline with a
   clip track, trim and cut, undo and redo.
4. **Styling**: background, padding, rounding, shadow and glow, crop,
   device frames, camera bubble settings.
5. **Auto-zoom and cursor**: zooms made from clicks, a zoom track you can
   edit, smooth easing, cursor smoothing and size, click ripples.
6. **Export**: Metal renderer, MP4, MOV, and GIF, resolution and fps
   choices, progress, Share sheet.
7. **Captions and audio**: on-device transcription, a caption track you can
   edit, caption styles, volume and noise reduction.
8. **Polish**: performance, keyboard shortcuts, onboarding for permissions.
