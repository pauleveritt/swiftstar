"""The last ds4-engine session as a report: flagged steps, a summary and raw
signals, read from the session directory with no model call (AN.1).

Standard library only, run as `python3 -I`. The engine owns these files, and
this moves into ds4-engine as `ds4-dogfood last` once its rows settle (AN.4).
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

# The schema versions this was written against. Another version warns, and
# the report is still attempted. Capture 19 only adds the `speculation`
# record (ds4-engine crates/ds4-capture/src/lib.rs:1395-1407), unread here;
# 17 has no `loop_guards` (18 added it), so its guard check is skipped.
CAPTURE_SCHEMAS = (17, 18, 19)
EVENTS_SCHEMA = 1


class LoadError(Exception):
    """A session file is missing or unreadable."""


@dataclass
class Session:
    directory: Path
    events: list[dict]
    receipt: dict
    capture: dict
    diff: str
    warnings: list[str]


@dataclass
class Step:
    """One capture turn: a model pause. With no `tool`, it is an answer."""

    index: int
    prompt: int
    tool: dict | None
    context_used: int | None
    tokens: int


@dataclass
class Prompt:
    index: int
    text: str
    steps: list[Step]
    answered: bool


def _read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as e:
        raise LoadError(f"cannot read {path}: {e.strerror}") from None


def _json(path: Path):
    try:
        return json.loads(_read(path))
    except json.JSONDecodeError as e:
        raise LoadError(f"{path} is not JSON: {e}") from None


def load(directory: Path) -> Session:
    """Read a session directory. The capture is found by its file name inside
    the directory, so a moved directory still loads."""
    directory = Path(directory)
    receipt = _json(directory / "receipt.json")
    warnings = []
    name = Path(receipt.get("capture_path") or "").name
    if name:
        capture = _json(directory / name)
    else:
        # The engine writes no capture for a session that never reached the
        # model (`capture_status` "missing"), such as one rewound to 0.
        capture = {"schema_version": CAPTURE_SCHEMAS[-1], "turns": [], "user_turns": []}
        warnings.append(f"no capture (capture_status {receipt.get('capture_status')}): the model was never run")
    events = []
    for line in _read(directory / "operator-events.jsonl").splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            break  # a torn last line
    diff_path = directory / "candidate.diff"
    diff = _read(diff_path) if diff_path.exists() else ""
    if capture.get("schema_version") not in CAPTURE_SCHEMAS:
        known = " and ".join(map(str, CAPTURE_SCHEMAS))
        warnings.append(f"capture schema_version {capture.get('schema_version')}, written for {known}")
    versions = {e.get("schema_version") for e in events} - {EVENTS_SCHEMA}
    if versions:
        warnings.append(f"events schema_version {sorted(map(str, versions))}, written for {EVENTS_SCHEMA}")
    return Session(directory, events, receipt, capture, diff, warnings)


def steps(session: Session) -> list[Prompt]:
    """The capture's steps grouped into prompts. Each `user_turns` entry's
    `turn_index` is the step its prompt starts at, so a prompt cancelled
    before any step still counts. A capture without them falls back to
    "an answer step closes a prompt"."""
    user_turns = session.capture.get("user_turns") or []
    turns = session.capture.get("turns") or []
    starts = [u.get("turn_index") for u in user_turns]
    if starts and all(isinstance(s, int) for s in starts):
        prompts = []
        for i, (u, start) in enumerate(zip(user_turns, starts)):
            end = starts[i + 1] if i + 1 < len(starts) else len(turns)
            own = [_step(j, i, turns[j]) for j in range(start, min(end, len(turns)))]
            prompts.append(Prompt(i, u.get("text", ""), own, any(s.tool is None for s in own)))
        return prompts
    return _by_answers(session)


def _step(i: int, prompt: int, turn: dict) -> Step:
    return Step(i, prompt, turn.get("tool"), turn.get("context_used"), len(turn.get("tokens") or []))


def _by_answers(session: Session) -> list[Prompt]:
    texts = [u.get("text", "") for u in session.capture.get("user_turns") or []]
    prompts: list[Prompt] = []
    current: list[Step] = []
    for i, turn in enumerate(session.capture.get("turns") or []):
        step = _step(i, len(prompts), turn)
        current.append(step)
        if step.tool is None:
            prompts.append(Prompt(len(prompts), _text(texts, len(prompts)), current, True))
            current = []
    if current:
        prompts.append(Prompt(len(prompts), _text(texts, len(prompts)), current, False))
    return prompts


def _text(texts: list[str], i: int) -> str:
    return texts[i] if i < len(texts) else ""


# The engine's guard notices, as a tool result begins, by `loop_guards` kind
# (ds4-engine 5451cd7d). `answer_cap` and `self_copy` act on sampling, not on
# a tool result, so no step carries them.
GUARD_MARKERS = {
    # crates/ds4-native/src/shown.rs:209
    "already_shown": "[Already shown above:",
    # crates/ds4-native/src/loop_guards.rs:78
    "repeated_call": "Tool error: not run. You already made this exact call",
    # crates/ds4-native/src/loop_guards.rs:81-86
    "call_cycle": "Tool error: not run. Your last",
}

CHECKS = ("F1", "F2", "F3", "U1", "U2", "R1")
# R1: one pause's prefill took longer than this. A full refill of 37,764
# tokens after a rewind took 242 s on the 27B (AN.2's first attempt).
SLOW_SYNC_MS = 10_000
BOOKKEEPING = "host_results"
WRITES = ("edit", "write")
SEARCHES = ("grep", "ls")


@dataclass
class Flag:
    """A failed (F) or useless (U) step; `step` is None for a whole prompt."""

    prompt: int
    step: int | None
    rule: str
    evidence: str


def _args(t: dict) -> dict:
    return {k: v for k, v in t.get("args") or []}


def _guard(text: str) -> str | None:
    return next((kind for kind, mark in GUARD_MARKERS.items() if text.startswith(mark)), None)


def flags(prompts: list[Prompt], events: list[dict]) -> list[Flag]:
    """Each step gets at most one flag, in the order U1, F1, U2: a loop
    refusal fails, but the engine refused it as waste. F2, F3 and R1 flag a
    prompt."""
    found: list[Flag] = []
    seen: set[tuple] = set()  # (name, args) since the path was last written
    slow = _slow_syncs(events)
    for p in prompts:
        for tokens, ms in slow.get(p.index, []):
            found.append(Flag(p.index, None, "R1", f"prefill {tokens:,} tokens in {ms / 1000:.1f} s"))
        for s in p.steps:
            t = s.tool
            if t is None or t.get("name") == BOOKKEEPING:
                continue
            text = t.get("result_text") or ""
            args = _args(t)
            key = (t.get("name"), tuple(sorted(args.items())))
            if (kind := _guard(text)) is not None:
                found.append(Flag(p.index, s.index, "U1", kind))
            elif t.get("result_ok") is False:
                found.append(Flag(p.index, s.index, "F1", text.splitlines()[0] if text else "failed"))
            elif key in seen:
                found.append(Flag(p.index, s.index, "U2", f"repeat of {t.get('name')} {args.get('path', '')}".rstrip()))
            if t.get("name") in WRITES:
                # A write makes re-reading that path, and searching again,
                # verification rather than waste.
                seen = {k for k in seen if dict(k[1]).get("path") != args.get("path") and k[0] not in SEARCHES}
            else:
                seen.add(key)
        for e in events:
            if e.get("turn") != p.index:
                continue
            if e.get("kind") == "native_end" and e.get("status") != "ok":
                found.append(Flag(p.index, None, "F2", f"native_end status {e.get('status')}"))
            elif e.get("kind") == "error":
                found.append(Flag(p.index, None, "F2", str(e.get("text") or "error")))
        if not p.answered:
            found.append(Flag(p.index, None, "F3", "no answer"))
    return found


def _slow_syncs(events: list[dict]) -> dict[int, list[tuple[int, float]]]:
    """Pauses whose own prefill (the delta of the session-cumulative
    `sync_ms`) took over `SLOW_SYNC_MS`, by prompt, as (tokens, ms)."""
    slow: dict[int, list[tuple[int, float]]] = {}
    last_tokens, last_ms = 0, 0.0
    for e in _of(events, "checkpoint"):
        snap = e.get("snapshot") or {}
        tokens, ms = snap.get("prefill_tokens") or 0, snap.get("sync_ms") or 0.0
        if ms - last_ms > SLOW_SYNC_MS:
            slow.setdefault(e.get("turn", 0), []).append((tokens - last_tokens, ms - last_ms))
        last_tokens, last_ms = tokens, ms
    return slow


def guard_mismatch(found: list[Flag], loop_guards: dict) -> str | None:
    """Guard notices found in results against the engine's own counts, so a
    notice whose wording this doesn't know shows up as a difference."""
    diffs = []
    for kind in GUARD_MARKERS:
        n = sum(1 for f in found if f.rule == "U1" and f.evidence == kind)
        counted = loop_guards.get(kind, 0)
        if n != counted:
            diffs.append(f"{kind}: found {n}, counted {counted}")
    return "; ".join(diffs) or None


