import SwiftUI
import SwiftStarKit

/// The Recent folders as menu rows, each followed by a resume item for its
/// newest conversation (SU.7b, D2). The toolbar's folder menu and File ›
/// Open Recent both use it, so they stay alike. The controller is passed in
/// because `.commands` has no window environment.
public struct RecentProjectRows: View {
    private let controller: EngineController

    public init(controller: EngineController) { self.controller = controller }

    public var body: some View {
        ForEach(controller.recentProjects) { project in
            Button {
                controller.requestSwitch(to: URL(fileURLWithPath: project.path))
            } label: {
                if project.isCurrent {
                    Label(project.menuTitle, systemImage: "checkmark")
                } else {
                    Text(project.menuTitle)
                }
            }
            .disabled(project.disabledReason != nil)
            if let conversation = project.latest, let title = project.resumeTitle {
                Button {
                    controller.requestSwitch(to: URL(fileURLWithPath: project.path), resuming: conversation)
                } label: {
                    Label(title, systemImage: "bubble.left")
                }
            }
        }
    }
}
