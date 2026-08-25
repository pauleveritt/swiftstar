import Testing
import Foundation
@testable import SwiftStarKit

struct LabeledBlockParserTests {
    private let allowlist = ["app.py", "models.py", "templates/base.html", "tests/test_app.py"]

    @Test func harvestsALabeledBlock() {
        let text = "### `app.py`\n```python\nfrom fastapi import FastAPI\napp = FastAPI()\n```\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].path == "app.py")
        #expect(r.files[0].content == "from fastapi import FastAPI\napp = FastAPI()")
    }

    @Test func firstCompleteBlockWinsAndDuplicatesAreCounted() {
        let text = """
        ### `app.py`
        ```
        full = True
        ```
        some re-review prose
        ### `app.py`
        ```
        import x
        ```
        """
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].content == "full = True")
        #expect(r.duplicateCounts["app.py"] == 1)
    }

    @Test func headingInsideAFenceDoesNotFlipAttribution() {
        let text = """
        ### `app.py`
        ```
        # a heading-looking line inside code:
        ### `models.py`
        real = True
        ```
        """
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].path == "app.py")
        #expect(r.files[0].content.contains("### `models.py`"))
    }

    @Test func fenceWithoutHeadingIsIgnored() {
        let text = "```\norphan = True\n```\n"
        #expect(LabeledBlockParser.parse(text, writableFiles: allowlist).files.isEmpty)
    }

    @Test func unterminatedFenceIsDropped() {
        let text = "### `app.py`\n```\npartial = True\n"
        #expect(LabeledBlockParser.parse(text, writableFiles: allowlist).files.isEmpty)
    }

    @Test func headingWithNoFenceHarvestsItsBareBody() {
        // Lenient harvest (2026-08-25): an unfenced heading is a block whose body
        // runs to the next allowlisted heading. Mellum emits this form in ~half of
        // build runs (captures 20260825-171016, -171258) with complete file bodies.
        let text = "### `app.py`\nx = 1\n### `models.py`\n```\nok = 1\n```\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 2)
        #expect(r.files[0].path == "app.py")
        #expect(r.files[0].content == "x = 1")
        #expect(r.files[1].path == "models.py")
    }

    @Test func digitBearingInfoStringIsAccepted() {
        let text = "### `templates/base.html`\n```jinja2\n<div>x</div>\n```\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].path == "templates/base.html")
    }

    @Test func pathNormalization() {
        let text = "### `./app.py`\n```\nok = 1\n```\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].path == "app.py")
    }

    @Test func outOfGrantHeadingIsDroppedAndRecorded() {
        let text = "### `README.md`\n```\nsecret\n```\n### `app.py`\n```\nok = 1\n```\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].path == "app.py")
        #expect(r.outOfGrantHeadings == ["README.md"])
    }

    @Test func hashPathHeadingIsAccepted() {
        let text = "#app.py\n```\nfrom fastapi import FastAPI\n```\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].path == "app.py")
        #expect(r.files[0].content == "from fastapi import FastAPI")
    }

    @Test func hashPathCommentInsideFenceIsNotAHeading() {
        // Load-bearing: `#app.py` is a Python comment; a heading-looking line
        // inside a fenced body must never flip attribution.
        let text = "#app.py\n```\n#app.py\nx = 1\n```\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].content == "#app.py\nx = 1")
    }

    @Test func hashPathOutOfGrantIsRecorded() {
        let text = "#README.md\n```\nsecret\n```\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.isEmpty)
        #expect(r.outOfGrantHeadings == ["README.md"])
    }

    @Test func hashPathHeadingWithNoFenceHarvestsItsBareBody() {
        // The lenient tradeoff, stated plainly: with no fence to delimit it, prose
        // under an allowlisted heading is indistinguishable from file content and
        // is harvested as content. The fenced form remains the directive's ask.
        let r = LabeledBlockParser.parse("#app.py\nsome prose\n", writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].content == "some prose")
    }

    // MARK: - Lenient harvest (unfenced blocks)

    @Test func bareBodyIsHarvestedToEndOfText() {
        let text = "#app.py\nfrom fastapi import FastAPI\napp = FastAPI()\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].path == "app.py")
        #expect(r.files[0].content == "from fastapi import FastAPI\napp = FastAPI()")
    }

    @Test func bareBodyEndsAtTheNextAllowlistedHeadingWithTrailingBlanksTrimmed() {
        let text = "#app.py\nx = 1\n\n#models.py\ny = 2\n\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 2)
        #expect(r.files[0].content == "x = 1")
        #expect(r.files[1].content == "y = 2")
    }

    @Test func hashCommentInsideABareBodyDoesNotEndTheBlock() {
        // Load-bearing (capture 20260825-171258): `# In-memory storage` is a Python
        // comment sitting inside app.py's body. Only an *allowlisted* heading may
        // close a bare block, or every commented line would truncate the file.
        let text = "#app.py\nimport os\n# In-memory storage\ncomplaints = []\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].content == "import os\n# In-memory storage\ncomplaints = []")
    }

    @Test func outOfGrantBareHeadingIsRecordedAndItsBodyDropped() {
        let text = "#README.md\nsecret\n#app.py\nok = 1\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].path == "app.py")
        #expect(r.files[0].content == "ok = 1")
        #expect(r.outOfGrantHeadings == ["README.md"])
    }

    @Test func bareHeadingWithEmptyBodyIsDropped() {
        let text = "#app.py\n\n#models.py\ny = 2\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].path == "models.py")
    }

    @Test func aFenceStillWinsOverBareContentWhenItFollowsTheHeading() {
        let text = "#app.py\n```python\nx = 1\n```\ntrailing prose\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].content == "x = 1")
    }

    // MARK: - Repeated-heading abort

    @Test func repeatedHeadingAbortsTheHarvestAndIsRecorded() {
        // Capture 20260825-171057: Mellum re-emitted the same four headings eleven
        // times, running to the token wall. The first pass is the answer; everything
        // after the first repeat is degenerate resampling and must not be harvested.
        let text = "#app.py\nfirst = 1\n#models.py\nm = 1\n#app.py\nsecond = 2\n#templates/base.html\n<p>x</p>\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 2)
        #expect(r.files[0].content == "first = 1")
        #expect(r.files[1].path == "models.py")
        #expect(r.degenerateRepetition)
        #expect(r.duplicateCounts["app.py"] == 1)
        #expect(!r.files.contains { $0.path == "templates/base.html" })
    }

    @Test func repeatedFencedHeadingAlsoAborts() {
        let text = "### `app.py`\n```\nfirst = 1\n```\n### `app.py`\n```\nsecond = 2\n```\n### `models.py`\n```\nm = 1\n```\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].content == "first = 1")
        #expect(r.degenerateRepetition)
        #expect(!r.files.contains { $0.path == "models.py" })
    }

    @Test func aCleanHarvestIsNotFlaggedAsDegenerate() {
        let text = "#app.py\nx = 1\n#models.py\ny = 2\n"
        #expect(!LabeledBlockParser.parse(text, writableFiles: allowlist).degenerateRepetition)
    }
}
