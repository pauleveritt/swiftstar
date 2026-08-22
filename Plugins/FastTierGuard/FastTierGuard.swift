import PackagePlugin

@main
struct FastTierGuard: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }
        let tool = try context.tool(named: "FastTierGuardTool")
        return try sourceTarget.sourceFiles(withSuffix: "swift").map { file in
            .buildCommand(
                displayName: "FastTierGuard: \(file.path.lastComponent)",
                executable: tool.path,
                arguments: [file.path.string]
            )
        }
    }
}