@dataclass
class PauseRate:
    """One pause's own rates. Checkpoint timings are session-cumulative, so
    a pause's rate is the delta from the checkpoint before it (from zero for
    the first). No elapsed time gives no rate, not an infinite one, and no
    new tokens gives no rate, not a zero one: such a pause did no prefill."""

    seq: int
    prompt: int
    prefill_tps: float | None
    gen_tps: float | None
    context_used: int | None


def _rate(tokens: float, ms: float) -> float | None:
    return tokens / ms * 1000 if ms > 0 and tokens > 0 else None


def pause_rates(events: list[dict]) -> list[PauseRate]:
    rates = []
    last = {"prefill_tokens": 0, "sync_ms": 0.0, "eval_count": 0, "eval_ms": 0.0}
    for e in events:
        if e.get("kind") != "checkpoint":
            continue
        snap = e.get("snapshot") or {}
        now = {k: snap.get(k) or 0 for k in last}
        rates.append(PauseRate(
            e.get("seq", 0), e.get("turn", 0),
            _rate(now["prefill_tokens"] - last["prefill_tokens"], now["sync_ms"] - last["sync_ms"]),
            _rate(now["eval_count"] - last["eval_count"], now["eval_ms"] - last["eval_ms"]),
            snap.get("context_used"),
        ))
        last = now
    return rates


