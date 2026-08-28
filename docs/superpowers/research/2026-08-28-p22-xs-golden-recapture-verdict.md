# P22 XS golden recapture — verdict

**2026-08-28.** P22's XS-golden-recapture forward item closes: the XS golden
fixture is taken against the **contract-admitted** file on the pinned engine,
verified, and committed with provenance. This was the last open P22 forward
item — Item 4 (16 GB hardware acceptance) is skipped by decision 2026-08-27,
never scheduled.

## The trap the item names

The P22 acceptance ran the **RoutedQ3_K** artifact
(`laguna-xs-2.1-RoutedQ3_K-biased.gguf`). The `Q4_K_M` file — which the
`lagunaXS` variant's `QuantContract(downType: .q3_k)` would **refuse** (the
verifier finds Q4_K tensors where it expects Q3_K) — is a red herring for the
golden: a capture from it would not be admitted by the variant's own gate. The
golden must come from the file the contract actually admits, which is what
`VariantRegistry.lagunaXS` resolves (`~/projects/ds4/gguf/` on the search
path). Confirmed by direct read of the variant + a passing
`everyRegisteredVariantResolvesToAReadableFile` against the real file.

## What shipped

**`fixtures/agent/golden-tools-xs.*`** (`620b635`) — a verbatim
`swiftstar-drive` capture of the real `ds4-agent` (pin `849f375`, P22 engine
divergence #13) with the RoutedQ3_K file at ctx 32768, using the same p7
tool-zoo prompt set as the S golden (`golden-tools`): wire + stderr + trace +
a provenance note documenting the recipe, the prompts, and the verification.

Verification greps (in the provenance note, re-run at install):

| grep | count | requirement |
|---|---:|---|
| `"phase":"start"` / `"tool"` / `"finish"` | 8 each | ≥ 1 |
| `"phase":"output"` | 2 | ≥ 1 (the bash echo) |
| `"stop_reason"` | 5 | ≥ 5 prompts — every turn-end `ready` carries it |
| `"t":"ready"` | 6 | 1 startup + 5 turn-ends |

Tool names announced: `write`, `read`, `edit`, `list`, `bash` (the full zoo).
Confinement: `seed.txt` created + edited **inside** the workspace (content
`hi from golden-tools`), nothing leaked into `external/ds4/`.

## Confirmation asked by the brief

`everyRegisteredVariantResolvesToAReadableFile` — **PASS** on the real file
(fast tier, `ModelLocationTests`, 1 test).

## Standing-rule note

The submodule bump this session (`7838700`, divergence #13) is a gate-only
change — no wire emission touched — so no recapture of the existing S goldens
is owed (same precedent as divergence #12; recorded in the fork-ledger row).
The XS golden is an additive fixture, and its provenance documents that every
future bump must recapture it the same way.

## Open items

- The backlog's larger golden-tools item (a fixture test asserting
  `kind`/`path`/`finished` populate from a fresh recapture with provenance)
  remains backlog; the XS fixture above is the sanctioned input for it when it
  reopens.
- 16 GB hardware acceptance — skipped by decision, never scheduled.
