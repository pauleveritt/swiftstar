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
}