def _secs(ms: float | None) -> str:
    if ms is None:
        return "—"
    s = ms / 1000
    if s < 60:
        return f"{s:.1f} s"
    return f"{int(s // 60)} m {int(s % 60)} s"


def _tps(v: float | None) -> str:
    return "—" if v is None else f"{v:,.0f}"


def _of(events: list[dict], kind: str) -> list[dict]:
    return [e for e in events if e.get("kind") == kind]


def _spread(values: list[float | None]) -> str:
    """first / median / last of the pauses that have a rate."""
    vs = [v for v in values if v is not None]
    if not vs:
        return "—"
    return f"{_tps(vs[0])} / {_tps(statistics.median(vs))} / {_tps(vs[-1])}"


def _tools(prompts: list[Prompt]) -> list[dict]:
    return [s.tool for p in prompts for s in p.steps if s.tool is not None]


def _compactions(events: list[dict]) -> int:
    snaps = [e.get("snapshot") or {} for e in events if e.get("kind") in ("checkpoint", "closed")]
    return max((s.get("compactions") or 0 for s in snaps), default=0)


def summary(session: Session, prompts: list[Prompt]) -> dict[str, str]:
    """The summary rows, one per question (spec §2.2)."""
    ev = session.events
    wall = max((e.get("elapsed_ms") or 0 for e in ev), default=None)
    ready = next(iter(_of(ev, "candidate_ready")), {}).get("elapsed_ms")
    caches = [f"{c.get('outcome')} {_secs(c.get('fill_ms') or c.get('load_ms'))}" for c in _of(ev, "prefix_cache")]
    native = [e.get("duration_ms") or 0 for e in _of(ev, "native_end")]
    tool_ms = [e.get("duration_ms") or 0 for e in _of(ev, "tool_end")]
    time = (
        f"wall {_secs(wall)}; start-up: candidate ready at {_secs(ready)}"
        + (f", prefix cache {', '.join(caches)}" if caches else "")
        + f"; model {_secs(sum(native))} over {len(native)} calls; tools {_secs(sum(tool_ms))} over {len(tool_ms)} calls"
    )

    contexts = [s.context_used for p in prompts for s in p.steps if s.context_used is not None]
    rates = pause_rates(ev)
    slowest = min((r for r in rates if r.prefill_tps is not None), key=lambda r: r.prefill_tps, default=None)
    speed = (
        (f"ctx {contexts[0]:,} → {contexts[-1]:,}" if contexts else "ctx —")
        + f"; prefill tok/s first / median / last {_spread([r.prefill_tps for r in rates])}"
        + f"; generation tok/s {_spread([r.gen_tps for r in rates])}"
        + (f"; slowest prefill {_tps(slowest.prefill_tps)} at pause seq {slowest.seq} (prompt {slowest.prompt})" if slowest else "")
    )

    names = collections.Counter(t.get("name") for t in _tools(prompts) if t.get("name") != BOOKKEEPING)
    rejected = collections.Counter(f"{e.get('name')} ({e.get('reason')})" for e in _of(ev, "tool_rejected"))
    files = sum(1 for line in session.diff.splitlines() if line.startswith("diff --git "))
    work = (
        f"{len(prompts)} prompts, {sum(len(p.steps) for p in prompts)} steps; tools: "
        + (", ".join(f"{n} {c}" for n, c in names.most_common()) or "none")
        + "; rejected: " + (", ".join(f"{r} ×{c}" if c > 1 else r for r, c in rejected.items()) or "none")
        + f"; files changed: {files}"
    )

    closed = next(iter(_of(ev, "closed")), None)
    ending = (
        ", ".join(f"{p.index}: {'answer' if p.answered else 'no answer'}" for p in prompts) or "no prompts"
    ) + f"; outcome {session.capture.get('outcome', '—')}" + (
        f"; closed, telemetry_ok {closed.get('telemetry_ok')}" if closed else "; not closed"
    )

    mem = _of(ev, "memory")
    peak = max(mem, key=lambda e: e.get("gpu_allocated_bytes") or 0, default=None)
    gib = 2**30
    health = (
        f"GPU peak {peak['gpu_allocated_bytes'] / gib:.1f} of {peak['gpu_budget_bytes'] / gib:.1f} GiB"
        if peak and peak.get("gpu_budget_bytes") else "GPU —"
    ) + f"; compactions {_compactions(ev)}; errors {len(_of(ev, 'error'))}"

    return {"Time": time, "Context and speed": speed, "Work": work, "Ending": ending, "Health": health}


