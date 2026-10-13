import SwiftUI
import SwiftStarKit

extension EnvironmentValues {
    /// The transcript's live body-font size (pt), from Settings' slider,
    /// propagated so every surface re-renders the moment it changes.
    @Entry var transcriptFontSize: CGFloat = CGFloat(TranscriptFontScale.defaultSize)
}
