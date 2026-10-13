import Testing
import Foundation
@testable import SwiftStarKit

struct EngineCommandTests {
    // MARK: argv

    struct ArgvCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let modelID: String?
        let contextSize: Int?
        let tail: [String]
    }

    static let argvCases: [ArgvCase] = [
        .init(testDescription: "argumentsAreExact", modelID: nil, contextSize: nil, tail: []),
        .init(testDescription: "emptySettingsKeepTheBaseArgv", modelID: "", contextSize: 0, tail: []),
        .init(testDescription: "modelIDAppended", modelID: "qwen3.8-flash-next", contextSize: nil,
              tail: ["--model-id", "qwen3.8-flash-next"]),
        .init(testDescription: "contextAppended", modelID: nil, contextSize: 20000, tail: ["--context-size", "20000"]),
        .init(testDescription: "bothInOrder", modelID: "m", contextSize: 8192,
              tail: ["--model-id", "m", "--context-size", "8192"]),
        .init(testDescription: "whitespaceIDAndNonPositiveContextIgnored", modelID: "  ", contextSize: -1, tail: []),
    ]

    @Test(arguments: argvCases) func arguments(_ c: ArgvCase) {
        let base = ["tui", "--ndjson", "--source", "/tmp/r", "--commit", "HEAD"]
        #expect(EngineCommand.arguments(source: URL(fileURLWithPath: "/tmp/r"), modelID: c.modelID, contextSize: c.contextSize)
            == base + c.tail)
    }

    // MARK: executable resolution

    struct ResolveCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let settingsPath: String?
        let pathEnv: String
        /// The candidates that exist; nil means every candidate does.
        let executables: [String]?
        let expected: EngineResolution
    }

    static let resolveCases: [ResolveCase] = [
        .init(testDescription: "settingsPathWins", settingsPath: "/opt/ds4", pathEnv: "/a:/b", executables: nil,
              expected: .found("/opt/ds4")),
        .init(testDescription: "emptySettingsFallsToPATH", settingsPath: "", pathEnv: "/a:/b",
              executables: ["/b/ds4-dogfood"], expected: .found("/b/ds4-dogfood")),
        .init(testDescription: "fallsBackToLocalBin", settingsPath: nil, pathEnv: "/a",
              executables: ["/Users/tester/.local/bin/ds4-dogfood"],
              expected: .found("/Users/tester/.local/bin/ds4-dogfood")),
        .init(testDescription: "notFoundListsEverySearchedPlace", settingsPath: "/opt/ds4", pathEnv: "/a:/b",
              executables: [], expected: .notFound(searched: [
                  "/opt/ds4", "/a/ds4-dogfood", "/b/ds4-dogfood", "/Users/tester/.local/bin/ds4-dogfood",
              ])),
    ]

    @Test(arguments: resolveCases) func resolveExecutable(_ c: ResolveCase) {
        let r = EngineCommand.resolveExecutable(
            settingsPath: c.settingsPath, pathEnv: c.pathEnv, home: URL(fileURLWithPath: "/Users/tester"),
            isExecutable: { c.executables?.contains($0) ?? true })
        #expect(r == c.expected)
    }

    // MARK: exit messages

    struct ExitCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let code: Int32
        var stderr = ""
        var sawReady = true
        var reason: EngineTermination = .exit
        var forced = false
        var terminated = false
        var afterProtocolError = false
        let message: String
    }

    static let exitCases: [ExitCase] = [
        .init(testDescription: "exitZeroEnded", code: 0, message: "ended"),
        .init(testDescription: "exitOneIsNotClean", code: 1, stderr: "boom",
              message: "Ended without a clean answer.\nboom"),
        .init(testDescription: "exit130Interrupted (plainInterruptStillInterrupted)", code: 130, message: "interrupted"),
        .init(testDescription: "unknownCodeShowsCode", code: 42, stderr: "weird", message: "exited with code 42\nweird"),
        .init(testDescription: "exitTwoQuotesArgparse", code: 2,
              stderr: "usage: ...\nds4-dogfood tui: error: no model on this Mac\n", sawReady: false,
              message: "refused to start: ds4-dogfood tui: error: no model on this Mac"),
        .init(testDescription: "failureBeforeReadyIsAStartRefusal", code: 1, stderr: "no git\n", sawReady: false,
              message: "refused to start: no git"),
        .init(testDescription: "signalExitReadsAsSignal", code: 9, reason: .signal,
              message: "killed by signal 9 (SIGKILL)"),
        .init(testDescription: "signalExitReadsAsSignal (unnamed)", code: 77, reason: .signal,
              message: "killed by signal 77"),
        .init(testDescription: "ownSigtermReadsAsQuitTimeout", code: 15, reason: .signal, terminated: true,
              message: "ended after the quit timed out"),
        .init(testDescription: "ownSigtermReadsAsQuitTimeout (not ours)", code: 15, reason: .signal,
              message: "killed by signal 15 (SIGTERM)"),
        .init(testDescription: "ownSigtermExit130ReadsAsQuitTimeout", code: 130, terminated: true,
              message: "ended after the quit timed out"),
        .init(testDescription: "forcedExitReadsAsForced", code: 9, reason: .signal, forced: true,
              message: "ended by force after the quit timed out"),
        .init(testDescription: "sessionArtifactsLineIsStripped", code: 1,
              stderr: "Session artifacts: /tmp/s/20260929-x\n", message: "Ended without a clean answer."),
        .init(testDescription: "sessionArtifactsLineIsStripped (mixed)", code: 1,
              stderr: "boom\nSession artifacts: /tmp/s/x\n", message: "Ended without a clean answer.\nboom"),
        .init(testDescription: "refusalIgnoresSessionArtifactsLine", code: 2,
              stderr: "ds4-dogfood: error: bad\nSession artifacts: /tmp/s/x\n", sawReady: false,
              message: "refused to start: ds4-dogfood: error: bad"),
        .init(testDescription: "protocolErrorExitReadsAsSuch", code: 130, sawReady: false, afterProtocolError: true,
              message: "ended after a protocol error"),
        .init(testDescription: "protocolErrorExitReadsAsSuch (signal)", code: SIGTERM, reason: .signal,
              afterProtocolError: true, message: "ended after a protocol error"),
        .init(testDescription: "ownExitAfterProtocolErrorKeepsTheEnginesReason", code: 2,
              stderr: "ds4-dogfood tui: error: bad flag", sawReady: false, afterProtocolError: true,
              message: "refused to start: ds4-dogfood tui: error: bad flag"),
    ]

    @Test(arguments: exitCases) func exitMessage(_ c: ExitCase) {
        let exit = EngineExit.describe(
            code: c.code, stderrTail: c.stderr, sawReady: c.sawReady, reason: c.reason,
            forced: c.forced, terminated: c.terminated, afterProtocolError: c.afterProtocolError)
        #expect(exit.message == c.message)
    }

    // SU.7a: no --commit (the engine refuses it on resume), no model flags.
    @Test func resumeArguments() {
        #expect(EngineCommand.resumeArguments(id: "20261013-1-x", source: URL(fileURLWithPath: "/r"))
                == ["tui", "--ndjson", "--resume", "20261013-1-x", "--source", "/r"])
    }

    @Test func applyCommandUsesDirectoryName() {
        #expect(EngineCommand.applyCommand(sessionDirectory: URL(fileURLWithPath: "/x/sessions/20260928-101010-repo"))
                == "ds4-dogfood apply 20260928-101010-repo")
    }
}
