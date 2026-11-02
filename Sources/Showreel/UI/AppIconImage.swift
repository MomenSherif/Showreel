import AppKit
import SwiftUI

/// The app's own icon (S-046), as the Dock shows it: in the Library's empty
/// state and the Welcome window. Decorative; the text beside it names the app.
struct AppIconImage: View {
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
