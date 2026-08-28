import Testing
@testable import SwiftStarKit

struct PoolPromptTests {
    @Test func encodesWorkerAddressedPrompt() {
        #expect(PoolPrompt(worker: WorkerId(3), text: "do it").encode()
                == #"{"s":"do it","t":"prompt","worker":3}"#)
    }
    @Test func barePromptIsWorkerZero() {
        #expect(PoolPrompt(worker: .orchestrator, text: "go").encode()
                == #"{"s":"go","t":"prompt","worker":0}"#)
    }

    @Test func multiLineTextEncodesToExactlyOnePhysicalLine() {
        // The engine's stdin is line-delimited — it splits on "\n" and parses
        // each line as its own prompt. A raw multi-line prompt therefore arrived
        // as N prompts, N-1 of them garbage. Every writer (user prompts, consult
        // answers, injected receipts) goes through this encoder, so the escaping
        // is the whole guarantee.
        let encoded = PoolPrompt(worker: .orchestrator, text: "line one\nline two\nline three").encode()
        #expect(!encoded.contains("\n"))
        #expect(encoded == #"{"s":"line one\nline two\nline three","t":"prompt","worker":0}"#)
    }

    @Test func quotesAndBackslashesSurviveEncoding() {
        // The engine decodes \" \\ \n \t \r and \uXXXX (agent_json_parse_string),
        // which is exactly what JSONSerialization emits.
        let encoded = PoolPrompt(worker: WorkerId(1), text: #"say "hi" \ then stop"#).encode()
        #expect(!encoded.contains("\n"))
        #expect(encoded.contains(#"\"hi\""#))
        #expect(encoded.contains(#"\\"#))
    }

    // MARK: - P23 per-turn fields

    @Test func nilFieldsKeepTodayBytes() {
        // The byte-identical contract: every existing fixture and fake was
        // encoded with these two fields absent; a nil field must not add a
        // byte.
        #expect(PoolPrompt(worker: .orchestrator, text: "go").encode()
                == #"{"s":"go","t":"prompt","worker":0}"#)
    }

    @Test func thinkFieldEncodesOnlyWhenSet() {
        #expect(PoolPrompt(worker: .orchestrator, text: "go", think: .off).encode()
                == #"{"s":"go","t":"prompt","think":"none","worker":0}"#)
        #expect(PoolPrompt(worker: .orchestrator, text: "go", think: .max).encode()
                == #"{"s":"go","t":"prompt","think":"max","worker":0}"#)
    }

    @Test func contextFieldEncodesOnlyWhenSet() {
        #expect(PoolPrompt(worker: WorkerId(1), text: "do it", contextSize: 8192).encode()
                == #"{"ctx":8192,"s":"do it","t":"prompt","worker":1}"#)
    }

    @Test func bothFieldsSortedWithEverythingElse() {
        #expect(PoolPrompt(worker: WorkerId(1), text: "do it", think: .off, contextSize: 8192).encode()
                == #"{"ctx":8192,"s":"do it","t":"prompt","think":"none","worker":1}"#)
    }
}
