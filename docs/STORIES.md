# Showreel — Stories

Source: `docs/BRIEF.md`. Reference: `docs/screens/reference-editor.png`
(Recordio). The reference is used for layout only. The look is native macOS 26.

Snapshot pages: `permissions`, `menubar`, `record-panel`, `source-picker`,
`area-selector`, `countdown`, `recording-controls`, `camera-bubble`, `library`,
`library-empty`, `editor`, `editor-background`, `editor-screen`,
`editor-camera`, `editor-effects`, `editor-captions`, `editor-audio`,
`editor-zoom-selected`, `crop-sheet`, `export-sheet`, `export-progress`,
`settings`.

Seed data (snapshot mode): three projects ("Onboarding walkthrough" 0:42,
"Pricing page tour" 1:15, "API keys demo" 0:28). Each one has a style, zoom
segments, and captions, all of which the user can create with the stories
below.

---

## M1 Recorder core
Done when you can record a display with your mic and camera, find the
project in the library after a restart, play it back, and open its files
in Finder.

### S-001 Grant permissions on first launch
As the user, on first launch I see the access Showreel needs (Screen
Recording, Microphone, Camera) and grant each one from that page.
Screens: permissions
Acceptance:
- [snap] Three rows, each with an icon, the reason it is needed, a status
  ("Allowed" / "Not allowed"), and an "Open System Settings" button.
- [self] Status changes within 2 seconds of being granted, without a
  relaunch (Screen Recording may still ask for a relaunch, and the page
  says so).
- [manual] Microphone and Camera show the system prompt. Screen Recording
  opens Privacy & Security.
- [self] Mic and camera are optional. Only Screen Recording blocks
  recording.
UX:
- Flow: first launch, or Settings > Recording > "Check Access…" -> Welcome window -> click Allow on each row -> system prompt or Privacy & Security -> row turns to "Allowed" -> "Continue" opens the Record Panel. Closing the window or pressing Escape skips it, and the window comes back the next time you choose New Recording without Screen Recording access.
- Surface: new window "Welcome to Showreel" (a self-contained task done once).
- States: each row is either "Not allowed" (an Allow button) or "Allowed" (a green checkmark and the word). Screen Recording granted but not active yet: "Quit and reopen Showreel to finish" with a "Quit & Reopen" button. Continue is disabled until Screen Recording is allowed, with the inline hint "Screen Recording is required to record."
- Words: title "Welcome to Showreel", subtitle "Showreel needs your permission to record. Your recordings stay on this Mac." Rows: "Screen Recording: to record your displays and windows", "Microphone: to record your voice (optional)", "Camera: to show you in a Camera Bubble (optional)". Buttons "Allow…", "Continue".
- Access: Tab moves through the Allow buttons, and Return triggers Continue. VoiceOver reads "Screen Recording, not allowed, Allow button". Status uses an icon and a word, never color alone.
Status: done
Note: the system prompts and the Screen Recording relaunch need a person to try ([manual]).

### S-002 Open the record panel from the menu bar or a shortcut
As the user, I click the menu bar icon or press ⌃⌥⌘R to open the floating
record panel.
Screens: menubar, record-panel
Depends: S-001
Acceptance:
- [snap] The menu bar menu has New Recording, Open Library, Settings…, and
  Quit.
- [snap] The record panel is a small glass panel above all windows. It has
  a source control, Mic, Camera, and System Audio toggles, and a red Record
  button.
- [self] Pressing the shortcut again, or Esc, closes the panel.
UX:
- Flow: menu bar icon > New Recording, ⌃⌥⌘R, Library toolbar "New Recording" (⌘N), or Dock menu -> the Record Panel appears centered near the top of the active display -> set up -> Start Recording. Escape, ⌃⌥⌘R, or clicking the close button hides it without changing anything.
- Surface: panel (a tool kept open beside the work, non-activating so the app you are about to record keeps focus).
- States: no Screen Recording access shows an inline "Allow Screen Recording…" button in place of Start Recording. The menu bar icon is red with the elapsed time while recording.
- Words: menu "New Recording ⌃⌥⌘R", "Open Library", "Settings…", "Quit Showreel". Panel button "Start Recording". Tooltip on the menu bar icon: "Showreel: New Recording (⌃⌥⌘R)".
- Access: the panel takes keyboard focus when opened from the shortcut. Tab order: Source, Mic, Camera, System Audio, Start Recording. Return starts.
Status: done

