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
}
