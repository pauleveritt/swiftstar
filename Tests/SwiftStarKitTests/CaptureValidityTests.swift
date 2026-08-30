import Testing
@testable import SwiftStarKit

struct CaptureValidityTests {
    @Test func missingWireIsUnauditable() {
        let result = CaptureValidity.audit(wire: nil)
        #expect(result.v5 == CaptureValidity.Check(
            status: .unauditable, detail: "no wire.ndjson"))
        #expect(result.v6 == CaptureValidity.Check(
            status: .unauditable, detail: "no wire.ndjson"))
    }

    @Test(arguments: [
        "exceeds context",
        "turnDidNotEnd",
        #"{"stop_reason":"limit"}"#,
        #"{"stop_reason": "contextFull"}"#,
    ])
    func v5RejectsUndeliverableWire(_ marker: String) {
        #expect(CaptureValidity.checkV5(marker).status == .fail)
    }

    @Test func v6RejectsCommentaryBeforeFence() {
        let wire = "{\"t\":\"text\",\"s\":\"# `app.py`\\nHere is the file:\\n```python\\nprint(1)\\n\",\"ts\":1}\n{\"t\":\"ready\",\"ts\":2}"
        let check = CaptureValidity.checkV6(wire)
        #expect(check.status == .fail)
        #expect(check.detail ==
                "1 heading(s) had fenced code discarded in favour of commentary: ['app.py']")
    }

    @Test func v6AcceptsImmediateFenceAndIgnoresUnknownHeadings() {
        let wire = "{\"t\":\"text\",\"s\":\"# `app.py`\\n```python\\nprint(1)\\n```\\n# `notes.md`\\nCommentary\\n```\\n\",\"ts\":1}\n{\"t\":\"ready\",\"ts\":2}"
        #expect(CaptureValidity.checkV6(wire).status == .pass)
    }

    @Test func cleanWirePassesBothChecks() {
        let wire = "{\"t\":\"text\",\"s\":\"# `app.py`\\n```python\\nprint(1)\\n```\\n\",\"ts\":1}\n{\"t\":\"ready\",\"stop_reason\":\"eos\",\"ts\":2}"
        let result = CaptureValidity.audit(wire: wire)
        #expect(result.v5.status == .pass)
        #expect(result.v6.status == .pass)
    }
}
