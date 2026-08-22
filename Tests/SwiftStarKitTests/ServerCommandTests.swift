import Testing
import Foundation
@testable import SwiftStarKit

struct ServerCommandTests {
    @Test func buildsExactArgv() {
        let settings = EngineSettings(
            engineDir: URL(fileURLWithPath: "/tmp/engine"),
            modelPath: URL(fileURLWithPath: "/tmp/model.gguf"),
            contextSize: 32768,
            port: 43210
        )
        let argv = ServerCommand.argv(settings: settings)
        #expect(argv == [
            "-m", "/tmp/model.gguf",
            "-c", "32768",
            "--host", "127.0.0.1",
            "--port", "43210",
        ])
        #expect(ServerCommand.binaryPath(settings: settings) == "/tmp/engine/ds4-server")
    }

    @Test func honorsOverrides() {
        let settings = EngineSettings(
            engineDir: URL(fileURLWithPath: "/a"),
            modelPath: URL(fileURLWithPath: "/b.bin"),
            contextSize: 16384,
            port: 9,
            host: "0.0.0.0"
        )
        #expect(ServerCommand.argv(settings: settings).contains("16384"))
        #expect(ServerCommand.argv(settings: settings).contains("0.0.0.0"))
        #expect(ServerCommand.argv(settings: settings).contains("9"))
    }
}
