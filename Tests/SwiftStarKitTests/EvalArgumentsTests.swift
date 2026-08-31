import Testing
@testable import SwiftStarKit

/// Task 6: the ten analyzer verbs moved into `swiftstar-eval` unchanged. This
/// only checks the shared verb registry (`EvalArguments.knownVerbs`) — the
/// registry Task 5's `run` and Task 7's `experiment`/`verdict` extend rather
/// than each rewriting a switch. It does not exercise the verbs' behavior
/// (unchanged from `swiftstar-analyze`, spot-checked byte-for-byte instead).
struct EvalArgumentsTests {
    @Test func everyAnalyzeVerbIsReachable() {
        let verbs = [
            "list", "summary", "trace", "diff", "rereads",
            "findings", "taxonomy", "validate", "report", "index",
        ]
        for verb in verbs {
            #expect(EvalArguments.isKnownVerb(verb), "expected \(verb) to be a known verb")
        }
    }

    @Test func summariseIsRejected() {
        // Sibling refusal (binding rule 4): a near-miss verb name is not
        // silently accepted.
        #expect(!EvalArguments.isKnownVerb("summarise"))
    }

    // MARK: - Task 5: `run`'s flag set

    /// Binding rule 4: every former `CAPTURE_*` env knob
    /// (`swiftstar-drive`/`swiftstar-agenttest`) becomes a named flag — a
    /// setting living only in an env var lands in no provenance.
    @Test func everyFormerCaptureEnvKnobHasAFlag() {
        let envKnobs = [
            "CAPTURE_GGUF", "CAPTURE_CTX", "CAPTURE_WORKSPACE", "CAPTURE_SHELL",
            "CAPTURE_HOST_TOOLS", "CAPTURE_POWER", "CAPTURE_PER_TURN_THINK",
            "CAPTURE_PROMPTS_FILE",
        ]
        let runFlagNames = Set(EvalArguments.runFlags.map(\.name))
        for knob in envKnobs {
            let flag = EvalArguments.captureEnvKnobFlags[knob]
            #expect(flag != nil, "expected \(knob) to map to a named flag")
            if let flag {
                #expect(runFlagNames.contains(flag), "\(knob) maps to '\(flag)', which run does not accept")
            }
        }
    }

    @Test func rejectsAnUnknownFlag() {
        let result = EvalArguments.parse(["run", "--prompt", "hi", "--bogus"])
        switch result {
        case .success:
            Issue.record("expected --bogus to be rejected")
        case .failure(let message):
            #expect(message.contains("--bogus"))
        }
    }

    /// Sibling of `rejectsAnUnknownFlag`: every flag the brief (plus binding
    /// rule 4's `CAPTURE_*` replacements) documents is actually accepted.
    @Test func acceptsTheDocumentedFlagSet() {
        let argv = [
            "run",
            "--prompt", "hello",
            "--mode", "bare",
            "--variant", "laguna-s-2.1",
            "--gguf", "/tmp/model.gguf",
            "--ctx", "8192",
            "--power", "70",
            "--shell", "on",
            "--workspace", "/tmp/ws",
            "--host-tools",
            "--per-turn-think",
            "--seed", "42",
            "--tools", "read,write",
            "--dry-run",
            "--bare",
        ]
        switch EvalArguments.parse(argv) {
        case .failure(let message):
            Issue.record("expected the documented flag set to parse, got: \(message)")
        case .success(let invocation):
            #expect(invocation.verb == "run")
            #expect(invocation.flags["--prompt"] == "hello")
            #expect(invocation.flags["--mode"] == "bare")
            #expect(invocation.flags["--ctx"] == "8192")
            #expect(invocation.flags["--power"] == "70")
            #expect(invocation.flags["--host-tools"] == "true")
            #expect(invocation.flags["--dry-run"] == "true")
            #expect(invocation.flags["--bare"] == "true")
            #expect(invocation.positional.isEmpty)
        }
    }

    // MARK: - Task 8: `--bare` (swiftstar-drive's retirement ruling)

    /// `--bare` reproduces `swiftstar-drive`'s exact P5 argv shape — it must
    /// be its own value-less flag, not folded into an existing one.
    @Test func runFlagsDeclaresBare() {
        #expect(EvalArguments.runFlags.contains(EvalArguments.FlagSpec("--bare", takesValue: false)))
    }
}
