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


def tool(name, ok=True, text="", **args):
    return {"name": name, "args": [[k, v] for k, v in args.items()], "result_ok": ok, "result_text": text}


def prompt(*tools, answered=True, index=0):
    """One prompt from tool dicts; an answer step closes it when `answered`."""
    steps = [sl.Step(i, index, t, None, 1) for i, t in enumerate(tools)]
    if answered:
        steps.append(sl.Step(len(steps), index, None, None, 1))
    return sl.Prompt(index, "p", steps, answered)


def rules(flags):
    return [(f.step, f.rule) for f in flags]


class FlagTests(unittest.TestCase):
    def setUp(self):
        self.session = sl.load(FIXTURE)
        self.flags = sl.flags(sl.steps(self.session), self.session.events)

    def test_123136_flags(self):
        got = [(f.prompt, f.step, f.rule, f.evidence) for f in self.flags]
        self.assertEqual([g[:3] for g in got], [(1, 17, "F1"), (3, 36, "U1"), (3, 37, "U1")])
        self.assertIn("unknown tool: run", got[0][3])
        self.assertEqual(got[1][3], "already_shown")

    def test_123136_reread_after_edit_not_flagged(self):
        flagged = {f.step for f in self.flags}
        self.assertNotIn(18, flagged)
        self.assertNotIn(30, flagged)

    def test_123136_guard_totals_agree(self):
        self.assertIsNone(sl.guard_mismatch(self.flags, self.session.capture["loop_guards"]))

    def test_guard_mismatch_reported(self):
        counted = dict(self.session.capture["loop_guards"], already_shown=3)
        message = sl.guard_mismatch(self.flags, counted)
        self.assertIn("already_shown", message)
        self.assertIn("found 2", message)
        self.assertIn("counted 3", message)

    def test_loop_refusal_is_u1_not_f1(self):
        text = "Tool error: not run. You already made this exact call 3 times in a row and got the same result each time."
        self.assertEqual(rules(sl.flags([prompt(tool("read", ok=False, text=text, path="a"))], [])), [(0, "U1")])

    def test_plain_tool_error_is_f1(self):
        text = "Tool error: unknown tool: x"
        self.assertEqual(rules(sl.flags([prompt(tool("x", ok=False, text=text))], [])), [(0, "F1")])

    def test_repeat_without_edit_flagged(self):
        p = prompt(tool("read", path="a.swift"), tool("read", path="a.swift"))
        self.assertEqual(rules(sl.flags([p], [])), [(1, "U2")])

    def test_repeat_after_edit_not_flagged(self):
        p = prompt(tool("read", path="a.swift"), tool("edit", path="a.swift"), tool("read", path="a.swift"))
        self.assertEqual(rules(sl.flags([p], [])), [])

    def test_prompt_without_answer_flagged(self):
        self.assertEqual(rules(sl.flags([prompt(tool("ls", path="."), answered=False)], [])), [(None, "F3")])

    def test_prompt_with_answer_not_flagged(self):
        self.assertEqual(rules(sl.flags([prompt(tool("ls", path="."))], [])), [])

    def test_native_end_not_ok_flagged(self):
        events = [{"kind": "native_end", "turn": 0, "status": "error"}]
        self.assertEqual(rules(sl.flags([prompt()], events)), [(None, "F2")])

    def test_native_end_ok_not_flagged(self):
        events = [{"kind": "native_end", "turn": 0, "status": "ok"}]
        self.assertEqual(rules(sl.flags([prompt()], events)), [])

    def test_host_results_never_flagged(self):
        p = prompt(tool("host_results", held="1"), tool("host_results", held="1"))
        self.assertEqual(rules(sl.flags([p], [])), [])


def checkpoint(seq, prefill_tokens, sync_ms, eval_count=0, eval_ms=0.0, turn=0):
    return {"kind": "checkpoint", "seq": seq, "turn": turn, "snapshot": {
        "prefill_tokens": prefill_tokens, "sync_ms": sync_ms, "eval_count": eval_count, "eval_ms": eval_ms}}


class SummaryTests(unittest.TestCase):
    def setUp(self):
        self.session = sl.load(FIXTURE)
        self.prompts = sl.steps(self.session)

    def test_per_pause_rates_are_deltas(self):
        rates = sl.pause_rates([checkpoint(1, 955, 1950.4), checkpoint(2, 1000, 2744.5)])
        self.assertAlmostEqual(rates[1].prefill_tps, 45 / 794.1 * 1000, places=1)
        self.assertLess(rates[1].prefill_tps, 100)  # the cumulative average would be ~364

    def test_zero_delta_has_no_rate(self):
        rates = sl.pause_rates([checkpoint(1, 955, 1950.4), checkpoint(2, 1000, 1950.4)])
        self.assertIsNone(rates[1].prefill_tps)

    def test_no_new_tokens_has_no_rate(self):
        rates = sl.pause_rates([checkpoint(1, 955, 1950.4), checkpoint(2, 955, 1990.0)])
        self.assertIsNone(rates[1].prefill_tps)

    def test_123136_pause_rates(self):
        rates = sl.pause_rates(self.session.events)
        self.assertEqual(len(rates), 23)
        self.assertAlmostEqual(rates[0].prefill_tps, 955 / 1950.416958 * 1000, places=1)

    def test_123136_summary(self):
        rows = sl.summary(self.session, self.prompts)
        self.assertEqual(list(rows), ["Time", "Context and speed", "Work", "Ending", "Health"])
        self.assertIn("1,021 → 7,300", rows["Context and speed"])
        self.assertIn("read 10, edit 4, ls 3, grep 2, run 1", rows["Work"])
        self.assertIn("rejected: run (unknown-tool)", rows["Work"])
        self.assertNotIn("host_results", rows["Work"])

    def test_123136_signals(self):
        signals = sl.signals(self.session, self.prompts)
        self.assertEqual(signals["loop_guards"]["already_shown"], 2)
        self.assertEqual(signals["syncs_under_1ms"], 19)
        self.assertEqual(signals["host_results_steps"], 16)
        self.assertEqual(signals["result_bytes"], (8997, 8997))


if __name__ == "__main__":
    unittest.main()
