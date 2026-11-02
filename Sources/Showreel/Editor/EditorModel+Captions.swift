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
    var canGenerateCaptions: Bool { project.hasMicrophone && player != nil && captionJob?.isRunning != true }

    /// Clip > Generate Captions, or the inspector's button. Replaces the
    /// captions as one undo step when it ends. `audio` is the mic track
    /// unless a test passes its own file.
    @discardableResult
    func generateCaptions(from audio: URL? = nil) -> CaptionJob? {
        guard captionJob?.isRunning != true else { return captionJob }
        let url = audio ?? ProjectStore.file(ProjectFiles.microphone, of: project.uuid)
        let job = CaptionJob()
        captionJob = job
        section = .captions
        job.task = Task { [weak self, weak job] in
            do {
                let (words, language) = try await Transcriber.words(in: url) { phase in
                    Task { @MainActor in if job?.isRunning == true { job?.set(.running(phase)) } }
                }
                try Task.checkCancellation()
                let lines = CaptionTrack.lines(from: words)
                guard !lines.isEmpty else {
                    job?.set(.failed("No speech found in the microphone recording."))
                    return
                }
                self?.applyCaptions(CaptionTrack(captions: lines, language: language.identifier), named: "Generate Captions")
                if self?.captionJob === job { self?.captionJob = nil }
            } catch is CancellationError {
                if self?.captionJob === job { self?.captionJob = nil }
            } catch Transcriber.Failure.unsupportedLanguage(let locale) {
                job?.set(.failed("Captions aren’t available in \(Self.languageName(locale.identifier)) yet."))
            } catch Transcriber.Failure.unreadable {
                job?.set(.failed("Unable to read the microphone recording."))
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
        guard new != captions else { return }
        let old = captions
        undoManager?.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated { editor.applyCaptions(old, named: name) }
        }
        undoManager?.setActionName(name)
        captions = new
        project.captionsData = new.captions.isEmpty && new.language.isEmpty ? nil : new.encoded()
        try? project.modelContext?.save()
        refreshUndo()
    }

    /// "English (United States)" for "en_US".
    static func languageName(_ identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}