### S-003 Choose what to record: display, window, or area
As the user, I choose a display, a window, or an area I drag out before
recording.
Screens: record-panel, source-picker, area-selector
Depends: S-002
Acceptance:
- [snap] The source picker lists displays and windows with live
  thumbnails, grouped by app.
- [snap] Area mode dims the screen and shows the selection with its size
  in pixels and handles to resize it.
- [unit] The chosen source maps to the right `SCContentFilter`, and
  Showreel's own windows are always excluded.
- [self] The last source is remembered.
UX:
- Flow: Record Panel source control (Display | Window | Area) -> Display or Window opens a popover with live thumbnails -> click one -> the popover closes and the control shows its name. Area dims every display -> drag a rectangle -> adjust the handles -> Return confirms and Escape returns to the previous source.
- Surface: inline segmented control plus a popover (a few related choices tied to one control). Area uses a full-screen overlay because it has to be drawn on the display itself.
- States: a closed window falls back to "Choose a Window…" with an inline warning. An area smaller than 200×200 shows "Area is too small" next to the size readout. Long window titles truncate in the middle, with a tooltip.
- Words: segments "Display", "Window", "Area". Popover titles "Choose a Display", "Choose a Window". Area hint "Drag to select an area. Press Return to confirm, Escape to cancel." Size readout "1920 × 1080".
- Access: arrow keys move through thumbnails and Return picks. VoiceOver reads "Window, Safari: GitHub, 1 of 12". In area mode, arrow keys nudge by 1 pt and Shift-arrow by 10 pt.
Status: done

### S-004 Turn the microphone on or off and pick a device
As the user, I toggle the mic and choose which microphone to use, with a
level meter.
Screens: record-panel
Depends: S-002
Acceptance:
- [snap] The Mic toggle has a device menu and a live level meter when on.
- [self] With the mic off, no mic track is written.
- [self] If the device is unplugged, the panel falls back to the default
  device and says so.
UX:
- Flow: click the Mic toggle -> on, with a level meter -> the chevron opens a device menu -> pick a device. The toggle can be switched off at any time before recording.
- Surface: inline toggle with a menu (changes one value on screen).
- States: off is a slashed mic and "Mic off". No access shows "Allow Microphone…" inline. Device lost: "MacBook Pro Microphone (default)" with a small warning icon and the tooltip "Your USB mic was disconnected." A silent meter for 5 seconds shows the hint "No sound detected".
- Words: label "Mic", tooltip "Record your voice", menu header "Microphone".
- Access: Space toggles. VoiceOver reads "Microphone, on, MacBook Pro Microphone", and the meter is exposed as a level value.
Status: done
Note: unplugging a USB mic is not tried yet ([manual]); the fallback rule is unit-tested.

### S-005 Turn the camera on or off and pick a device
As the user, I toggle the camera and choose which camera to use.
Screens: record-panel
Depends: S-002
Acceptance:
- [snap] The Camera toggle has a device menu. Turning it on shows the
  camera bubble (S-011).
- [self] With the camera off, no camera track is written.
UX:
- Flow: click the Camera toggle -> the Camera Bubble appears on screen at once -> the chevron opens a device menu -> pick a camera.
- Surface: inline toggle with a menu (changes one value on screen).
- States: off is a slashed camera and "Camera off". No access shows "Allow Camera…" inline. Camera in use by another app: "Camera is in use by another app" inline.
- Words: label "Camera", tooltip "Show yourself in a Camera Bubble", menu header "Camera".
- Access: Space toggles. VoiceOver reads "Camera, on, FaceTime HD Camera".
Status: done
Note: the bubble is the basic live circle; dragging with snap, sizes, and shapes are M2.

