"""Tests for record-engine-fixture.py's file handling (SU.6g, D5).

No engine: the recordings are files made here, and the one subprocess is
`/bin/echo`.
"""

import gc
import importlib.util
import tempfile
import warnings
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

    def test_a_raising_resume_drops_the_first_half_too(self):
        # SU.17: the first recording's .tmp went nowhere when the resumed run raised.
        with self.assertRaises(ValueError):
            recorder.run_resumed("/bin/echo", ["not json"], None, self.out, self.resumed)
        self.assertFalse(Path(self.out + ".tmp").exists())
        self.assertFalse(Path(self.resumed + ".tmp").exists())
        self.assertEqual(Path(self.out).read_text(), "old\n")

    def test_a_run_closes_its_pipes(self):
        # SU.17: no ResourceWarning for an unclosed pipe, on success or failure.
        out = str(self.dir / "pipes.ndjson")
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            recorder.run("/bin/echo", ['{"kind": "input"}'], None, out, lambda line, send: None)
            with self.assertRaises(ValueError):
                recorder.run("/bin/echo", ["not json"], None, out, lambda line, send: None)
            gc.collect()
        self.assertEqual([w for w in caught if issubclass(w.category, ResourceWarning)], [])


if __name__ == "__main__":
    unittest.main()
