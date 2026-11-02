import AppKit
import SwiftData
import ShowreelKit

extension Snapshot {
    /// The Editor, once per inspector section: "editor" shows Background,
    /// "editor-<section>" the others.
    static func editorSurfaces(model: AppModel) -> [Surface] {
        let title = SeedData.samples.first?.title
        let window = { NSApp.windows.first { $0.title == title && $0.isVisible } }
        /// Opens the first sample in the Editor if no snapshot page did yet.
        let openEditor: () async -> EditorModel? = {
            let project = (try? model.context.fetch(FetchDescriptor<Project>()))?.first { $0.title == title }
            if let project, window() == nil { AppServices.shared.openProject(project.uuid) }
            for _ in 0..<30 where EditorModel.newest?.player == nil { try? await Task.sleep(for: .seconds(0.1)) }
            return EditorModel.newest
        }
        let zoomed = Surface(name: "editor-zoomed", show: {
                                 let project = (try? model.context.fetch(FetchDescriptor<Project>()))?.first { $0.title == title }
                                 if let project, window() == nil { AppServices.shared.openProject(project.uuid) }
                                 for _ in 0..<20 where EditorModel.newest == nil { try? await Task.sleep(for: .seconds(0.1)) }
                                 EditorModel.newest?.section = .background
                                 EditorModel.newest?.seek(to: 12.3)
                                 EditorModel.newest?.zoom = TimelineZoom(level: 0.9)
                             },
                             window: window,
                             hide: { window()?.close() })
        // S-035: a ripple 0.15 s after the first click, shown without saving.
        let click = Surface(name: "editor-click", show: {
                                guard let editor = await openEditor() else { return }
                                editor.zoom = TimelineZoom()
                                editor.section = .effects
                                var style = editor.style
                                style.clickEffect = .ripple
                                editor.previewStyle(style)
                                editor.seek(to: 4.35)
                            },
                            window: window,
                            hide: {
                                guard let editor = EditorModel.newest else { return }
                                var style = editor.style
                                style.clickEffect = .none
                                editor.previewStyle(style)
                            })
        // S-031: the zoom around 0:12 selected, the playhead inside it.
        let zoomSelected = Surface(name: "editor-zoom-selected", show: {
                                       guard let editor = await openEditor() else { return }
                                       editor.zoom = TimelineZoom()
                                       editor.section = .background
                                       let zoom = editor.zooms.segment(at: 12.6)
                                       editor.selectZoom(zoom?.id)
                                       editor.seek(to: 12.6)
                                       // The focus preview loads its frame.
                                       try? await Task.sleep(for: .seconds(0.5))
                                   },
                                   window: window,
                                   hide: { EditorModel.newest?.selectZoom(nil) })
        // S-048, S-049: the seeded blur selected, its rectangle on the canvas.
        let blurSelected = Surface(name: "editor-blur-selected", show: {
                                       guard let editor = await openEditor() else { return }
                                       editor.zoom = TimelineZoom()
                                       editor.section = .background
                                       editor.selectBlur(editor.blurs.region(at: 6)?.id)
                                       editor.seek(to: 6)
                                       await editor.seeksSettled()
                                   },
                                   window: window,
                                   hide: { EditorModel.newest?.selectBlur(nil) })
        // S-018: the start being trimmed by 6 s, mid-drag.
        let trim = Surface(name: "editor-trim", show: {
                               let project = (try? model.context.fetch(FetchDescriptor<Project>()))?.first { $0.title == title }
                               if let project, window() == nil { AppServices.shared.openProject(project.uuid) }
                               for _ in 0..<20 where EditorModel.newest?.player == nil { try? await Task.sleep(for: .seconds(0.1)) }
                               guard let editor = EditorModel.newest, let first = editor.edits.segments.first else { return }
                               editor.zoom = TimelineZoom()
                               editor.section = .background
                               editor.selectedSegment = first.id
                               editor.previewTrim(first.id, edge: .start, by: 6)
                           },
                           window: window,
                           hide: {})
        // S-019: split twice, the middle piece selected.
        let split = Surface(name: "editor-split", show: {
                                guard let editor = await openEditor() else { return }
                                editor.section = .background
                                editor.selectedSegment = nil
                                editor.apply(EditList(sourceDuration: editor.edits.sourceDuration))
                                editor.seek(to: 12)
                                editor.splitAtPlayhead()
                                editor.seek(to: 24)
                                editor.splitAtPlayhead()
                                editor.selectedSegment = editor.edits.segments[1].id
                            },
                            window: window,
                            hide: {})
        // S-025: Crop Screen with a crop set, so the handles and dimming show.
        let crop = Surface(name: "crop-sheet", show: {
                               guard let editor = await openEditor() else { return }
                               var style = editor.style
                               style.crop = CropRect(x: 0.1, y: 0.12, width: 0.75, height: 0.7) // grid: ok normalized crop
                               editor.applyStyle(style, named: "Crop")
                               editor.showsCropSheet = true
                           },
                           window: { window()?.attachedSheet },
                           hide: {
                               guard let editor = EditorModel.newest else { return }
                               editor.showsCropSheet = false
                               var style = editor.style
                               style.crop = .full
                               editor.applyStyle(style, named: "Crop")
                           })
        // S-026: the Browser frame with an address, in Inspector > Screen.
        let frame = Surface(name: "editor-frame", show: {
                                guard let editor = await openEditor() else { return }
                                editor.section = .screen
                                var style = editor.style
                                style.frame = .browser
                                style.url = "showreel.app/pricing"
                                editor.applyStyle(style, named: "Frame")
                            },
                            window: window,
                            hide: {
                                guard let editor = EditorModel.newest else { return }
                                var style = editor.style
                                style.frame = .none
                                style.url = ""
                                editor.applyStyle(style, named: "Frame")
                            })
        // S-027: a 9:16 canvas, from Inspector > Background.
        let aspect = Surface(name: "editor-aspect", show: {
                                 guard let editor = await openEditor() else { return }
                                 editor.section = .background
                                 var style = editor.style
                                 style.aspect = .tall
                                 editor.applyStyle(style, named: "Aspect Ratio")
                             },
                             window: window,
                             hide: {
                                 guard let editor = EditorModel.newest else { return }
                                 var style = editor.style
                                 style.aspect = .auto
                                 editor.applyStyle(style, named: "Aspect Ratio")
                             })
        // S-029: Save Style as Preset.
        let savePreset = Surface(name: "save-preset", show: {
                                     guard let editor = await openEditor() else { return }
                                     editor.section = .background
                                     editor.showsSavePreset = true
                                 },
                                 window: { window()?.attachedSheet },
                                 hide: { EditorModel.newest?.showsSavePreset = false })
        // S-036: the Export sheet with the default choices and the size estimate.
        let export = Surface(name: "export-sheet", show: {
                                 guard let editor = await openEditor() else { return }
                                 editor.section = .background
                                 editor.showExportSheet()
                             },
                             window: { window()?.attachedSheet },
                             hide: { EditorModel.newest?.showsExportSheet = false })
        // S-037: an export 40% done after 10 s, in its popover.
        let progress = Surface(name: "export-progress", show: {
                                   guard let editor = await openEditor() else { return }
                                   editor.export = .shown(for: editor, fraction: 0.4, elapsed: 10)
                                   try? await Task.sleep(for: .seconds(0.3))
                                   editor.showsExportPopover = true
                               },
                               window: { NSApp.windows.first { $0.className.contains("Popover") && $0.isVisible } },
                               hide: {
                                   EditorModel.newest?.showsExportPopover = false
                                   EditorModel.newest?.export = nil
                               })
        // S-039: Generate Captions running, and with no speech found.
        let captionJob = { (name: String, state: CaptionJob.State) in
            Surface(name: name, show: {
                        guard let editor = await openEditor() else { return }
                        editor.section = .captions
                        editor.captionJob = .shown(state)
                    },
                    window: window,
                    hide: { EditorModel.newest?.captionJob = nil })
        }
        let captionsProgress = captionJob("editor-captions-progress", .running(.listening(0.35)))
        let captionsFailed = captionJob("editor-captions-failed", .failed("No speech found in the microphone recording."))
        // S-040: the second caption selected, its text being edited.
        let captionSelected = Surface(name: "editor-caption-selected", show: {
                                          guard let editor = await openEditor() else { return }
                                          editor.zoom = TimelineZoom()
                                          let caption = editor.captions.captions.dropFirst().first
                                          editor.selectCaption(caption?.id, editText: true)
                                          editor.seek(to: caption?.start ?? 0)
                                      },
                                      window: window,
                                      hide: { EditorModel.newest?.selectCaption(nil) })
        // S-054: Arabic captions with English words, one selected, shown without saving.
        var arabicOriginal: CaptionTrack?
        let captionsArabic = Surface(name: "editor-captions-arabic", show: {
                                         guard let editor = await openEditor() else { return }
                                         editor.zoom = TimelineZoom()
                                         arabicOriginal = editor.captions
                                         let lines = ["أهلاً بيكم، النهارده هنشرح الـ dashboard.",
                                                      "هنعمل login وبعدين نفتح الـ settings.",
                                                      "وناخد الـ API key ونحطه في المشروع."]
                                         var at = 1.0
                                         let captions = lines.map { line -> Caption in
                                             let words = line.split(separator: " ").map { w -> CaptionWord in
                                                 defer { at += 0.45 }
                                                 return CaptionWord(text: String(w), start: at, end: at + 0.4)
                                             }
                                             at += 0.8
                                             return Caption(words: words)
                                         }
                                         editor.previewCaptions(CaptionTrack(captions: captions, language: "ar"))
                                         let caption = editor.captions.captions[1]
                                         editor.selectCaption(caption.id)
                                         editor.seek(to: caption.words[3].start + 0.1)
                                         await editor.seeksSettled()
                                     },
                                     window: window,
                                     hide: {
                                         EditorModel.newest?.selectCaption(nil)
                                         if let arabicOriginal { EditorModel.newest?.previewCaptions(arabicOriginal) }
                                     })
        // S-022: the wallpapers on this Mac, with a video wallpaper's first frame as the background.
        var wallpaperOriginal: Style?
        let wallpapers = Surface(name: "editor-wallpapers", show: {
                                     guard let editor = await openEditor() else { return }
                                     editor.section = .background
                                     wallpaperOriginal = editor.style
                                     if let movie = Wallpaper.available().first(where: { $0.url.pathExtension == "mov" }) {
                                         var style = editor.style
                                         style.background = .wallpaper(movie.url.path)
                                         editor.previewStyle(style)
                                     }
                                     try? await Task.sleep(for: .seconds(1.5))
                                     // Scroll the inspector to its Wallpaper section.
                                     if let window = NSApp.windows.first(where: { $0.isVisible && $0.title == title }) {
                                         scrollInspector(in: window.contentView, toward: 0.62)
                                     }
                                     try? await Task.sleep(for: .seconds(1))
                                 },
                                 window: window,
                                 hide: { if let wallpaperOriginal { EditorModel.newest?.previewStyle(wallpaperOriginal) } })
        // Blends: Aurora on the canvas, the Blend section in view.
        var blendOriginal: Style?
        let blend = Surface(name: "editor-blend", show: {
                                guard let editor = await openEditor() else { return }
                                editor.section = .background
                                blendOriginal = editor.style
                                var style = editor.style
                                style.background = .blend("aurora")
                                style.padding = 0.12
                                editor.previewStyle(style)
                                try? await Task.sleep(for: .seconds(1))
                                if let window = NSApp.windows.first(where: { $0.isVisible && $0.title == title }) {
                                    scrollInspector(in: window.contentView, toward: 0.22)
                                }
                                try? await Task.sleep(for: .seconds(0.8))
                            },
                            window: window,
                            hide: { if let blendOriginal { EditorModel.newest?.previewStyle(blendOriginal) } })
        // S-042: a muted part on the audio track, shown without saving.
        let audioMuted = Surface(name: "editor-audio-muted", show: {
                                     guard let editor = await openEditor() else { return }
                                     editor.zoom = TimelineZoom()
                                     editor.section = .audio
                                     var mix = AudioMix(microphone: 1.3)
                                     mix.mute(from: 9, to: 12.5)
                                     editor.previewAudio(mix)
                                 },
                                 window: window,
                                 hide: { EditorModel.newest?.previewAudio(AudioMix()) })
        // S-043: Reduce Noise making the clean mic the first time.
        let noiseProgress = Surface(name: "editor-audio-noise", show: {
                                        guard let editor = await openEditor() else { return }
                                        editor.section = .audio
                                        editor.noiseJob = .shown(fraction: 0.45)
                                    },
                                    window: window,
                                    hide: { EditorModel.newest?.noiseJob = nil })
        // S-038: the finished export, with Share…, Show in Finder, and Copy.
        let done = Surface(name: "export-done", show: {
                               guard let editor = await openEditor() else { return }
                               editor.export = .shown(for: editor, fraction: 1, elapsed: 18, state: .finished, bytes: 47_600_000)
                               try? await Task.sleep(for: .seconds(0.3))
                               editor.showsExportPopover = true
                           },
                           window: { NSApp.windows.first { $0.className.contains("Popover") && $0.isVisible } },
                           hide: {
                               EditorModel.newest?.showsExportPopover = false
                               EditorModel.newest?.export = nil
                           })
        return InspectorSection.allCases.map { section in
            Surface(name: section == .background ? "editor" : "editor-\(section.rawValue)", show: {
                        let project = (try? model.context.fetch(FetchDescriptor<Project>()))?.first { $0.title == title }
                        if let project, window() == nil { AppServices.shared.openProject(project.uuid) }
                        for _ in 0..<20 where EditorModel.newest == nil { try? await Task.sleep(for: .seconds(0.1)) }
                        EditorModel.newest?.section = section
                    },
                    window: window,
                    hide: {})
        } + [trim, split, crop, frame, aspect, savePreset, export, progress, done, zoomSelected, blurSelected, wallpapers, blend, click, zoomed, captionsProgress, captionsFailed, captionSelected, captionsArabic, audioMuted, noiseProgress]
    }
}

/// Scrolls the inspector's form (the trailing scroll view) to `fraction` of
/// its height, for snapshot pages of what is below the fold.
@MainActor
func scrollInspector(in view: NSView?, toward fraction: CGFloat) {
    guard let view, let window = view.window else { return }
    var views = [view]
    while let next = views.popLast() {
        if let scroll = next as? NSScrollView, let document = scroll.documentView,
           next.convert(next.bounds, to: nil).minX > window.frame.width * 0.7 {
            let room = max(document.frame.height - scroll.contentView.bounds.height, 0)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: room * fraction))
            scroll.reflectScrolledClipView(scroll.contentView)
            return
        }
        views += next.subviews
    }
}