### S-006 Turn system audio on or off
As the user, I choose whether sounds from my Mac are recorded.
Screens: record-panel
Depends: S-002
Acceptance:
- [self] When on, system audio is written to its own track, and Showreel's
  own sounds are excluded.
UX:
- Flow: click the System Audio toggle -> on or off.
- Surface: inline toggle (changes one value on screen).
- States: off by default, with a speaker-slash icon when off.
- Words: label "System Audio", tooltip "Record sounds your Mac plays".
- Access: Space toggles. VoiceOver reads "System Audio, off".
Status: done

### S-007 Start and stop a recording
As the user, I press Record, see a 3-second countdown, and later stop with
the Stop button in the Recording Controls or ⌃⌥⌘R.
Screens: countdown, recording-controls
Depends: S-003, S-004, S-005, S-006
Acceptance:
- [snap] The countdown is shown on the recorded display. The Recording Controls show the
  elapsed time, Pause, Stop, and Restart.
- [unit] A project folder holds `screen.mov` (cursor hidden), `camera.mov`,
  `mic.m4a`, `system.m4a`, and `events.json` (cursor moves at 60 Hz, plus
  clicks and key presses with timestamps).
- [unit] All tracks share one host-time clock and start within 1 frame of
  each other.
- [self] Pause and resume leave no gap or desync in any track.
- [manual] A 10-minute 4K/60 recording drops no frames on an M1.
UX:
- Flow: Start Recording or Return in the Record Panel -> the panel hides -> Countdown 3-2-1 on the recorded display (click or Escape cancels) -> recording -> Recording Controls float at the bottom of the screen (excluded from the capture) -> Stop, ⌃⌥⌘R, or the menu bar icon > Stop -> the project opens in its window.
- Surface: a full-screen Countdown overlay, then a floating panel for the Recording Controls (a tool kept open beside the work).
- States: paused shows the time blinking and "Paused". Low disk space (under 2 GB) shows an inline warning in the controls. A failed write stops the recording, keeps everything recorded so far, and shows the alert "Recording stopped because the disk is full. What was recorded up to 4:12 is saved."
- Words: "Pause", "Resume", "Stop", "Restart". Tooltips: "Stop and open the project (⌃⌥⌘R)", "Throw away this recording and start again". Restart sends the recording to the Trash without a dialog, and the Library's Undo restores it.
- Access: ⌃⌥⌘P pauses or resumes. VoiceOver reads "Recording, 1 minute 12 seconds". Reduce Motion fades the Countdown numbers instead of scaling them.
Status: done
Note: the self-test records real 2 s and 2.5 s clips with a pause; the 10-minute 4K/60 run is [manual].

### S-008 See my recordings in the library
As the user, I open the library window and see every project as a card
with a thumbnail, title, duration, and date, newest first.
Screens: library, library-empty
Depends: S-007
Acceptance:
- [snap] A grid of cards. When empty: "No recordings yet" and a New
  Recording button.
- [self] A new recording appears at the top as soon as it stops.
- [self] Projects survive a restart.
UX:
- Flow: menu bar icon > Open Library, the Dock icon, or ⌘0 -> Library window -> a grid of projects, newest first -> a new recording slides in at the top.
- Surface: new window (a place people come back to). One page in M1, with a toolbar holding New Recording and Search.
- States: empty shows a large icon, "No Recordings Yet", the line "Record your screen, voice, and camera. Showreel adds zooms and a frame for you.", and a "New Recording" button. A project still finishing its recording shows its card with a spinner and "Saving…". A missing file shows "Recording files are missing" with Show in Finder. Long titles wrap to two lines, then truncate with a tooltip.
- Words: window title "Library". Toolbar "New Recording" (⌘N). Card subtitle "0:42 · Today, 10:14".
- Access: arrow keys move the selection, Return opens, and type-to-select works. VoiceOver reads each card as "Onboarding walkthrough, 42 seconds, today".
Status: done

