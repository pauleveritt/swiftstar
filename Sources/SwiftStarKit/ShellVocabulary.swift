import Foundation

/// One named region/component of the app shell (P19.1 D5). `id` is the stable,
/// load-bearing name — the future image-describer and the agent's layout
/// reasoning both speak in these ids, so renaming one is a test-visible change.
public struct ShellRegion: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let role: String

    public init(id: String, name: String, role: String) {
        self.id = id
        self.name = name
        self.role = role
    }
}

/// The machine-readable component/region vocabulary. Regions + controls, one
/// entry each; `phaseBrowserRail` is reserved for SDD (not built this phase).
public enum ShellVocabulary {
    public static let regions: [ShellRegion] = [
        .init(id: "sidebar", name: "Sidebar", role: "primary navigation sections"),
        .init(id: "toolbar", name: "Toolbar", role: "window toolbar: model, workspace, session"),
        .init(id: "detail", name: "Detail", role: "the selected section's content"),
        .init(id: "inspector", name: "Inspector", role: "off-by-default trailing telemetry panel"),
        .init(id: "composer", name: "Composer", role: "prompt entry + send/stop"),
        .init(id: "transcript", name: "Transcript", role: "the conversation's rows"),
        .init(id: "toolCard", name: "Tool card", role: "one tool call's rendered state"),
        .init(id: "statusBar", name: "Status bar", role: "telemetry rings + rates"),
        .init(id: "ringGauge", name: "Ring gauge", role: "context/memory severity dial"),
        .init(id: "modelMenu", name: "Model menu", role: "the active model choice"),
        .init(id: "workspaceControl", name: "Workspace control", role: "the active workspace picker"),
        .init(id: "phaseBrowserRail", name: "Phase browser rail", role: "SDD mode's secondary listing (reserved)"),
        .init(id: "picker", name: "Picker", role: "a selection control"),
        .init(id: "segmentedControl", name: "Segmented control", role: "an exclusive small-set switch"),
        .init(id: "toggle", name: "Toggle", role: "a boolean switch"),
        .init(id: "slider", name: "Slider", role: "a ranged value"),
        .init(id: "textField", name: "Text field", role: "single-line input"),
        .init(id: "disclosure", name: "Disclosure", role: "a collapsible region"),
        .init(id: "section", name: "Section", role: "a grouped region"),
        .init(id: "list", name: "List", role: "a selection list"),
        .init(id: "grid", name: "Grid", role: "a multi-column layout"),
    ]
}
