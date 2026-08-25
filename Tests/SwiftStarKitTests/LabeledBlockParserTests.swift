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

    @Test func headingWithNoFenceIsDroppedAndNotCarriedForward() {
        let text = "### `app.py`\nsome prose, no fence follows\n### `models.py`\n```\nok = 1\n```\n"
        let r = LabeledBlockParser.parse(text, writableFiles: allowlist)
        #expect(r.files.count == 1)
        #expect(r.files[0].path == "models.py")
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

    @Test func noBacktickHeadingIsNotAHeading() {
        // A prose line like "### app.py" (no backticks) is not a label.
        #expect(LabeledBlockParser.parse("### app.py\n```\nx=1\n```\n", writableFiles: allowlist).files.isEmpty)
    }
}