### S-009 Play back a recording
As the user, I double-click a project and play it back with mic and system
audio in sync.
Screens: editor (was player until S-015)
Depends: S-008
Acceptance:
- [snap] A player with play/pause, a scrubber, and the time. The camera is
  shown in its bubble position.
- [unit] Audio and video stay within 1 frame of each other over the full
  length.
UX:
- Flow: double-click a card, press Return, or right-click > Open -> the project opens in its own window (this window becomes the Editor in M3) -> Space plays -> ⌘W closes.
- Surface: new window (a self-contained task kept beside the Library).
- States: loading for more than half a second shows the first frame with a spinner. A missing camera track hides the bubble without an error.
- Words: window title is the project title. Tooltips "Play (Space)", "Pause (Space)".
- Access: Space plays and pauses, ←/→ step 1 second, J/K/L control playback speed. VoiceOver reads the scrubber as "Playhead, 0:12 of 0:42".
Status: done
Note: audio/video sync over a long recording is not measured yet ([unit] still to write).

### S-010 Rename, show in Finder, or move a project to the Trash
As the user, I right-click a project card to rename it, show its folder in
Finder, or move it to the Trash.
Screens: library
Depends: S-008
Acceptance:
- [snap] The context menu has Open, Rename, Show in Finder, Duplicate,
  and Move to Trash.
- [self] Move to Trash moves the folder to the Trash with no dialog, and
  ⌘Z restores it.
UX:
- Flow: right-click a card or press ⌘-click > Rename (or Return on a selected card): the title becomes editable inline, Return saves, and Escape cancels. Show in Finder (⌥⌘R). Duplicate (⌘D). Move to Trash (⌘⌫), which removes the card and offers Undo (⌘Z) right away.
- Surface: context menu, with Rename edited inline (changes one value on screen). No confirmation dialog, because Move to Trash can be undone.
- States: an empty title restores the previous one. Undo after Move to Trash puts the folder back in place.
- Words: "Open", "Rename", "Show in Finder", "Duplicate", "Move to Trash". Edit menu "Undo Move to Trash".
- Access: every item has a menu bar equivalent in the File menu with the same shortcut.
Status: done

---

## M2 Camera bubble
Done when you can drag, resize, and reshape the bubble while recording,
and the editor shows it exactly where it was.

### S-011 See myself in a camera bubble
As the user, with the camera on, I see a live round camera bubble on top
of every app.
Screens: camera-bubble
Depends: S-005
Acceptance:
- [snap] A circle with a soft shadow, mirrored, in the bottom-right corner
  by default.
- [unit] The bubble window is excluded from the screen capture. The camera
  is recorded only to `camera.mov`.
Status: done

### S-012 Drag the bubble to a new position
As the user, I drag the bubble anywhere. It snaps to corners and edges
when close.
Screens: camera-bubble
Depends: S-011
Acceptance:
- [self] Snapping happens within 24 pt of a corner or an edge midpoint.
- [unit] Each move during a recording is logged to `events.json` as a
  normalized position with a timestamp.
Status: done
Note: snapping and logging are self-tested; the drag feel needs a person to try ([manual]).

### S-013 Resize the bubble and change its shape
As the user, I pick Small, Medium, or Large and Circle or Rounded Square
from the bubble's hover controls.
Screens: camera-bubble
Depends: S-011
Acceptance:
- [snap] Hover controls show size and shape choices.
- [self] The choice is remembered for the next recording.
Status: done

### S-014 Hide the bubble for a moment during recording
As the user, I press ⌃⌥⌘C to hide or show the camera while recording.
Depends: S-011
Acceptance:
- [unit] Hide and show times are logged, and the editor hides the camera
  for those ranges.
Status: done

---

## M3 Editor shell
Done when you can open a recording, watch it, cut out mistakes, and undo.

