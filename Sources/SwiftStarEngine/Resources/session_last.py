"""The last ds4-engine session as a report: flagged steps, a summary and raw
signals, read from the session directory with no model call (AN.1).

Standard library only, run as `python3 -I`. The engine owns these files, and
this moves into ds4-engine as `ds4-dogfood last` once its rows settle (AN.4).
"""

from __future__ import annotations

import collections
import json
import statistics
from dataclasses import dataclass
from pathlib import Path

# The schema versions this was written against. Another version warns, and
# the report is still attempted.
CAPTURE_SCHEMA = 18
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
    name = Path(receipt.get("capture_path") or "").name
    if not name:
        raise LoadError(f"{directory / 'receipt.json'} names no capture")
    capture = _json(directory / name)
    events = []
    for line in _read(directory / "operator-events.jsonl").splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            break  # a torn last line
    diff_path = directory / "candidate.diff"
    diff = _read(diff_path) if diff_path.exists() else ""
    warnings = []
    if capture.get("schema_version") != CAPTURE_SCHEMA:
        warnings.append(f"capture schema_version {capture.get('schema_version')}, written for {CAPTURE_SCHEMA}")
    versions = {e.get("schema_version") for e in events} - {EVENTS_SCHEMA}
    if versions:
        warnings.append(f"events schema_version {sorted(map(str, versions))}, written for {EVENTS_SCHEMA}")
    return Session(directory, events, receipt, capture, diff, warnings)


def steps(session: Session) -> list[Prompt]:
    """The capture's steps grouped into prompts: an answer step closes one."""
    texts = [u.get("text", "") for u in session.capture.get("user_turns") or []]
    prompts: list[Prompt] = []
    current: list[Step] = []
    for i, turn in enumerate(session.capture.get("turns") or []):
        step = Step(i, len(prompts), turn.get("tool"), turn.get("context_used"), len(turn.get("tokens") or []))
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

CHECKS = ("F1", "F2", "F3", "U1", "U2")
BOOKKEEPING = "host_results"
WRITES = ("edit", "write")


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
    refusal fails, but the engine refused it as waste. F2 and F3 flag a
    prompt."""
    found: list[Flag] = []
    seen: set[tuple] = set()  # (name, args) since the path was last written
    for p in prompts:
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
                seen = {k for k in seen if dict(k[1]).get("path") != args.get("path")}
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
        "loop_guards": cap.get("loop_guards") or {},
        "constraint": {k: constraint.get(k) for k in ("masked_token_count", "removed_probability_mass", "forbidden_argmax")},
        "think_inert_openers": cap.get("think_inert_openers"),
        "citation_corrections": sum(len(e.get("citation_corrections") or []) for e in _of(ev, "answer")),
        "prefix_cache": dict(collections.Counter(e.get("outcome") for e in _of(ev, "prefix_cache"))),
        "syncs_under_1ms": sum(1 for s in (cap.get("timing") or {}).get("per_sync_ms") or [] if (s.get("ms") or 0) < 1),
        "dflash": (start.get("dflash") or {}).get("label"),
        "host_results_steps": sum(1 for t in tools if t.get("name") == BOOKKEEPING),
        "result_bytes": (sum(t.get("bytes_total") or 0 for t in tools), sum(t.get("bytes_shown") or 0 for t in tools)),
    }
