# Architecture review, 2026-11-02 (end of M8, commit da48880)

14,440 lines. The largest files are `RecordController` (463), `EditorModel` (371), `SelfTest+Editor`
(344), `Zoom` (317), and `EditorTracks` (308); nothing is near 600. `Snapshot.swift` went from
419 to 205 lines when the editor surfaces moved out (first M8 commit), and the menu
snapshots live in `Snapshot+Menus.swift`. M8 added `Settings/` (`AppSettings`, the tabs,
`ShortcutField`), `ExportChoices` (shared by the Export sheet and Settings > Export), and
`HotKeys.replaceRecord`. Two fix-log entries: a self-test that broke on clicks during the
Countdown (test harness), and an export-cancel crash (an AVAssetReader cancelled across threads).
The two are in unrelated areas.

## One home for app settings  [Worth exploring]

Files: Recording/RecordController.swift, Recording/Devices.swift, Recording/BubbleControls.swift,
Recording/WelcomeView.swift, Library/LibraryView.swift, Models.swift, UI/Theme.swift,
Settings/AppSettings.swift, and five self-test files.
Signal: one setting spread over many files. Eleven `Store.defaults` keys are string literals in
the types that use them; `"welcome.done"` is written in 3 app files and 6 self-test lines.
Problem: a typo in a key reads the default with no error, and the self-test has to know each
key's spelling to put it back. S-045 made `AppSettings` the home for the new settings, but the
older ones stayed where they were.
Proposal: every key moves into `AppSettings` as a typed property; the callers read and write
the property:
```swift
@Observable final class AppSettings {
    var welcomeDone: Bool          // "welcome.done"
    var recordSource: SourceKind   // "record.source"
    var micOn, cameraOn, systemAudioOn: Bool
    var microphoneID, cameraID: String?
    var displayID: CGDirectDisplayID?
    var bubbleSize: Int; var bubbleShape: BubbleShape
    // accent and settings tab stay with ThemeStore and AppModel, read through here
}
```
Benefits: one file lists everything Showreel remembers; the self-test saves and restores
`AppSettings` values instead of raw keys.
Proof of same behavior: the stored keys keep their names (existing settings still load); the
self-test's 195 checks; a launch with a filled `Store.defaults` domain shows the same Record Panel.
Plan: three commits: the recording keys, then welcome and bubble, then the self-test.

## RecordController size  [Speculative]

463 lines, every recording state in one type. It is the next file to cross 600. When the next
recorder feature lands (iPhone over USB is in Later), split the writers' setup
(`prepareAndCountDown`) into a `RecordingSession` value that owns the writers and the capture.

## Open-editor registry  [Worth exploring, carried over]

Still no fourth caller. Revisit when a Library command needs an editor.

## Considered, not recommended

- **Live menus in snapshots**: an app that is not active cannot open an NSMenu, and a
  snapshot run must not take the front, so the menus are drawn from the real items
  (`Snapshot+Menus`). The self-test checks the items' shortcuts and states.
- **ExportChoices in ShowreelKit**: it is SwiftUI; the rules it shows (`resolutions`,
  `frameRates`, `with(format:)`) are already in Kit with tests.
- **Moving the self-test and snapshot code out of the app target**: they drive the real
  windows and panels, which only exist in the app.

## Top recommendation

One home for app settings (Worth exploring). The loop ran unattended, so nothing was changed
in this check-in; it waits for the user.
