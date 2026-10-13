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
