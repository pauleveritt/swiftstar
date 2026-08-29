# Handoff packet frontmatter schema — draft v1 (2026-08-24)

**Status:** implemented and green (367 tests). Every field below traces to a
specific observed failure; nothing is speculative surface area.

Built: [PacketFrontmatter.swift](../../../Sources/SwiftStarKit/PacketFrontmatter.swift)
(parser), [HandoffPacketValidator.swift](../../../Sources/SwiftStarKit/HandoffPacketValidator.swift),
and the `facts` / `redacts` / `role` / `sampling` fields on `HandoffPacket`.
Not yet wired into `DispatchPacketBuilder` or the agenttest harness — that is
the next step, and it must validate the **assembled** packet (see below).

Implemented rules: 3 (paths, absolute + `..`), 8 (redaction, across five
channels), 9 (non-empty task), plus empty-manifest and `turns`/`toolCalls` > 0.
The parser throws on an unrecognized `role`/`think` or a non-numeric budget
rather than defaulting. **Not** implemented: rules 1 (`packet` version), 2
(role enum — enforced at parse, not validate), 4 (`workspace.paths`), 6
(`sampling.maxTokens` > 0), 7 (`validation.command` required). `packet:` and
`workspace.paths` are currently parsed and discarded, so a `packet: 99` file is
accepted today.

**Parser hazard worth knowing:** `think: off` is a YAML 1.1 *boolean*. The
hand-rolled parser reads it as the string `"off"`, which is what the schema
means; swapping in a general YAML library later would silently coerce it to
`false` and change behavior. Either keep the constrained parser or quote the
value.

## Why

`HandoffPacket` ([Sources/SwiftStarKit/HandoffPacket.swift](../../../Sources/SwiftStarKit/HandoffPacket.swift))
is already a typed contract with `writableFiles`, `baselines`, validation
commands, and budgets, and `PoolOrchestrator` already enforces
`shellAllowed: false` plus a vetted `bash` limited to the packet's own
validation command. Three things are missing, and each one has a body count:

| gap | what it cost |
|---|---|
| no place to pin decisions | the `models.complaints` hidden contract; ~31k think-tokens of deliberation over an unstated fact |
| no record of what a packet withholds | spec contamination went untracked — the "L1" cell turned out to leak its own fix, so no valid L1 bug currently exists in the design |
| no sampling policy | `--nothink` had to be a global switch instead of per-role config |

## The authored/derived split

Frontmatter carries only what a human or the decompose role **authors**.
`baselines` are **derived** — read from the worktree at dispatch time, never
authored, never trusted from input. That invariant is already documented on
`FileBaseline` and this schema does not weaken it.

## Schema

```yaml
---
packet: 1                      # schema version, required
role: implement                # decompose | implement | repair — required
phase: 2                       # optional; multi-phase specs only

workspace:
  paths: workspace-relative    # the only accepted value in v1; declaring it
                               # is what makes an absolute path a hard error
  writable:                    # required, non-empty; the exact manifest
    - app.py
    - models.py
    - templates/complaints.html

budget:
  toolCalls: 30                # required, > 0
  turns: 1                     # required, > 0
  maxTokens: 8192              # required, > 0 — the `-n` cap

sampling:
  think: off                   # off | on | bounded — required
  temp: 0                      # required, >= 0

validation:
  command: "uv run --frozen pytest -q tests/test_app.py"
  selfTest: "uv run --frozen python -c 'import app'"   # optional

facts:                         # pinned decisions; the anti-ambiguity lever
  - "The in-memory list lives in models.py as module-level `complaints: list[Complaint]`."
  - "Complaint.timestamp uses field(default_factory=lambda: datetime.now(timezone.utc))."

redacts:                       # strings that MUST NOT appear in the rendered packet
  - "fastapi.responses"
  - "default_factory"
---

Implement phase 2 of the roadmap: the complaints board.
<the task text is the markdown body, not a YAML string>
```

## `redacts` — the contamination gate

This is the field that makes the experiment ladder honest. A packet declares
what it deliberately withholds, and the validator asserts those strings appear
**nowhere** in the rendered packet — task body, facts, or validation commands.

Without it, "L1" (diagnose from failure alone) silently degrades into "L3"
(fix is stated) the moment someone pastes a spec that happens to name the fix.
That already happened: the near-miss bug's fix sits verbatim in
`spec_context.md:54`, and it took a manual read to catch. With `redacts`, that
packet fails validation in milliseconds instead of producing a result that
looks like a pass.

**Validate the assembled packet, not the authored one.** `taskText` grows after
authoring — `DispatchPacketBuilder` appends the digest and loaded files via
`ContextAssembly`, and the agenttest harness concatenates the shared spec
context ([main.swift:163](../../../Sources/swiftstar-agenttest/main.swift:163)).
The historical leak was in precisely that appended content, so validating a
frontmatter-parsed packet — whose `taskText` is only the markdown body — would
miss the exact failure the gate is for.

**What the gate cannot do.** The check is verbatim and case-sensitive across
`taskText`, `facts`, both commands, and `writableFiles`. A redacted fix that is
reworded, re-cased, or split across lines passes; so does a spec file sitting
in the worktree where the worker can simply read it. This is a tripwire for the
mistake that actually happened, not a proof of ignorance — and the doc should
not pretend otherwise.

Note the interaction with `facts`: a fact and a redaction can contradict each
other (pin `default_factory` while redacting it). The validator treats that as
an error, not a warning — it is exactly the mistake worth catching.

## Validation rules

Mechanical, no model in the loop:

1. `packet` version present and known.
2. `role` is one of the three known roles.
3. `workspace.writable` non-empty; every entry workspace-relative — no leading
   `/`, no `..` component. (The 19:26 run burned 6 writes on absolute paths.)
4. `workspace.paths` is `workspace-relative`.
5. All three budgets present and > 0.
6. `sampling.think` is a known mode; `temp` >= 0.
7. `validation.command` present and non-empty.
8. No string in `redacts` appears in the rendered packet.
9. Task body non-empty.

Rules 3 and 8 are the ones that would have caught real failures. The rest are
schema hygiene.

## What this does *not* do

It does not make the decompose role's judgment deterministic — choosing *which*
facts to pin is the model's job and stays a model output. What it makes
deterministic is the **interface**: a packet is either well-formed or it is
not, checkable in milliseconds without loading a 45 GB model or running an
implementer for three phases. That is the iteration-speed win.

## Per-role defaults (v1 starting point, to be tuned by measurement)

| role | think | rationale |
|---|---|---|
| decompose | `on` | genuinely underdetermined; failure is cheap (schema catches it) |
| implement | `off` | drafts inside thinking measured byte-identical — deliberation added zero content |
| repair | `bounded` | canonical bugs needed none; ambiguous ones are untested |

These are starting points, not conclusions. The A/B that settles them — same
packet, `think` on vs off, n=3 — is only possible *because* the packet is fixed.
