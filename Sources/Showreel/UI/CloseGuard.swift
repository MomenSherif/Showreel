import AppKit
import SwiftUI

extension View {
    /// Asks before the window closes while `ask` returns a question (S-037).
    /// `ask` returns nil to let the window close. The question shows as an
    /// alert sheet; its first button closes the window after `confirm`.
    func confirmsClose(_ ask: @escaping @MainActor () -> CloseQuestion?) -> some View {
        background(CloseGuardHook(ask: ask))
    }
}

/// "Stop Exporting “Demo”?" with "Stop Exporting" and "Continue".
struct CloseQuestion {
    var title: String
    var message: String
    var confirm: String
    var cancel: String
    var onConfirm: @MainActor () -> Void
}

private struct CloseGuardHook: NSViewRepresentable {
    let ask: @MainActor () -> CloseQuestion?

    func makeNSView(context: Context) -> Probe { Probe(ask: ask) }
    func updateNSView(_ probe: Probe, context: Context) { probe.guardian.ask = ask }

    final class Probe: NSView {
        let guardian: CloseGuardian
        init(ask: @escaping @MainActor () -> CloseQuestion?) {
            guardian = CloseGuardian(ask: ask)
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window.delegate !== guardian else { return }
            guardian.original = window.delegate
            window.delegate = guardian
        }
    }
}

/// Stands in front of SwiftUI's window delegate: it answers
/// `windowShouldClose` and hands every other message to the original.
final class CloseGuardian: NSObject, NSWindowDelegate {
    // AppKit asks `responds(to:)` from no particular isolation; the delegate
    // is set once, on the main thread, before any message arrives.
    nonisolated(unsafe) weak var original: NSWindowDelegate?
    var ask: @MainActor () -> CloseQuestion?
    /// The person confirmed: the next close goes through.
    private var confirmed = false

    init(ask: @escaping @MainActor () -> CloseQuestion?) {
        self.ask = ask
    }

    nonisolated override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
    }

    func windowShouldClose(_ window: NSWindow) -> Bool {
        let theirs = original?.windowShouldClose?(window) ?? true
        guard theirs, !confirmed, let question = ask() else { return theirs }
        guard window.attachedSheet == nil else { NSSound.beep(); return false }
        let alert = NSAlert()
        alert.messageText = question.title
        alert.informativeText = question.message
        alert.addButton(withTitle: question.confirm)
        alert.addButton(withTitle: question.cancel)
        alert.beginSheetModal(for: window) { [weak self, weak window] response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn else { return }
                question.onConfirm()
                self?.confirmed = true
                window?.performClose(nil)
                self?.confirmed = false
            }
        }
        return false
    }
}
