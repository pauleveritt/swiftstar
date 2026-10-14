import SwiftUI
import SwiftStarKit

extension EnvironmentValues {
    /// The window's live body-font size (pt), from Settings' slider,
    /// propagated so every surface re-renders the moment it changes.
    @Entry var transcriptFontSize: CGFloat = CGFloat(TranscriptFontScale.defaultSize)
}

extension Font {
    /// A smaller text style at its share of the window's font size (SU.9),
    /// in place of a fixed `.caption`-style size.
    static func scaled(_ role: TextRole, base: CGFloat, design: Font.Design = .default) -> Font {
        let size = CGFloat(TranscriptFontScale.points(role, base: Double(base)))
        let font = Font.system(size: size, design: design)
        return role == .headline ? font.weight(.bold) : font
    }
}
