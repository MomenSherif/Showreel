import Foundation
import Observation
import Speech
import ShowreelKit

/// The speech models on this Mac and their downloads (S-050, S-051). One
/// store for the app, so Settings and every editor show the same progress.
@MainActor
@Observable
final class SpeechModels {
    static let shared = SpeechModels()

    private enum Key {
        static let model = "captions.model"
        static let language = "captions.language"
    }

    var locator = ModelLocator.standard {
        didSet { refresh() }
    }

    /// The model Generate Captions uses.
    var model = SpeechModel(rawValue: Store.defaults.string(forKey: Key.model) ?? "") ?? .standard {
        didSet {
            Store.defaults.set(model.rawValue, forKey: Key.model)
            language = CaptionLanguage.resolved(language, for: model, appleLocales: appleLocales)
        }
    }

    /// "auto" or a language code, from the chosen model's list.
    var language = Store.defaults.string(forKey: Key.language) ?? CaptionLanguage.automatic {
        didSet { Store.defaults.set(language, forKey: Key.language) }
    }

    /// Apple's languages, as locale identifiers, loaded once.
    private(set) var appleLocales: [String] = []
    /// Where each model is; refreshed after a download or a delete.
    private(set) var availability: [SpeechModel: ModelAvailability] = [:]
    /// Downloads running now, 0...1.
    private(set) var downloads: [SpeechModel: Double] = [:]
    /// The last download that failed, and why.
    private(set) var failures: [SpeechModel: String] = [:]
    @ObservationIgnored private var tasks: [SpeechModel: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var watches: [SpeechModel: NSKeyValueObservation] = [:]

    private init() {
        refresh()
        Task {
            appleLocales = await SpeechTranscriber.supportedLocales.map(\.identifier).sorted()
            language = CaptionLanguage.resolved(language, for: model, appleLocales: appleLocales)
        }
    }

    func refresh() {
        availability = Dictionary(uniqueKeysWithValues: SpeechModel.allCases.map { ($0, locator.availability(of: $0)) })
    }

    func availability(of model: SpeechModel) -> ModelAvailability { availability[model] ?? .missing }

    /// The languages the chosen model offers, as codes.
    var languages: [String] { CaptionLanguage.codes(for: model, appleLocales: appleLocales) }

    /// The locale Apple's model listens in for `language`.
    var appleLocale: Locale {
        let code = language == CaptionLanguage.automatic ? (Locale.current.language.languageCode?.identifier ?? "en") : language
        if let current = Locale.current.region?.identifier, appleLocales.contains("\(code)_\(current)") {
            return Locale(identifier: "\(code)_\(current)")
        }
        return Locale(identifier: appleLocales.first { $0.hasPrefix(code + "_") } ?? code)
    }

    // MARK: Downloads (S-051)

    /// Downloads `model` to Showreel's Models folder. The file is checked
    /// by size; a cancelled or broken download leaves nothing behind.
    /// `source` replaces the model's URL in the self-test.
    func download(_ model: SpeechModel, from source: URL? = nil) {
        guard let url = source ?? model.downloadURL, let destination = locator.destination(of: model), tasks[model] == nil else { return }
        failures[model] = nil
        downloads[model] = 0
        let task = URLSession.shared.downloadTask(with: url) { [weak self] temp, response, error in
            // The temporary file is gone when this returns: move it first.
            var moved: URL?
            if let temp, error == nil {
                let keep = destination.deletingLastPathComponent().appending(path: ".\(destination.lastPathComponent).part")
                try? FileManager.default.createDirectory(at: keep.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: keep)
                if (try? FileManager.default.moveItem(at: temp, to: keep)) != nil { moved = keep }
            }
            let failure = (error as? URLError)?.code == .cancelled ? nil : error?.localizedDescription
            Task { @MainActor in self?.finish(model, file: moved, at: destination, failure: failure) }
        }
        watches[model] = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in if self?.downloads[model] != nil { self?.downloads[model] = fraction } }
        }
        tasks[model] = task
        task.resume()
    }

    func cancelDownload(_ model: SpeechModel) {
        tasks[model]?.cancel()
    }

    /// Waits until no download runs. For the self-test.
    func downloadsFinished() async {
        for _ in 0..<600 where !tasks.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
    }

    private func finish(_ model: SpeechModel, file: URL?, at destination: URL, failure: String?) {
        tasks[model] = nil
        watches[model] = nil
        downloads[model] = nil
        defer { refresh() }
        guard let file else {
            if let failure { failures[model] = failure }
            return
        }
        let size = ((try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber)?.int64Value
        guard size == model.byteCount else {
            try? FileManager.default.removeItem(at: file)
            failures[model] = "The download was incomplete. Try again."
            return
        }
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: file, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: file)
            failures[model] = error.localizedDescription
        }
    }

    /// Deletes a downloaded model. Handy's copy is never touched.
    func delete(_ model: SpeechModel) {
        guard case .downloaded(let url) = availability(of: model) else { return }
        try? FileManager.default.removeItem(at: url)
        refresh()
    }
}