def signals(session: Session, prompts: list[Prompt]) -> dict[str, object]:
    """Counters only this architecture records, raw: which ones ever move is
    what AN.1 is for."""
    cap, ev = session.capture, session.events
    constraint = cap.get("constraint") or {}
    tools = _tools(prompts)
    start = next(iter(_of(ev, "session")), {})
    return {
        "loop_guards": cap.get("loop_guards"),  # None before schema 18
        "constraint": {k: constraint.get(k) for k in ("masked_token_count", "removed_probability_mass", "forbidden_argmax")},
        "think_inert_openers": cap.get("think_inert_openers"),
        "citation_corrections": sum(len(e.get("citation_corrections") or []) for e in _of(ev, "answer")),
        "prefix_cache": dict(collections.Counter(e.get("outcome") for e in _of(ev, "prefix_cache"))),
        "syncs_under_1ms": sum(1 for s in (cap.get("timing") or {}).get("per_sync_ms") or [] if (s.get("ms") or 0) < 1),
        "dflash": (start.get("dflash") or {}).get("label"),
        "host_results_steps": sum(1 for t in tools if t.get("name") == BOOKKEEPING),
        "result_bytes": (sum(t.get("bytes_total") or 0 for t in tools), sum(t.get("bytes_shown") or 0 for t in tools)),
    }


def _did(step: Step | None) -> str:
    if step is None:
        return "prompt"
    if step.tool is None:
        return "answer"
    args = _args(step.tool)
    return f"{step.tool.get('name')} {args.get('path') or args.get('pattern') or ''}".rstrip()


def report(session: Session) -> dict:
    """Everything the Markdown shows, as plain data (`--json`)."""
    prompts = steps(session)
    by_index = {s.index: s for p in prompts for s in p.steps}
    found = flags(prompts, session.events)
    start = next(iter(_of(session.events, "session")), {})
    resumed = next(iter(_of(session.events, "resumed")), {})
    warnings = list(session.warnings)
    guards = session.capture.get("loop_guards")
    if guards is not None and (mismatch := guard_mismatch(found, guards)) is not None:
        warnings.append(f"guard notices against loop_guards: {mismatch}")
    return {
        "header": {
            "id": session.directory.name,
            "path": str(session.directory),
            "model": start.get("model_id"),
            "context_size": start.get("context_size"),
            "wall_ms": max((e.get("elapsed_ms") or 0 for e in session.events), default=None),
            "outcome": session.capture.get("outcome"),
            "resumed_from": Path(start["resumed_from"]).name if start.get("resumed_from") else None,
            "rewound_to": resumed.get("rewound_to"),
        },
        "flags": [
            dict(prompt=f.prompt, step=f.step, rule=f.rule, evidence=f.evidence,
                 did=_did(by_index.get(f.step) if f.step is not None else None))
            for f in found
        ],
        "checks": list(CHECKS),
        "summary": summary(session, prompts),
        "signals": signals(session, prompts),
        "warnings": warnings,
    }


