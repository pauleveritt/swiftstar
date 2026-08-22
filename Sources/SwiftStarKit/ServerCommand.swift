import Foundation

/// The engine launch settings. Pure value type; defaults live in the app, not here.
public struct EngineSettings: Equatable, Sendable {
    public var engineDir: URL
    public var modelPath: URL
    public var contextSize: Int
    public var port: Int
    public var host: String

    public init(
        engineDir: URL,
        modelPath: URL,
        contextSize: Int = 32768,
        port: Int,
        host: String = "127.0.0.1"
    ) {
        self.engineDir = engineDir
        self.modelPath = modelPath
        self.contextSize = contextSize
        self.port = port
        self.host = host
    }
}

/// The one argv contract: what the app spawns and what the fake engine validates.
public enum ServerCommand {
    public static func argv(settings: EngineSettings) -> [String] {
        [
            settings.engineDir.appendingPathComponent("ds4-server").path,
            "-m", settings.modelPath.path,
            "-c", String(settings.contextSize),
            "--host", settings.host,
            "--port", String(settings.port),
        ]
    }
}
