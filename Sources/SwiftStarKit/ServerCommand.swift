import Foundation

/// The engine launch settings. Pure value type; defaults live in the app, not here.
public struct EngineSettings: Equatable, Sendable {
    public var engineDir: URL
    public var modelPath: URL
    public var port: Int
    public var contextSize: Int
    public var host: String
    /// Launch-time engine flags (SSD streaming etc.) declared by a selected
    /// variant; nil = engine defaults.
    public var runtime: EngineRuntimeConfig?

    public init(
        engineDir: URL,
        modelPath: URL,
        port: Int,
        contextSize: Int = 32768,
        host: String = "127.0.0.1",
        runtime: EngineRuntimeConfig? = nil
    ) {
        self.engineDir = engineDir
        self.modelPath = modelPath
        self.port = port
        self.contextSize = contextSize
        self.host = host
        self.runtime = runtime
    }
}

/// The one argv contract: what the app spawns (as `Process.arguments`, after
/// `Process` prepends the executable path as argv[0]) and what the fake engine
/// validates. The binary path itself is NOT part of the returned array.
public enum ServerCommand {
    public static func argv(settings: EngineSettings) -> [String] {
        var argv: [String] = [
            "-m", settings.modelPath.path,
            "-c", String(settings.contextSize),
            "--host", settings.host,
            "--port", String(settings.port),
        ]
        if let runtime = settings.runtime {
            argv.append(contentsOf: runtime.argvFlags)
        }
        return argv
    }

    /// The executable to spawn for these settings.
    public static func binaryPath(settings: EngineSettings) -> URL {
        settings.engineDir.appendingPathComponent("ds4-server")
    }
}
