import PackagePlugin
import Foundation

@main
struct FastTierGuard: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }
        let tool = try context.tool(named: "FastTierGuardTool")
        // URL-based API (the Path-based forms are deprecated and emit a warning
        // on every build — F10).
        return try sourceTarget.sourceFiles(withSuffix: "swift").map { file in
            .buildCommand(
                displayName: "FastTierGuard: \(file.url.lastPathComponent)",
                executable: tool.url,
                arguments: [file.url.path]
            )
        }
    }
}
