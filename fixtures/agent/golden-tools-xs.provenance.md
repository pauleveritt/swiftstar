# `golden-tools-xs.ndjson` — capture notes (P22 XS golden recapture)

This fixture is a **verbatim, byte-for-byte copy of `ds4-agent`'s stdout** from
one real `--json-events` session with the **Laguna XS 2.1** model — the
contract-admitted artifact (`laguna-xs-2.1-RoutedQ3_K-biased.gguf`, the file
`VariantRegistry.lagunaXS`'s `QuantContract` (`downType: .q3_k`) actually
admits; the `Q4_K_M` file the acceptance did *not* run would be refused by the
verifier). Captured by the committed `swiftstar-drive` program with the P7
consent knobs, same recipe as the S-model `golden-tools.ndjson`.

It is the XS counterpart to `golden-tools.ndjson`: the tool-phase zoo
(`write`/`read`/`edit`/`list`/`bash`), the block
`start`/`tool`/`param_*`/`finish` sequence, a bash `output` event, and the
D12 `stop_reason`/`generated`/`ctx_used` fields on every turn-end `ready` —
proving the XS line produces the same wire shape as S on the pinned engine.
This closes the P22 forward item "XS golden recapture" (the acceptance verdict
listed the XS fixtures as pending) and re-verifies the pin's wire after the
P22 engine divergence #13 (a gate-only change, so the wire is expected
unchanged — this capture confirms it on the XS line).

## Provenance

- Submodule (`external/ds4`) SHA: `849f375` (`p20-dispatch-schema`, P22
  divergence #13 — `--ssd-streaming` admission widened to XS21 + S21). The
  SwiftStar gitlink pins this SHA.
- Built with: `just engine` (`make -C external/ds4 ds4-agent`). Binary run in
  place, `external/ds4/ds4-agent`.
- Captured by: `swiftstar-drive`, run from the repo root with
  `CAPTURE_GGUF=$HOME/projects/ds4/gguf/laguna-xs-2.1-RoutedQ3_K-biased.gguf \
   CAPTURE_WORKSPACE=/tmp/swiftstar-xs-workspace CAPTURE_SHELL=on \
   CAPTURE_PROMPTS_FILE=Tools/p7-tool-capture-prompts.txt just capture`.
- Model file: `laguna-xs-2.1-RoutedQ3_K-biased.gguf` (Laguna XS 2.1, 15 GiB) at
  `~/projects/ds4/gguf/` — the file the variant contract admits. Resident load
  (the drive's fixed shape does not pass the variant's SSD-streaming flags;
  the streaming path itself was live-validated 2026-08-28 in the
  model-switching run, `--ssd-streaming --ssd-streaming-cache-experts 3200
  --prefill-chunk 4096`, and the S-ssd probes).
- Recorded command line (from the capture's `CaptureManifest.commandLine`):
  `external/ds4/ds4-agent -m <gguf> -c 32768 --metal --non-interactive
  --json-events --trace <capture-dir>/wire.trace --workspace
  /tmp/swiftstar-xs-workspace --shell on`
- `DS4_LOCK_FILE=/tmp/ds4-capture-<pid>.lock`.
- Wall-clock start: `2026-08-28T15:26:40Z`.

## Workspace + Metal-source interaction

Same as `golden-tools.ndjson`: the engine's `--workspace` sets the agent cwd
(fail-closed confinement), and `swiftstar-drive` sets the `DS4_METAL_*_SOURCE`
overrides so Metal resolves after the chdir. Workspace setup before capture:

```bash
mkdir -p /tmp/swiftstar-xs-workspace && rm -f /tmp/swiftstar-xs-workspace/seed.txt
```

## Prompts sent, in order

The same `Tools/p7-tool-capture-prompts.txt` zoo as the S golden:

1. `Write a file named seed.txt in the current directory with content exactly: hello from golden-tools`
2. `Read the file seed.txt`
3. `Edit seed.txt: replace the text "hello" with "hi"`
4. `List the current directory`
5. `Run the command: echo hello-world`

## Verification (against the real `ds4-agent` at `849f375`, XS model)

Greps over the capture's `wire.ndjson`:

| grep | count | requirement |
|---|---:|---|
| `"phase":"start"`  | 8 | ≥ 1 |
| `"phase":"tool"`   | 8 | ≥ 1 |
| `"phase":"output"` | 2 | ≥ 1 (the bash echo) |
| `"phase":"finish"` | 8 | ≥ 1 |
| `"stop_reason"`     | 5 | ≥ number of prompts (5) — every turn-end `ready` carries a stop reason |
| `"t":"ready"`       | 6 | 1 startup + 5 turn-ends |

Tool names announced: `write`, `read`, `edit`, `list`, `bash` — the full
file/shell zoo. **Confinement proof:** `seed.txt` was created inside
`/tmp/swiftstar-xs-workspace/` with the edited content `hi from golden-tools`
(write ran, edit replaced `hello`→`hi`), nothing leaked into
`external/ds4/`.

## Recapture rule

Same as the S golden: on every submodule bump, this fixture must be recaptured
against the freshly rebuilt binary (`just engine`, then the `just capture`
invocation above) and the greps re-verified before installing. The next
recapture should re-confirm the contract-admitted file (`RoutedQ3_K`, never
the `Q4_K_M` the contract refuses).
