import SwiftUI
import SwiftStarKit

extension EnvironmentValues {
    /// The window's live body-font size (pt), from Settings' slider,
    /// propagated so every surface re-renders the moment it changes.
    @Entry var fontSize: CGFloat = CGFloat(TranscriptFontScale.defaultSize)
}

extension Font {
    /// A smaller text style at its share of the window's font size (SU.9),
    /// in place of a fixed `.caption`-style size.
    static func scaled(_ role: TextRole, base: CGFloat, design: Font.Design = .default) -> Font {
        Font.system(size: CGFloat(TranscriptFontScale.points(role, base: Double(base))), design: design)
    }
}
