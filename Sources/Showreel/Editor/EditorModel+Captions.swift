import Foundation
import Observation
import ShowreelEngine
import ShowreelKit

/// Generate Captions while it runs, or the reason it stopped (S-039).
@Observable
final class CaptionJob {
    enum State: Equatable {
        case running(Transcriber.Phase)
        case failed(String)
    }

    private(set) var state: State = .running(.listening(0))
    @ObservationIgnored fileprivate var task: Task<Void, Never>?

    var isRunning: Bool { if case .running = state { true } else { false } }

    /// Words for the progress row, and the bar's fraction.
    var progress: (text: String, fraction: Double)? {
        switch state {
        case .running(.downloading(let f)): ("Downloading the speech model…", f)
        case .running(.listening(let f)): ("Making captions from your voice…", f)
        case .failed: nil
        }
    }

    var failure: String? { if case .failed(let text) = state { text } else { nil } }

    func cancel() { task?.cancel() }

    /// Waits until it ends. For the self-test.
    func finished() async { await task?.value }

    fileprivate func set(_ state: State) { self.state = state }

    /// A job frozen in `state`, for snapshot pages.
    static func shown(_ state: State) -> CaptionJob {
        let job = CaptionJob()
        job.state = state
        return job
    }
}

/// Captions (M7): made from the mic track, one undo step, saved at once.
extension EditorModel {
    var canGenerateCaptions: Bool {
        project.hasMicrophone && player != nil && captionJob?.isRunning != true && speechModelIsReady
    }

    /// The chosen speech model is on this Mac (S-050).
    var speechModelIsReady: Bool { SpeechModels.shared.availability(of: SpeechModels.shared.model).isReady }

    /// Clip > Generate Captions, or the inspector's button. Replaces the
    /// captions as one undo step when it ends. `audio` is the mic track
    /// unless a test passes its own file.
    @discardableResult
    func generateCaptions(from audio: URL? = nil) -> CaptionJob? {
        guard captionJob?.isRunning != true else { return captionJob }
        // With Reduce Noise on, captions are made from the clean voice.
        let url = audio ?? (self.audio.reducesNoise && sources?.cleanMicrophone != nil
            ? cleanMicrophoneURL : ProjectStore.file(ProjectFiles.microphone, of: project.uuid))
        let job = CaptionJob()
        captionJob = job
        section = .captions
        // The model and language from Settings > Captions or the inspector (S-050).
        let models = SpeechModels.shared
        let model = models.model, chosenLanguage = models.language, appleLocale = models.appleLocale
        let file = models.availability(of: model).url
        job.task = Task { [weak self, weak job] in
            do {
                let report: @Sendable (Transcriber.Phase) -> Void = { phase in
                    Task { @MainActor in if job?.isRunning == true { job?.set(.running(phase)) } }
                }
                let words: [CaptionWord], language: String
                if model.isWhisper {
                    guard let file else {
                        job?.set(.failed("Download \(model.title) in Settings > Captions."))
                        return
                    }
                    (words, language) = try await WhisperTranscriber.words(in: url, model: file, language: chosenLanguage, progress: report)
                } else {
                    let (heard, locale) = try await Transcriber.words(in: url, locale: appleLocale, progress: report)
                    (words, language) = (heard, locale.identifier)
                }
                try Task.checkCancellation()
                let lines = CaptionTrack.lines(from: words)
                guard !lines.isEmpty else {
                    job?.set(.failed("No speech found in the microphone recording."))
                    return
                }
                self?.applyCaptions(CaptionTrack(captions: lines, language: language), named: "Generate Captions")
                if self?.captionJob === job { self?.captionJob = nil }
            } catch is CancellationError {
                if self?.captionJob === job { self?.captionJob = nil }
            } catch Transcriber.Failure.unsupportedLanguage(let locale) {
                job?.set(.failed("Captions aren’t available in \(Self.languageName(locale.identifier)) yet."))
            } catch Transcriber.Failure.unreadable, WhisperTranscriber.Failure.unreadable {
                job?.set(.failed("Unable to read the microphone recording."))
            } catch WhisperTranscriber.Failure.modelUnreadable {
                job?.set(.failed("\(model.title) could not be opened. Download it again in Settings > Captions."))
            } catch {
                // A cancel can surface as the analyzer's own error.
                if Task.isCancelled {
                    if self?.captionJob === job { self?.captionJob = nil }
                } else {
                    job?.set(.failed("Unable to make captions. \(error.localizedDescription)"))
                }
            }
        }
        return job
    }

    /// Replaces the captions as one undoable step called `name`, and saves them.
    func applyCaptions(_ new: CaptionTrack, named name: String) {
        commitCaptions(from: captions, to: new, named: name)
    }

    /// Shows `new` on the timeline without an undo step or a save, while dragging.
    func previewCaptions(_ new: CaptionTrack) {
        guard new != captions else { return }
        captions = new
        redraw()
    }

    /// Ends a drag that started at `old`: one undo step for the whole drag.
    func commitCaptions(from old: CaptionTrack, named name: String) {
        commitCaptions(from: old, to: captions, named: name)
    }

    private func commitCaptions(from old: CaptionTrack, to new: CaptionTrack, named name: String) {
        commitPart(from: old, to: new, named: name, current: { $0.captions }) { editor, captions in
            editor.captions = captions
            editor.project.captionsData = captions.captions.isEmpty && captions.language.isEmpty ? nil : captions.encoded()
            if let id = editor.selectedCaption, !captions.captions.contains(where: { $0.id == id }) { editor.selectedCaption = nil }
        }
    }

    // MARK: Editing one caption (S-040)

    /// The selected caption, shown in the inspector in place of the section.
    var selectedCaptionItem: Caption? {
        selectedCaption.flatMap { id in captions.captions.first { $0.id == id } }
    }

    /// Selects a caption, or with nil, goes back to the inspector's section.
    /// With `editText`, the inspector puts the cursor in its text.
    func selectCaption(_ id: Caption.ID?, editText: Bool = false) {
        selectedCaption = id
        if id != nil {
            selectedZoom = nil
            selectedSegment = nil
            selectedBlur = nil
            section = .captions
        }
        editsCaptionText = id != nil && editText
    }

    /// Applies new text to the caption `id`. Empty text is not applied.
    func setText(_ text: String, ofCaption id: Caption.ID) {
        guard let caption = captions.captions.first(where: { $0.id == id }),
              let edited = caption.withText(text), edited.text != caption.text else { return }
        applyCaptions(captions.changing(id) { _ in edited }, named: "Edit Caption")
    }

    /// Clip > Delete Caption (⌫, the inspector's button, or the block's menu).
    func deleteSelectedCaption() {
        guard let id = selectedCaption else { return }
        applyCaptions(captions.changing(id) { _ in nil }, named: "Delete Caption")
        selectedCaption = nil
    }

    /// The caption's start in the edited video, or nil when the cut removed it.
    func editStart(of caption: Caption) -> Double? {
        edits.editRanges(fromSource: caption.start, to: caption.end).first?.lowerBound
    }

    /// "English (United States)" for "en_US".
    static func languageName(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}
