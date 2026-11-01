import AppKit
import ScreenCaptureKit
import SwiftUI
import ShowreelKit

/// The 3-2-1 before recording (S-007), centered on the recorded display.
/// A click or Escape cancels.
final class Countdown {
    static let shared = Countdown()
    private var panel: FloatingPanel?

    func show(on displayID: CGDirectDisplayID) {
        hide()
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) ?? NSScreen.main else { return }
        var options = FloatingPanel.Options()
        options.level = .screenSaver
        options.onCancel = { RecordController.shared.cancelCountdown(reason: "Escape") }
        let panel = FloatingPanel(size: screen.frame.size, options: options, content: CountdownView())
        panel.setFrame(screen.frame, display: true)
        panel.present()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    var window: NSWindow? { panel }
}

struct CountdownView: View {
    private var recorder = RecordController.shared

    var body: some View {
        ZStack {
            Color.clear
            VStack(spacing: Space.xl) {
                Text("\(recorder.countdown)")
                    .font(.system(size: 72, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .frame(width: Layout.countdownCircle, height: Layout.countdownCircle)
                    .glassEffect(.regular, in: Circle())
                    .id(recorder.countdown)
                    .transition(Motion.reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
                Text("Click anywhere or press Escape to cancel")
                    .font(.callout)
                    .foregroundStyle(Surfaces.onScrim)
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.sm)
                    .background(Surfaces.scrim, in: Capsule())
            }
            .animation(Motion.resolved(Motion.countdownTick), value: recorder.countdown)
        }
        .contentShape(Rectangle())
        .onTapGesture { RecordController.shared.cancelCountdown(reason: "click") }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording starts in \(recorder.countdown)")
    }
}

/// The floating bar while recording (S-007): time, Pause, Stop, Restart.
/// Left out of the recording like every Showreel panel.
final class RecordingControls {
    static let shared = RecordingControls()
    private(set) var panel: FloatingPanel?

    func show(on displayID: CGDirectDisplayID) {
        let size = CGSize(width: 420, height: 56 + Space.xxl)
        if panel == nil {
            var options = FloatingPanel.Options()
            options.level = .statusBar
            options.takesKey = false
            options.movable = true
            panel = FloatingPanel(size: size, options: options, content: RecordingControlsView())
        }
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.displayID == displayID } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + Layout.controlsInset))
        }
        panel.present()
    }

    func hide() { panel?.orderOut(nil) }
}

struct RecordingControlsView: View {
    private var recorder = RecordController.shared
    @State private var dotOn = true

    var body: some View {
        VStack(spacing: Space.xs) {
            if recorder.lowDisk {
                Label("Less than 2 GB free on this disk", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .symbolRenderingMode(.multicolor)
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, Space.xs)
                    .glassEffect(.regular, in: Capsule())
            }
            GlassEffectContainer(spacing: Space.sm) {
                HStack(spacing: Space.md) {
                    status
                    Divider().frame(height: Space.xl)
                    Button(paused ? "Resume" : "Pause", systemImage: paused ? "play.fill" : "pause.fill") { recorder.togglePause() }
                        .help(paused ? "Continue recording (⌃⌥⌘P)" : "Pause without a gap in the video (⌃⌥⌘P)")
                    Button("Stop", systemImage: "stop.fill") { recorder.stop() }
                        .help("Stop and open the project (⌃⌥⌘R)")
                    Divider().frame(height: Space.xl)
                    Button("Restart", systemImage: "arrow.counterclockwise") { recorder.restart() }
                        .help("Throw away this recording and start again")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .padding(.horizontal, Space.md)
                .frame(height: 56)
                .glassEffect(.regular, in: Capsule())
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .onAppear { pulse() }
        .onChange(of: recorder.state) { pulse() }
    }

    private var paused: Bool { recorder.state == .paused }

    private var status: some View {
        HStack(spacing: Space.sm) {
            if paused {
                Text("Paused").font(.callout.weight(.semibold))
            } else {
                Circle().fill(Media.record).frame(width: Space.md, height: Space.md)
                    .opacity(dotOn ? 1 : 0.35)
            }
            Text(TimeText.clock(recorder.elapsed))
                .font(.body.monospacedDigit().weight(.medium))
                .contentTransition(.numericText())
                .opacity(paused && !dotOn ? 0.4 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(paused ? "Paused" : "Recording")
        .accessibilityValue(TimeText.spoken(recorder.elapsed))
    }

    /// The recording dot pulses, and the time blinks while paused. Both stop under Reduce Motion.
    private func pulse() {
        dotOn = true
        guard let loop = Motion.resolved(Motion.pulse, isLoop: true) else { return }
        withAnimation(loop) { dotOn = false }
    }
}
