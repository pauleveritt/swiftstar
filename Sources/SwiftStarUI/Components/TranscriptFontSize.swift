import SwiftUI
import SwiftStarKit

/// The transcript's live body-font size (pt), driven by Settings' four-slot
/// slider and propagated via the environment so every surface — composer,
/// pills, prose, cards — re-renders the moment it changes (no restart).
private struct TranscriptFontSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = CGFloat(TranscriptFontScale.defaultSize)
}

extension EnvironmentValues {
    var transcriptFontSize: CGFloat {
        get { self[TranscriptFontSizeKey.self] }
        set { self[TranscriptFontSizeKey.self] = newValue }
    }
}
