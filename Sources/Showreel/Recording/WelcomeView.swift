import SwiftUI

/// "Welcome to Showreel" (S-001): the access Showreel needs, one row each.
/// Shown on first launch and from Help > Check Access….
struct WelcomeView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    private var permissions = Permissions.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            HStack(alignment: .center, spacing: Space.lg) {
                AppIconImage(size: Layout.appIconSmall)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Welcome to Showreel")
                        .font(.title2.weight(.semibold))
                    Text("Showreel needs your permission to record. Your recordings stay on this Mac.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .gridProbe("header", area: "welcome")

            Form {
                ForEach(Permissions.Kind.allCases) { kind in
                    PermissionRow(kind: kind, state: permissions.state(kind))
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, -Space.xl)
            .padding(.vertical, -Space.lg)

            HStack {
                if permissions.canRecord {
                    Spacer()
                } else {
                    Text("Screen Recording is required to record.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Button("Continue") {
                    Store.defaults.set(true, forKey: "welcome.done")
                    dismissWindow(id: "welcome")
                    RecordController.shared.newRecording()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!permissions.canRecord)
            }
            .gridProbe("footer", area: "welcome", edge: nil)
        }
        .padding(Space.margin)
        .frame(width: Layout.welcomeWidth)
        .gridArea("welcome")
        .noInitialFocus()
        .onAppear { permissions.startWatching() }
        .onDisappear { permissions.stopWatching() }
    }
}

private struct PermissionRow: View {
    let kind: Permissions.Kind
    let state: Permissions.State

    var body: some View {
        LabeledContent {
            switch state {
            case .allowed:
                Label {
                    Text("Allowed").foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                .labelStyle(.titleAndIcon)
            case .notAllowed:
                Button("Allow…") { Permissions.shared.request(kind) }
                    .help("Allow Showreel to use the \(kind.title.lowercased())")
            case .needsRelaunch:
                Button("Quit & Reopen") { Permissions.shared.relaunch() }
                    .help("Showreel must reopen to start using Screen Recording")
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                    Text(state == .needsRelaunch ? "Quit and reopen Showreel to finish." : kind.reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: kind.symbol)
                    .foregroundStyle(.tint)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(kind.title), \(state == .allowed ? "allowed" : "not allowed")")
    }
}
