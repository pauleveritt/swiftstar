"""Tests for session_last.py (AN.1), against a recorded session directory.

No subprocess and no network: `newest_session` takes an injected runner.
"""

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Sources/SwiftStarEngine/Resources"))

import session_last as sl  # noqa: E402

FIXTURE = ROOT / "fixtures/sessions/20261013-123136-swiftstar"
CAPTURE = "run-2032219913971169475-1791909283501.json"


class Copy:
    """A writable copy of the fixture, for tests that change a file."""

    def __enter__(self) -> Path:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name) / FIXTURE.name
        shutil.copytree(FIXTURE, self.dir)
        return self.dir

    def __exit__(self, *exc):
        self.tmp.cleanup()

    @staticmethod
    def edit_json(path: Path, change):
        data = json.loads(path.read_text())
        change(data)
        path.write_text(json.dumps(data))


class LoadTests(unittest.TestCase):
    def test_123136_accepted(self):
        session = sl.load(FIXTURE)
        prompts = sl.steps(session)
        self.assertEqual(len(prompts), 4)
        all_steps = [s for p in prompts for s in p.steps]
        self.assertEqual(len(all_steps), 40)
        self.assertEqual([s.index for s in all_steps if s.tool is None], [0, 20, 32, 39])
        self.assertEqual(session.warnings, [])

    def test_capture_found_by_basename(self):
        with Copy() as d:
            Copy.edit_json(d / "receipt.json", lambda r: r.update(capture_path=f"/elsewhere/{CAPTURE}"))
            self.assertEqual(len(sl.load(d).capture["turns"]), 40)

    def test_unknown_schema_warns(self):
        with Copy() as d:
            Copy.edit_json(d / CAPTURE, lambda c: c.update(schema_version=19))
            warnings = sl.load(d).warnings
            self.assertEqual(len(warnings), 1)
            self.assertIn("19", warnings[0])

    def test_missing_capture_raises(self):
        with Copy() as d:
            (d / CAPTURE).unlink()
            with self.assertRaises(sl.LoadError) as caught:
                sl.load(d)
            self.assertIn(CAPTURE, str(caught.exception))

    def test_session_without_prompts(self):
        session = sl.Session(directory=Path("x"), events=[], receipt={}, capture={"turns": [], "user_turns": []}, diff="", warnings=[])
        self.assertEqual(sl.steps(session), [])


if __name__ == "__main__":
    unittest.main()
