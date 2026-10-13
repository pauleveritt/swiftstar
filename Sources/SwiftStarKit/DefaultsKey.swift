/// `UserDefaults`/`@AppStorage` keys, in one place so a key is never
/// duplicated as a bare string literal across files. Raw values are fixed:
/// changing one would silently orphan an existing user's saved setting.
public enum DefaultsKey: String, Sendable {
    case workspace = "agentWorkspace"
    case executable = "engineExecutable"
    case modelID = "engineModelID"
    case contextSize = "engineContextSize"
    case recentWorkspaces = "recentWorkspaces"
    case inspectorPresented = "appShellInspectorPresented"
    case transcriptFontSize = "transcriptFontSize"
    /// The most recent ended session's directory (SU.6c, D2).
    case lastSessionDirectory = "lastSessionDirectory"
    /// The conversation sidebar is shown (SU.7a).
    case sidebarVisible = "sidebarVisible"
}
