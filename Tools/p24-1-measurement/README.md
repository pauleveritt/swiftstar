# P24.1 measurement protocol

Committed so both arms can be re-run and audited. The original run was not —
its prompts, timeout and control diff lived in a scratch directory and the
control branch was deleted, which is the evidence-hygiene failure P26 was about.

Results: [`2026-08-30-p24-1-window-honoring-after-measurement.md`](../../docs/superpowers/research/2026-08-30-p24-1-window-honoring-after-measurement.md).

## Treatment arm (as shipped)

```sh
export SWIFTSTAR_MODEL=/path/to/model.gguf
Tools/p24-1-measurement/run.sh
```

## Control arm (pre-P24.1 read behaviour)

On a throwaway branch, replace the **body of the app branch** of
`HostToolExecutor.readResult` — everything from the `// P24.1: the app's shape`
comment down to (not including) `private func intParam` — with the pre-P24.1
body:

```swift
        // CONTROL ARM (pre-P24.1 behaviour, do not merge): whole file,
        // window params ignored, straight into the 8000-byte condenser.
        guard let path = HostToolConfinement.realPath(request) else {
            return ToolExecutionResult(ok: false, text: "error: path is outside the workspace grant")
        }
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            return ToolExecutionResult(ok: false, text: "error: could not read \(path)")
        }
        return ToolExecutionResult(ok: true, text: text)
    }

```

Keep everything else — `intParam`/`boolParam`, the continuation map,
`setContextSize`, `resetReadState` — so only the function under test differs.
Then `swift build` and run `run.sh` exactly as for the treatment arm, and
`git branch -D` the branch afterwards.

## Analysis

```sh
swift run swiftstar-eval rereads <capture-dir-name>
python3 Tools/window-spread.py captures/<capture-dir-name>
```

## What the knobs mean

- `CAPTURE_HOST_TOOLS=1` — **essential**. Without it the *engine* runs `read`
  itself and the capture measures code P24.1 never touched. The first attempt
  at this measurement failed exactly this way (0 `tool_request` events).
- `CAPTURE_TURN_TIMEOUT=240` — deliberately below the 900 s default, because the
  control arm is expected not to converge. Every "timed out" claim in the
  write-up means *did not finish in 240 s*, never *cannot finish*.
- `CAPTURE_CTX=32768` — the app's default, so the 500-line read tier applies.

## Known limits of the run on record

One session per arm, one seed; the control failed at prompt 1 so there is no
Σsuffix comparison; and the numeric falsifier in `window-spread.py` is
post-hoc — see the write-up's "what was pre-registered, and what was not".
