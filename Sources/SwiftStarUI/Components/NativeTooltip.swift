import AppKit
import SwiftUI

/// SwiftUI's `.help` does not reliably create a hover target for a small,
/// custom-drawn view. Keep a transparent AppKit view over each status widget so
/// macOS can provide its native tooltip while the gauge remains non-interactive.
/// Rechecked on macOS 27 (SU.6e): with `.help` and `.contentShape` alone, the
/// rings showed no tooltip; only the GPU figures' text did.
private struct NativeTooltipView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = text
    }
}

private struct NativeTooltipModifier: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content.overlay {
            NativeTooltipView(text: text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    func nativeTooltip(_ text: String) -> some View {
        modifier(NativeTooltipModifier(text: text))
    }
}