### S-015 Open a project in the editor
As the user, I open a project and see the editor: the canvas in the
middle, the timeline at the bottom, and a trailing inspector with the
sections Background, Screen, Effects, Camera, Captions, and Audio
(docs/DESIGN.md, "Editor").
Screens: editor, reference-editor.png
Depends: S-009
Acceptance:
- [snap] The layout follows docs/DESIGN.md: the reference's regions, with
  the section rail moved into a native trailing inspector.
- [snap] The toolbar has Undo, Redo, an editable title, and Export.
Status: done
Note: snapshots `editor` and `editor-<section>`. Export is shown but disabled until S-036, and Split, Add Zoom, and the timeline zoom until their stories. Space, ←/→, and J/K/L (S-009's AVPlayerView keys) come back with the Playback menu in S-016.

### S-016 Play, pause, and scrub
As the user, I press Space to play or pause, drag the playhead, and use
the arrow keys to step frames.
Screens: editor
Depends: S-015
Acceptance:
- [snap] The transport shows "0:00.0 / 0:02.6".
- [self] Scrubbing updates the canvas within one frame on a 4K source.
Status: done
Note: the one-frame target is not met yet (median 24 ms on 3456×2234) and moved to S-047. The self-test guards 3 frames. Playback menu: Play/Pause (Space), Previous/Next Frame (←/→), Back/Forward 1 Second (⇧←/⇧→), Go to Start/End (Home/End). While a text field is edited, those keys go to the text.

### S-017 Zoom the timeline
As the user, I use the zoom slider, ⌘+ and ⌘−, or Fit to change the
timeline scale.
Screens: editor
Depends: S-015
Acceptance:
- [snap] The ruler labels adapt (seconds or tenths).
Status: done
Note: snapshots `editor` (fit, labels every 5 s) and `editor-zoomed` (tenths). Pinch zooms too. Zoomed in, the playhead is kept in view. Seed movies now run their full length (2 fps).

### S-018 Trim the start and end
As the user, I drag the clip's edges to trim it.
Screens: editor
Depends: S-016
Acceptance:
- [unit] A trim is stored as a non-destructive range. The source files are
  never changed.
- [snap] The trimmed part is dimmed while dragging, and the clip shows its
  new length.
Status: done
Note: the cut is an `EditList` (Kit) of source-time segments, stored as JSON in `Project.editsData`. Snapshot `editor-trim`. Clip > Trim Start/End to Playhead (⌥[ / ⌥]). Clicking a clip selects it and moves the playhead.

### S-019 Split and delete a section
As the user, I press S (or the scissors) to split at the playhead, select
a piece, and delete it.
Screens: editor
Depends: S-018
Acceptance:
- [unit] Deleting a section closes the gap, and zooms and captions after
  it shift with it.
Status: todo

### S-020 Undo and redo every edit
As the user, I press ⌘Z or ⇧⌘Z to undo or redo any edit in the editor.
Depends: S-015
Acceptance:
- [unit] Every inspector and timeline change is one undo step. A slider
  drag counts as one step.
Status: todo

### S-021 Edits save automatically
As the user, I close the editor and reopen it to find everything as I
left it.
Depends: S-015
Acceptance:
- [self] Edits are saved within 1 second, and survive a crash or restart.
Status: todo

---

## M4 Styling
Done when a raw recording becomes a framed, padded, styled shot like the
reference.

### S-022 Pick a background
As the user, I choose a gradient preset, a solid color, a macOS wallpaper,
or my own image, and an optional blur.
Screens: editor-background
Depends: S-015
Acceptance:
- [snap] A grid of 12 or more gradients, a color well, wallpapers, and
  "Choose Image…".
Status: todo

### S-023 Set padding and corner rounding
As the user, I drag the Padding (0–30%) and Rounding (0–40 px) sliders.
Screens: editor-screen
Depends: S-015
Acceptance:
- [snap] The canvas updates live, and each value is shown next to its
  slider.
Status: todo

### S-024 Add a shadow or glow
As the user, I pick Shadow or Glow and set its amount.
Screens: editor-screen
Depends: S-023
Acceptance:
- [snap] A segmented Shadow / Glow control and an Amount slider (0–100%).
Status: todo

### S-025 Crop the recording
As the user, I click Crop Screen and drag the handles to cut away the
edges.
Screens: crop-sheet
Depends: S-015
Acceptance:
- [snap] A crop sheet with handles, a size readout, and Reset, Cancel, and
  Done.
- [unit] Click positions and zoom focus points are remapped to the cropped
  frame.
Status: todo

### S-026 Add a device frame
As the user, I pick None, Border, Browser, or MacBook as the outline
around the recording.
Screens: editor-screen
Depends: S-023
Acceptance:
- [snap] Each frame renders crisply at 4K. Browser shows traffic lights
  and an optional URL bar.
Status: todo

### S-027 Choose the output aspect ratio
As the user, I choose 16:9, 9:16, 1:1, 4:3, or Auto for the canvas.
Screens: editor
Depends: S-022
Acceptance:
- [snap] The canvas reflows, and the recording keeps its padding.
Status: todo

### S-028 Style and place the camera in the editor
As the user, I show or hide the camera, drag it on the canvas, and set
its size, shape, border, and shadow.
Screens: editor-camera
Depends: S-015, S-012
Acceptance:
- [snap] The Camera section has a Show toggle, Size, Shape, Border, and
  Shadow controls.
- [self] Dragging the camera on the canvas overrides the recorded position
  for the whole video.
Status: todo

### S-029 Save a style as a preset
As the user, I save the current style as a preset and apply it to other
projects. One preset can be the default for new recordings.
Screens: editor-background
Depends: S-022, S-024, S-026
Acceptance:
- [self] Applying a preset is one undo step.
Status: todo

---

## M5 Auto-zoom and cursor
Done when a recording plays back with smooth zooms on every click, without
any manual work.

### S-030 Zooms are made automatically from clicks
As the user, I open a new recording and find zoom segments already
placed where I clicked.
Screens: editor
Depends: S-007, S-015
Acceptance:
- [unit] Clicks less than 2.5 seconds apart and within 30% of the screen
  are merged into one segment. Each segment is at least 1.5 seconds long.
  The default scale is 2×.
- [unit] Typing bursts make a zoom on the caret's area.
- [snap] Zoom segments show on the zoom track as purple blocks.
Status: todo

### S-031 Edit a zoom segment
As the user, I select a zoom and set its scale and its focus point (drag
on a mini preview) in the inspector.
Screens: editor-zoom-selected
Depends: S-030
Acceptance:
- [snap] The inspector shows Scale (1–4×), Focus (Auto / Follow cursor /
  Fixed point), and Delete.
Status: todo

### S-032 Add, move, resize, and delete zooms
As the user, I click an empty spot on the zoom track to add a zoom, drag
it to move it, drag its edges to resize it, and press Delete to remove it.
Screens: editor
Depends: S-030
Acceptance:
- [self] Zooms cannot overlap. Dragging one into another pushes it or
  stops at its edge.
Status: todo

### S-033 Smooth zoom motion
As the user, I set how fast zooms ease in and out (Slow, Medium, Fast).
Screens: editor-effects
Depends: S-030
Acceptance:
- [unit] The camera path uses a critically damped spring. There is no
  jitter when following the cursor.
- [manual] Zooms feel as smooth as Screen Studio.
Status: todo

### S-034 Smooth and resize the cursor
As the user, I set cursor size (1–3×) and smoothing, and hide the cursor
when it is idle.
Screens: editor-effects
Depends: S-015
Acceptance:
- [unit] The cursor is redrawn from `events.json` using the right system
  cursor shape (arrow, I-beam, pointer).
- [snap] A large smoothed cursor renders crisply at 4K.
Status: todo

### S-035 Show click effects
As the user, I turn on a click ripple and pick its style and color.
Screens: editor-effects
Depends: S-034
Acceptance:
- [snap] A ripple appears at each click for 400 ms.
Status: todo

---

## M6 Export
Done when the exported file looks exactly like the preview.

### S-036 Export a video
As the user, I click Export and choose the format (MP4, MOV, or GIF),
resolution (720p, 1080p, or 4K), fps (30 or 60), and quality.
Screens: export-sheet
Depends: S-015
Acceptance:
- [snap] The export sheet shows an estimated file size.
- [unit] The rendered frame at t=5 s matches the preview frame (SSIM >
  0.98).
Status: todo

### S-037 Watch export progress and cancel
As the user, I see a progress bar and time remaining while I keep
editing, and I can cancel.
Screens: export-progress
Depends: S-036
Acceptance:
- [self] Cancelling deletes the partial file.
- [manual] A 1-minute 1080p/60 export takes under 30 seconds on Apple
  silicon.
Status: todo

### S-038 Share or reveal the exported file
As the user, when the export finishes I click Share, Show in Finder, or
Copy.
Screens: export-progress
Depends: S-036
Acceptance:
- [snap] A finished state with three buttons. Share opens the macOS Share
  sheet.
Status: todo

---

## M7 Captions and audio
Done when captions are made, can be edited, and look good, and the voice
sounds clean.

### S-039 Make captions automatically
As the user, I click Generate Captions and get timed captions from the mic
track, on-device.
Screens: editor-captions
Depends: S-015
Acceptance:
- [unit] SpeechAnalyzer produces word-level timings, grouped into lines of
  up to 42 characters.
- [snap] Caption blocks show on the caption track.
Status: todo

### S-040 Edit caption text and timing
As the user, I double-click a caption to fix its text and drag its edges
to change its timing.
Screens: editor-captions
Depends: S-039
Acceptance:
- [self] Edits are undoable, and captions shift with cuts (S-019).
Status: todo

### S-041 Style captions
As the user, I set the caption font size, position (bottom or top), and
background, and highlight the word being spoken.
Screens: editor-captions
Depends: S-039
Acceptance:
- [snap] Captions render in the preview and in the export the same way.
Status: todo

### S-042 Set track volumes and mute sections
As the user, I set the mic and system audio volume and mute a selected
range.
Screens: editor-audio
Depends: S-015
Acceptance:
- [snap] Waveforms show on the audio track.
Status: todo

### S-043 Reduce background noise
As the user, I turn on Noise Reduction for the mic.
Screens: editor-audio
Depends: S-042
Acceptance:
- [manual] Fan hum is clearly reduced, and the voice does not sound
  robotic.
Status: todo

---

## M8 Polish

### S-044 Every action has a menu command and a shortcut
Depends: S-015
Acceptance:
- [snap] The Edit, View, Clip, and Playback menus list every editor action
  with its shortcut.
Status: todo

### S-045 Settings
As the user, I set the save location, record shortcut, countdown length,
default style preset, and default export settings.
Screens: settings
Acceptance:
- [snap] A native Settings window with the tabs General, Recording, and
  Export.
Status: todo

### S-046 App icon
Acceptance:
- [snap] A Liquid Glass icon in the Dock, the library, and About.
Status: todo

### S-047 Smooth preview on big recordings
Acceptance:
- [manual] A 4K/60 project plays in the editor at 60 fps with zooms and
  the camera on, on an M1.
- [self] Scrubbing updates the canvas within one frame on a 4K source
  (moved from S-016). Measured at S-016 on a 3456×2234 recording: median
  24 ms, worst 67 ms, with exact AVPlayer seeks. Capping the preview render
  size made no difference, so the time is in decoding and seeking, not
  compositing.
Status: todo

---

## Later
- Blur regions on the timeline ("Add blur")
- Speed changes for a section (1.5×, 2×, skip silence)
- Multiple clips per project, intro and outro cards
- Background music track
- Recording an iPhone or iPad over USB
- Editing by transcript (delete words to cut video)
- iCloud sync of projects

## Dropped
- Cloud upload and share links: needs a server and accounts, and the
  Share sheet covers it.
- Accounts, teams, and workspaces: a single-user app.
- "Uploading 62%" status in the toolbar: no cloud.
- Avatar and profile menu: no accounts.
- Analytics and upgrade prompts: none.
