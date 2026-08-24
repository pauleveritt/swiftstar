import Testing
import Foundation
@testable import SwiftStarKit

struct ThinkHarvestTests {
    static let allowlist = ["app.py", "models.py", "templates/base.html", "templates/home.html"]

    /// The model names the file in prose, then emits the block. That pairing is
    /// the only thing that makes harvest mechanical.
    @Test func harvestsBlockLabelledByPrecedingProse() {
        let think = """
        Let me write models.py:

        ```python
        complaints: list = []
        ```
        """
        let files = ThinkHarvest.harvest(think: think, writableFiles: Self.allowlist)
        #expect(files["models.py"] == "complaints: list = []\n")
    }

    /// A block whose nearest named file is outside the writable grant must be
    /// dropped, not guessed at — harvest may never widen the packet's scope.
    @Test func ignoresBlockNamingFileOutsideTheGrant() {
        let think = """
        Now I edit /etc/passwd:

        ```
        root::0:0
        ```
        """
        #expect(ThinkHarvest.harvest(think: think, writableFiles: Self.allowlist).isEmpty)
    }

    /// Drafts refine across the stream, so the last complete draft of a file
    /// wins — matching how the model itself treats its later drafts.
    @Test func laterDraftOfSameFileWins() {
        let think = """
        First pass at app.py:

        ```python
        app = 1
        ```

        On reflection, app.py should be:

        ```python
        app = 2
        ```
        """
        let files = ThinkHarvest.harvest(think: think, writableFiles: Self.allowlist)
        #expect(files["app.py"] == "app = 2\n")
    }

    /// An unterminated trailing block is the token cap cutting mid-draft. A
    /// truncated file is worse than no file — it would overwrite a good earlier
    /// draft with a broken one.
    @Test func dropsUnterminatedTrailingBlock() {
        let think = """
        app.py first:

        ```python
        app = "good"
        ```

        Let me re-check app.py:

        ```python
        app = "trunc
        """
        let files = ThinkHarvest.harvest(think: think, writableFiles: Self.allowlist)
        #expect(files["app.py"] == "app = \"good\"\n")
    }

    /// Found by running the harvester against a real capture: `app.py` occurs
    /// *inside* `tests/test_app.py`, at a later index, so a plain substring
    /// search hands the test file's body to `app.py` — which then fails to
    /// import itself. The label must match on a boundary, not a substring.
    @Test func doesNotMatchAPathNestedInsideALongerFilename() {
        let think = """
        ### `tests/test_app.py`

        ```python
        from app import app
        ```
        """
        let files = ThinkHarvest.harvest(
            think: think, writableFiles: ["app.py", "tests/test_app.py"])
        #expect(files["tests/test_app.py"] == "from app import app\n")
        #expect(files["app.py"] == nil)
    }

    @Test func returnsNothingWhenNoBlocksPresent() {
        #expect(ThinkHarvest.harvest(think: "I am still deliberating about app.py.",
                                     writableFiles: Self.allowlist).isEmpty)
    }
}
