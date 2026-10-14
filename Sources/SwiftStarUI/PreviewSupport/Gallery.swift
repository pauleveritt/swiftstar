import Foundation

extension EngineController {
    /// The gallery app's controller (SU.12): the previews' running session,
    /// conversations and workspace. A fixture controller, so it never starts
    /// the engine, loads the catalog or reads the session lists.
    public static func gallery() -> EngineController { previewRunning }
}
