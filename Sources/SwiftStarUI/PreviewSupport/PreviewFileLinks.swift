import SwiftUI

extension View {
    /// The transcript's file links, for a row previewed on its own (SU.16):
    /// names resolve against this repository, and opening does nothing, since
    /// a first-frame render can't show Quick Look.
    func previewFileLinks() -> some View {
        let lookup = FileLinkLookup(
            source: EngineController.previewCheckout, worktree: nil, files: .previewFiles)
        return environment(\.fileLinkAction, FileLinkAction(resolve: lookup.resolve, open: { _ in }))
    }
}