def cell(text: str, limit: int = 200) -> str:
    """One table cell: whitespace runs with a newline become a space and `|`
    is escaped, with the backslashes before it doubled first, so `a\\|b`
    can't split the row either (mellum-worker's `cell()`)."""
    text = re.sub(r"\s*\r?\n\s*", " ", str(text)).strip()
    if len(text) > limit:
        text = text[: limit - 1] + "…"
    return re.sub(r"(\\*)\|", lambda m: m.group(1) * 2 + "\\|", text)


def markdown(r: dict) -> str:
    h = r["header"]
    head = f"**last**: {h['id']}, {h['model'] or '—'}, ctx {h['context_size'] or 0:,}, {_secs(h['wall_ms'])}, {h['outcome'] or '—'}"
    if h.get("resumed_from"):
        head += f", resumed from {h['resumed_from']}"
    if h.get("rewound_to") is not None:
        head += f", rewound to {h['rewound_to']}"
    lines = [head, ""]
    lines += [f"> warning: {w}" for w in r["warnings"]]
    if r["warnings"]:
        lines.append("")
    lines.append("### Flagged steps")
    lines.append("")
    if r["flags"]:
        lines += ["| Prompt | Step | Did | Rule | Evidence |", "|---|---|---|---|---|"]
        for f in r["flags"]:
            step = "—" if f["step"] is None else f["step"]
            lines.append(f"| {f['prompt']} | {step} | {cell(f['did'])} | {f['rule']} | {cell(f['evidence'])} |")
    else:
        lines.append(f"no flagged steps (checked {', '.join(r['checks'])})")
    lines += ["", "### Summary", "", "| Row | Value |", "|---|---|"]
    lines += [f"| {k} | {cell(v, 400)} |" for k, v in r["summary"].items()]
    lines += ["", "### Signals", ""]
    lines += [f"- {k}: {json.dumps(v)}" for k, v in r["signals"].items()]
    return "\n".join(lines) + "\n"


def _dogfood() -> str:
    found = os.environ.get("DS4_DOGFOOD") or shutil.which("ds4-dogfood")
    local = Path.home() / ".local/bin/ds4-dogfood"
    return found or (str(local) if local.exists() else "ds4-dogfood")


def newest_session(source: Path, run=subprocess.run, executable: str | None = None) -> Path:
    """The newest session of the repository holding `source`, by the engine's
    own rule (`ds4-dogfood sessions`)."""
    argv = [executable or _dogfood(), "sessions", "--json", "--source", str(source), "--limit", "1"]
    shown = " ".join(argv)
    try:
        done = run(argv, capture_output=True, text=True)
    except OSError as e:
        raise LoadError(f"cannot run {shown}: {e.strerror}") from None
    if done.returncode != 0:
        raise LoadError(f"{shown} failed: {(done.stderr or '').strip()[-300:]}")
    try:
        listed = json.loads(done.stdout)
    except json.JSONDecodeError:
        raise LoadError(f"{shown} did not print JSON") from None
    if not listed:
        raise LoadError(f"no session found for {source} ({shown})")
    return Path(listed[0]["path"])


def main(argv: list[str] | None = None, stdout=sys.stdout, stderr=sys.stderr) -> int:
    parser = argparse.ArgumentParser(prog="session_last.py", description=__doc__.split("\n\n")[0])
    parser.add_argument("--session", type=Path, help="a session directory (default: the newest for this repository)")
    parser.add_argument("--json", action="store_true", help="the report as JSON")
    args = parser.parse_args(argv)
    try:
        directory = args.session or newest_session(Path.cwd())
        r = report(load(directory))
    except LoadError as e:
        print(f"last: {e}", file=stderr)
        return 1
    stdout.write(json.dumps(r, indent=1) + "\n" if args.json else markdown(r))
    return 0


if __name__ == "__main__":
    sys.exit(main())
