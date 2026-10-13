"""The last ds4-engine session as a report: flagged steps, a summary and raw
signals, read from the session directory with no model call (AN.1).

Standard library only, run as `python3 -I`. The engine owns these files, and
this moves into ds4-engine as `ds4-dogfood last` once its rows settle (AN.4).
"""

from __future__ import annotations

import json
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
