"""Tests for record-engine-fixture.py's file handling (SU.6g, D5).

No engine: the recordings are files made here, and the one subprocess is
`/bin/echo`.
"""

import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("recorder", ROOT / "Tools/record-engine-fixture.py")
recorder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(recorder)


class Recordings(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="recorder-test-"))
        self.out = str(self.dir / "relaunch-rewind.ndjson")
        self.resumed = str(self.dir / "resumed.ndjson")
        for path in (self.out, self.resumed):
            Path(path).write_text("old\n")
            Path(path + ".tmp").write_text("new\n")

    def test_a_failed_first_recording_keeps_neither(self):
        recorder.settle_pair(self.out, self.resumed, code=1, resumed_code=0)
        self.assertEqual(Path(self.out).read_text(), "old\n")
        self.assertEqual(Path(self.resumed).read_text(), "old\n")
        self.assertFalse(Path(self.out + ".tmp").exists())
        self.assertFalse(Path(self.resumed + ".tmp").exists())

    def test_a_failed_resume_keeps_neither(self):
        recorder.settle_pair(self.out, self.resumed, code=0, resumed_code=2)
        self.assertEqual(Path(self.out).read_text(), "old\n")
        self.assertEqual(Path(self.resumed).read_text(), "old\n")

    def test_both_good_keeps_both(self):
        recorder.settle_pair(self.out, self.resumed, code=0, resumed_code=0)
        self.assertEqual(Path(self.out).read_text(), "new\n")
        self.assertEqual(Path(self.resumed).read_text(), "new\n")

    def test_output_that_is_not_json_leaves_no_tmp(self):
        out = str(self.dir / "broken.ndjson")
        with self.assertRaises(ValueError):
            recorder.run("/bin/echo", ["not json"], None, out, lambda line, send: None)
        self.assertFalse(Path(out + ".tmp").exists())


if __name__ == "__main__":
    unittest.main()
