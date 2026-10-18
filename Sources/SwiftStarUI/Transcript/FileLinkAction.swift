import SwiftUI
import SwiftStarKit

/// How a transcript row opens a file it names (SU.16, D6): resolve the text,
/// then open the link in the transcript's one Quick Look. Nil outside a
/// transcript, or before a session has a checkout.
struct FileLinkAction {
    let resolve: (String) -> FileLink?
    let open: (FileLink) -> Void
}

extension EnvironmentValues {
    @Entry var fileLinkAction: FileLinkAction? = nil
}

/// A file name drawn as a link (D5): the link color, the pointing hand, and
/// "Quick Look …" as help, saying when it's the engine's copy.
struct FileLinkButton<Label: View>: View {
    let link: FileLink
    @ViewBuilder let label: () -> Label
    @Environment(\.fileLinkAction) private var action

    var body: some View {
        Button { action?.open(link) } label: { label() }
            .buttonStyle(.link)
            .pointerStyle(.link)
            .help(link.help)
    }
}
