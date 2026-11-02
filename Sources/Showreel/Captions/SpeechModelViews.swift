import SwiftUI
import ShowreelKit

/// Settings > Captions (S-050, S-051): the speech model, where each one
/// comes from, and the language.
struct CaptionSettings: View {
    @Bindable private var models = SpeechModels.shared

    var body: some View {
        Section {
            Picker("Speech Model", selection: $models.model) {
                ForEach(SpeechModel.allCases) { Text($0.title).tag($0) }
            }
            LanguagePicker()
        } footer: {
            Text("Captions are made on this Mac. Nothing is uploaded.")
                .foregroundStyle(.secondary)
        }
        Section {
            ForEach(SpeechModel.allCases) { model in
                ModelRow(model: model)
            }
        } header: {
            Text("Models")
        } footer: {
            Text("Whisper models from Handy are used where they are, with no second download. Showreel never changes them.")
                .foregroundStyle(.secondary)
        }
    }
}

/// Language, from the chosen model's list.
struct LanguagePicker: View {
    @Bindable private var models = SpeechModels.shared

    var body: some View {
        Picker("Language", selection: $models.language) {
            ForEach(models.languages, id: \.self) { code in
                Text(CaptionLanguage.name(code)).tag(code)
                if code == CaptionLanguage.automatic { Divider() }
            }
        }
        .help(models.model.isWhisper ? "Automatic finds the language, and keeps English words in Arabic speech in English letters."
                                     : "Apple's model listens in one language.")
    }
}

/// One model: what it is, where it is, and Download, Cancel, or Delete.
struct ModelRow: View {
    let model: SpeechModel
    private var models: SpeechModels { SpeechModels.shared }
    @State private var confirmsDelete = false

    var body: some View {
        LabeledContent {
            ModelAction(model: model)
                .confirmationDialog("Delete \(model.title)?", isPresented: $confirmsDelete) {
                    Button("Delete", role: .destructive) { models.delete(model) }
                } message: {
                    Text("You can download it again later.")
                }
        } label: {
            Text(model.title)
            Text(model.summary).foregroundStyle(.secondary)
            if let failure = models.failures[model] {
                Text(failure).foregroundStyle(.red)
            }
        }
        .contextMenu {
            if case .downloaded = models.availability(of: model) {
                Button("Delete…") { confirmsDelete = true }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The state and the one action for a model: Built In, From Handy,
/// Downloaded with Delete…, a download's progress with Cancel, or Download.
struct ModelAction: View {
    let model: SpeechModel
    var compact = false
    private var models: SpeechModels { SpeechModels.shared }
    @State private var confirmsDelete = false

    var body: some View {
        if let fraction = models.downloads[model] {
            HStack(spacing: Space.sm) {
                ProgressView(value: fraction)
                    .frame(width: Layout.progressWidth)
                    .accessibilityLabel("Downloading \(model.title)")
                    .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
                Button("Cancel") { models.cancelDownload(model) }
            }
        } else {
            switch models.availability(of: model) {
            case .builtIn:
                Text("Built In").foregroundStyle(.secondary)
            case .fromHandy:
                Text("From Handy").foregroundStyle(.secondary)
                    .help("Read from the Handy app's models folder")
            case .downloaded:
                if compact {
                    Text("Downloaded").foregroundStyle(.secondary)
                } else {
                    Button("Delete…") { confirmsDelete = true }
                        .confirmationDialog("Delete \(model.title)?", isPresented: $confirmsDelete) {
                            Button("Delete", role: .destructive) { models.delete(model) }
                        } message: {
                            Text("It frees \(model.sizeText ?? "space"). You can download it again later.")
                        }
                        .help("Downloaded, \(model.sizeText ?? "")")
                }
            case .missing:
                Button("Download \(model.sizeText ?? "")") { models.download(model) }
                    .help("Download \(model.title) once, to use on this Mac")
            }
        }
    }
}
