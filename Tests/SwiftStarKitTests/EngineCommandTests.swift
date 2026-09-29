import Testing
import Foundation
@testable import SwiftStarKit

struct EngineCommandTests {
    private let home = URL(fileURLWithPath: "/Users/tester")

    @Test func argumentsAreExact() {
        #expect(EngineCommand.arguments(source: URL(fileURLWithPath: "/tmp/r"))
                == ["tui", "--ndjson", "--source", "/tmp/r", "--commit", "HEAD"])
    }

    @Test func settingsPathWins() {
        let r = EngineCommand.resolveExecutable(
            settingsPath: "/opt/ds4", pathEnv: "/a:/b", home: home,
            isExecutable: { _ in true })
        #expect(r == .found("/opt/ds4"))
    }

    @Test func emptySettingsFallsToPATH() {
        let r = EngineCommand.resolveExecutable(
            settingsPath: "", pathEnv: "/a:/b", home: home,
            isExecutable: { $0 == "/b/ds4-dogfood" })
        #expect(r == .found("/b/ds4-dogfood"))
    }

    @Test func fallsBackToLocalBin() {
        let r = EngineCommand.resolveExecutable(
            settingsPath: nil, pathEnv: "/a", home: home,
            isExecutable: { $0 == "/Users/tester/.local/bin/ds4-dogfood" })
        #expect(r == .found("/Users/tester/.local/bin/ds4-dogfood"))
    }

    @Test func notFoundListsEverySearchedPlace() {
        let r = EngineCommand.resolveExecutable(
            settingsPath: "/opt/ds4", pathEnv: "/a:/b", home: home,
            isExecutable: { _ in false })
        #expect(r == .notFound(searched: [
            "/opt/ds4", "/a/ds4-dogfood", "/b/ds4-dogfood",
            "/Users/tester/.local/bin/ds4-dogfood",
        ]))
    }

    @Test func exitTwoQuotesArgparse() {
        let exit = EngineExit.describe(
            code: 2,
            stderrTail: "usage: ...\nds4-dogfood tui: error: no model on this Mac\n",
            sawReady: false)
        #expect(exit.message == "refused to start: ds4-dogfood tui: error: no model on this Mac")
    }

    @Test func exitOneIsNotClean() {
        let exit = EngineExit.describe(code: 1, stderrTail: "boom", sawReady: true)
        #expect(exit.message.contains("without a clean answer"))
        #expect(exit.message.contains("boom"))
    }

    @Test func exitZeroEnded() {
        #expect(EngineExit.describe(code: 0, stderrTail: "", sawReady: true).message.contains("ended"))
    }

    @Test func exit130Interrupted() {
        #expect(EngineExit.describe(code: 130, stderrTail: "", sawReady: true).message.contains("interrupted"))
    }

    @Test func unknownCodeShowsCode() {
        let exit = EngineExit.describe(code: 42, stderrTail: "weird", sawReady: true)
        #expect(exit.message.contains("42"))
        #expect(exit.message.contains("weird"))
    }

    @Test func failureBeforeReadyIsAStartRefusal() {
        let exit = EngineExit.describe(code: 1, stderrTail: "no git\n", sawReady: false)
        #expect(exit.message == "refused to start: no git")
    }

    @Test func signalExitReadsAsSignal() {
        let exit = EngineExit.describe(code: 9, stderrTail: "", sawReady: true, reason: .signal)
        #expect(exit.message == "killed by signal 9 (SIGKILL)")
        #expect(EngineExit.describe(code: 77, stderrTail: "", sawReady: true, reason: .signal)
            .message == "killed by signal 77 (signal 77)")
    }

    @Test func forcedExitReadsAsForced() {
        let exit = EngineExit.describe(
            code: 9, stderrTail: "", sawReady: true, reason: .signal, forced: true)
        #expect(exit.message == "ended by force after the quit timed out")
    }

    @Test func applyCommandUsesDirectoryName() {
        #expect(EngineCommand.applyCommand(sessionDirectory: URL(fileURLWithPath: "/x/sessions/20260928-101010-repo"))
                == "ds4-dogfood apply 20260928-101010-repo")
    }

    private let src = URL(fileURLWithPath: "/tmp/r")
    private let p28 = ["tui", "--ndjson", "--source", "/tmp/r", "--commit", "HEAD"]

    @Test func emptySettingsKeepP28Argv() {
        #expect(EngineCommand.arguments(source: src, modelID: "", contextSize: 0) == p28)
    }

    @Test func modelIDAppended() {
        #expect(EngineCommand.arguments(source: src, modelID: "qwen3.8-flash-next")
                == p28 + ["--model-id", "qwen3.8-flash-next"])
    }

    @Test func contextAppended() {
        #expect(EngineCommand.arguments(source: src, contextSize: 20000)
                == p28 + ["--context-size", "20000"])
    }

    @Test func bothInOrder() {
        #expect(EngineCommand.arguments(source: src, modelID: "m", contextSize: 8192)
                == p28 + ["--model-id", "m", "--context-size", "8192"])
    }

    @Test func whitespaceIDAndNonPositiveContextIgnored() {
        #expect(EngineCommand.arguments(source: src, modelID: "  ", contextSize: -1) == p28)
    }

    private func info(_ m: String?, _ c: Int?) -> EngineSessionInfo {
        EngineSessionInfo(id: "s", modelID: m, contextSize: c)
    }

    @Test func restartNeededOnlyWhileSessionRunsAndSettingsDiffer() {
        let loaded = info("laguna-xs-2.1", 20000)
        #expect(!EngineCommand.restartNeeded(session: nil, modelID: "x", contextSize: 1))
        #expect(!EngineCommand.restartNeeded(session: loaded, modelID: "", contextSize: 0))
        #expect(!EngineCommand.restartNeeded(session: loaded, modelID: " ", contextSize: -5))
        #expect(!EngineCommand.restartNeeded(session: loaded, modelID: "laguna-xs-2.1", contextSize: 20000))
        #expect(!EngineCommand.restartNeeded(session: loaded, modelID: " laguna-xs-2.1 ", contextSize: 0))
        #expect(EngineCommand.restartNeeded(session: loaded, modelID: "qwen3.8-flash-next", contextSize: 0))
        #expect(EngineCommand.restartNeeded(session: loaded, modelID: "", contextSize: 8192))
        // Fields the session did not report are not compared.
        #expect(!EngineCommand.restartNeeded(session: info(nil, nil), modelID: "m", contextSize: 8192))
        #expect(EngineCommand.restartNeeded(session: info(nil, 8192), modelID: "m", contextSize: 4096))
        #expect(!EngineCommand.restartNeeded(session: info(nil, 8192), modelID: "m", contextSize: 8192))
    }
}
