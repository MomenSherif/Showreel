import Foundation

/// The on-device model that turns a voice into captions (docs/GLOSSARY.md,
/// "Speech Model", S-050). Apple's is built in; Whisper models are files,
/// downloaded once or read from the Handy app's folder (S-051).
public enum SpeechModel: String, CaseIterable, Codable, Sendable, Identifiable {
    case apple
    case whisperSmall
    case whisperTurbo

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .apple: "Apple"
        case .whisperSmall: "Whisper Small"
        case .whisperTurbo: "Whisper Large v3 Turbo"
        }
    }

    /// One line on what it is good for, under its name in Settings.
    public var summary: String {
        switch self {
        case .apple: "Fast, built into macOS. English, Spanish, French, German, Japanese, Chinese, and a few more."
        case .whisperSmall: "99 languages, including Arabic. Quick, less accurate."
        case .whisperTurbo: "99 languages, including Arabic mixed with English. The most accurate."
        }
    }

    public var isWhisper: Bool { self != .apple }

    /// The ggml file name, the same as Handy's and whisper.cpp's.
    public var fileName: String? {
        switch self {
        case .apple: nil
        case .whisperSmall: "ggml-small.bin"
        case .whisperTurbo: "ggml-large-v3-turbo.bin"
        }
    }

    /// The file's exact size in bytes, so a broken download is refused.
    public var byteCount: Int64? {
        switch self {
        case .apple: nil
        case .whisperSmall: 487_601_967
        case .whisperTurbo: 1_624_555_275
        }
    }

    public var downloadURL: URL? {
        fileName.map { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\($0)")! }
    }

    /// "470 MB", "1.6 GB".
    public var sizeText: String? {
        byteCount.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }

    /// The default for a new install: Apple's, which needs no download.
    public static let standard = SpeechModel.apple
}

/// Whether a model can run on this Mac now, and from where (S-051).
public enum ModelAvailability: Equatable, Sendable {
    case builtIn
    /// Read in place from the Handy app's folder; never moved or deleted.
    case fromHandy(URL)
    /// In Showreel's own Models folder; it can be deleted.
    case downloaded(URL)
    case missing

    public var url: URL? {
        switch self {
        case .fromHandy(let url), .downloaded(let url): url
        case .builtIn, .missing: nil
        }
    }

    public var isReady: Bool { self != .missing }
}

/// Finds model files: Showreel's own first, then Handy's.
public struct ModelLocator: Sendable {
    /// Showreel's models: ~/Library/Application Support/Showreel/Models.
    public var own: URL
    /// Handy's models: ~/Library/Application Support/com.pais.handy/models.
    public var handy: URL

    public init(own: URL, handy: URL) {
        self.own = own
        self.handy = handy
    }

    /// The real folders. `APP_MODELS_DIR` and `APP_HANDY_DIR` replace them in test runs.
    public static var standard: ModelLocator {
        let env = ProcessInfo.processInfo.environment
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ModelLocator(
            own: env["APP_MODELS_DIR"].map { URL(fileURLWithPath: $0) } ?? support.appending(path: "Showreel/Models"),
            handy: env["APP_HANDY_DIR"].map { URL(fileURLWithPath: $0) } ?? support.appending(path: "com.pais.handy/models"))
    }

    public func availability(of model: SpeechModel) -> ModelAvailability {
        guard let name = model.fileName else { return .builtIn }
        let mine = own.appending(path: name)
        if Self.isComplete(mine, model) { return .downloaded(mine) }
        let theirs = handy.appending(path: name)
        if Self.isComplete(theirs, model) { return .fromHandy(theirs) }
        return .missing
    }

    /// Where a download of `model` ends up.
    public func destination(of model: SpeechModel) -> URL? {
        model.fileName.map { own.appending(path: $0) }
    }

    /// A file of the model's exact size; anything else is a broken copy.
    static func isComplete(_ url: URL, _ model: SpeechModel) -> Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber else { return false }
        return size.int64Value == model.byteCount
    }
}

/// The caption language people pick: "auto", or a language code like "ar"
/// or "en". Apple's model needs a locale, so "auto" means this Mac's language there.
public enum CaptionLanguage {
    public static let automatic = "auto"

    /// Whisper's language codes, in its order (whisper.cpp `g_lang`).
    public static let whisper: [String] = [
        "en", "zh", "de", "es", "ru", "ko", "fr", "ja", "pt", "tr", "pl", "ca", "nl", "ar", "sv", "it", "id", "hi", "fi", "vi",
        "he", "uk", "el", "ms", "cs", "ro", "da", "hu", "ta", "no", "th", "ur", "hr", "bg", "lt", "la", "mi", "ml", "cy", "sk",
        "te", "fa", "lv", "bn", "sr", "az", "sl", "kn", "et", "mk", "br", "eu", "is", "hy", "ne", "mn", "bs", "kk", "sq", "sw",
        "gl", "mr", "pa", "si", "km", "sn", "yo", "so", "af", "oc", "ka", "be", "tg", "sd", "gu", "am", "yi", "lo", "uz", "fo",
        "ht", "ps", "tk", "nn", "mt", "sa", "lb", "my", "bo", "tl", "mg", "as", "tt", "haw", "ln", "ha", "ba", "jw", "su", "yue",
    ]

    /// The languages a model offers, as codes, "auto" first for Whisper.
    /// Apple's come from the system (`appleLocales`), as language codes.
    public static func codes(for model: SpeechModel, appleLocales: [String]) -> [String] {
        switch model {
        case .apple:
            var seen = Set<String>()
            return appleLocales.compactMap { Locale(identifier: $0).language.languageCode?.identifier }
                .filter { seen.insert($0).inserted }
        case .whisperSmall, .whisperTurbo:
            return [automatic] + whisper
        }
    }

    /// The language to use when `code` is not one the model offers: the
    /// model's first, or Automatic.
    public static func resolved(_ code: String, for model: SpeechModel, appleLocales: [String]) -> String {
        let offered = codes(for: model, appleLocales: appleLocales)
        if offered.contains(code) { return code }
        if model == .apple, let mac = Locale.current.language.languageCode?.identifier, offered.contains(mac) { return mac }
        return offered.first ?? automatic
    }

    /// "Automatic", "Arabic", "English".
    public static func name(_ code: String, in locale: Locale = .current) -> String {
        code == automatic ? "Automatic" : (locale.localizedString(forLanguageCode: code) ?? code)
    }

    /// A short mixed Arabic and English prompt, so Whisper keeps English
    /// words in Latin letters in Arabic speech (S-053). Whisper continues
    /// the prompt's style: product words stay as they are spoken. With
    /// Automatic, the language is detected first and this is asked again.
    public static func prompt(for code: String) -> String? {
        switch code {
        case "ar":
            "أهلاً بيكم، النهارده هنشرح الـ dashboard. هنعمل login، وبعدين نفتح الـ settings ونعمل copy للـ API key."
        default:
            nil
        }
    }
}
