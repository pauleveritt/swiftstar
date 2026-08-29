# CAG and the librarian

Research note, cross-cutting the ANE watcher tier (the librarian): what
[Cache-Augmented Generation](https://arxiv.org/html/2412.15605v2)
(Chan et al., WWW '25 short paper, arXiv 2412.15605v2) actually is, and how it
maps onto the librarian in
`docs/superpowers/research/2026-08-23-monty-and-the-ane-watcher-tier.md`.

**Research, not design.** No phase spec is pre-empted here. **Nothing in this
note is measured.** The economics it leans on (prefill is depth-scaled; KV
reuse is exact-prefix-only; the warm session serves 85–95% of each prompt from
cache) are measured and already recorded in
`docs/harvest/telemetry-findings.md`,
`docs/superpowers/research/2026-08-26-heavy-session-telemetry-findings.md`, and
`docs/superpowers/research/2026-08-23-house-style-as-a-compiled-artifact.md`.
Every claim specific to CAG-on-the-librarian below is conjecture, and
"What would falsify this" names the numbers that decide it.

## What CAG is (compressed to the parts that matter here)

The paper's move: when the knowledge corpus is **bounded and stable**, do not
retrieve at query time — *preload the whole corpus into context, precompute its
KV cache, and reuse it across every query*. Three phases:

1. **Preload** — `C_KV = KV-Encode(D)`: encode the whole document set `D` once,
   store the KV cache on disk/memory. The cost is paid once, regardless of how
   many queries follow.
2. **Infer** — `r = M(q | C_KV)`: each query is *appended* to the cached
   context; only the query tokens are prefilled fresh.
3. **Reset** — truncate the appended tokens to return to the preloaded state.
   Append-only KV growth, so reset is free.

The measured claims (Llama 3.1 8B, SQuAD + HotPotQA): CAG beats sparse and
dense RAG on BERTScore in nearly every config (e.g. HotPotQA-small 0.795 vs
0.768 sparse / 0.758 dense; SQuAD-large 0.773 vs 0.766 / 0.759), eliminates
retrieval latency and retrieval errors, and precomputing the KV drops
generation time from 92s (in-context learning, 85k-token context) to 2.3s.

The paper's own limits, stated plainly: the corpus must fit in context; as
corpus size grows, the CAG-vs-RAG gap *narrows* (long-context degradation —
lost-in-the-middle); and the conclusion gestures at the hybrid we should
notice: *"preload a foundation context and use retrieval only to augment edge
cases or highly specific queries."*

## The librarian is already a CAG system, minus the cache

The librarian's context decomposes into exactly the layers CAG wants:

| Layer | Contents | Change rate | CAG role |
|---|---|---|---|
| **Stable** | envelope (imports/template), host-function stubs, interest declarations, standing rules | changes at registration/edit time | **preload once** |
| **Event** | the projected digest slice (D6, reduced by the host) | every event | **append per event** |
| **Edge** | `kv_query(selector)` — the narrow host function | rare, only when the slice is insufficient | **retrieve on demand** |

Read that against the paper's conclusion and the mapping is one-to-one: the
*stable* layer is the preloaded foundation context; the *event* layer is the
query; the *edge* layer is the paper's "retrieval for edge cases." The note's
existing hybrid — project the common case, `kv_query` the rare deep read — is
literally the paper's recommended end state. What the note does **not** yet do
is exploit the middle column: it treats every wake as a fresh prefill over the
whole (envelope + stubs + interests + slice), because it never splits the
stable layer off into a cached prefix.

## The refinement CAG actually buys: two different prefill costs

This is the point the paper gets subtly wrong and SwiftStar's telemetry gets
right. The paper bundles everything under "eliminates retrieval overhead." But
on this engine there are **two distinct costs**, only one of which CAG
eliminates:

1. **Recompute** — re-prefilling tokens that were already seen. *Saved* by the
   prefix cache. Measured: the warm session serves 85–95% of every prompt from
   cache (`cached/prompt` in the heavy-session finding).
2. **Attention-depth tail** — attention cost scaling with *total* context
   length, regardless of how little of it is new. *Not saved* by any cache.
   Measured: prefill time roughly doubled (2,044 → 11,557 ms) for the same
   ~1,700–1,900-token suffix as context filled; the 7x throughput curve from
   3,400 → 92,500 tokens is this same term.

CAG eliminates cost 1 for the stable layer and does **nothing** for cost 2.
The paper's own Table 3 shows cost 2: CAG generation time grows 0.85s → 2.26s
as the corpus grows 21k → 85k tokens, *with retrieval already gone*. That is
the attention-depth tail, and it is why the preloaded corpus must stay small.
On SwiftStar this is not a footnote — it is the whole design constraint. The
projection step (D6 reduces the digest before it crosses the wire) is already
the admission control that keeps the corpus small; CAG makes the *economic
consequence* of that gate legible: **projection is not just a data-boundary
hygiene rule, it is what keeps the attention-depth tail affordable.**

## Why the exact-prefix-only objection does not apply here

The house-style note rejected specialist subagents on the grounds that KV
reuse is **exact-prefix-only** and a per-specialist recipe is a divergent
prefix that breaks the shared bootstrap root. That argument is correct *and
does not transfer*. The librarian's context is a **linear, append-only prefix**
by construction — stable layer first, event slice appended after it. That is
the one shape exact-prefix reuse is built for: the stable layer's KV is the
prefix, the event slice is the fresh tail. The librarian does not need RAG's
arbitrary insertion into the middle of context; it needs append-then-truncate,
which is the engine's native pattern. CAG is the *only* shape of model reuse
the note has proposed that fits the prefix cache rather than fighting it.

## The warm session is the cache

The single most important operational lesson, and it costs nothing to adopt: a
long-lived watcher with a persistent ANE session *is* a KV cache that survives
events. The note already calls the librarian "long-lived, own small context" —
CAG explains why that property is load-bearing rather than incidental. A
watcher that cold-starts per event re-pays the preload tail per event; a warm
one pays it once. The design consequence is only that the ANE session must be
**kept warm across events** (append slice → react → truncate → idle), not torn
down and rebuilt. "Reset" in CAG's sense is truncate-back-to-stable-layer, not
teardown.

## `ask_model` loops become shared-prefix CAG

The note's `ask_model` pattern — a Monty loop issuing sequential bounded model
calls (classify each item, then aggregate) — is RLM/slicing with the strategy
as a program. CAG refines it: the *scaffolding* (the classify template, the
aggregate template, the standing instruction prefix) is stable, so it is a
single cached prefix; each *instance* is a tiny appended query. A loop of N
calls becomes one cached prefix + N small appends instead of N full prefills.
This is the TurboRAG chunked-KV trick (the paper's own reference, Lu et al.
2024) applied at the loop level, and it sharpens the note's economics claim:
"sequential shallow prefills beat one deep prefill" becomes "sequential shallow
prefills *over one shared cached prefix* beat one deep prefill."

## The inspector is the negative case

The inspector (near-sync, stateless per call, inside the tool loop) has no
corpus to preload and no amortization to capture — every call is a fresh
bounded context. CAG's lesson there is mostly negative: *don't* try to preload
a standing context for it. The one transfer is that its shared envelope
(template + stubs) could be a tiny cached prefix — but only if the ANE runtime
can load a cached prefix within the tool's execution window, which is the same
"fill + `ty` + execute latency" number the note already pre-priced. If the
cache-load is not fast enough, the inspector stays a plain bounded prefill and
loses nothing.

## What would falsify this

The note already has two falsifiers (the AFM invocation API; the fill-success
rate) and one bounded number (inspector latency). CAG extends the first and
adds a third:

1. **The AFM API must support stateful sessions, not just one-shot
   generation.** CAG's entire premise for the librarian is that the ANE model
   runtime exposes a *persistent session whose KV cache survives across
   appends* (the paper's `M(q | C_KV)`). If AFM-on-ANE is callable only as a
   one-shot `.mlmodel` predictor — or if it exposes no cache-reuse surface to
   Swift — then CAG is unavailable for the librarian and the design falls back
   to "small-slice re-prefill per event," which is the note's current
   assumption. This is a sharper version of the note's existing check: the API
   must offer prompt-and-complete with a persistent prefix, not merely text
   generation.
2. **Fill-success rate** — unchanged; CAG does not touch it.
3. **The recompute-vs-depth crossover on the ANE.** At what stable-layer size
   does the attention-depth tail (cost 2) overtake the recompute savings
   (cost 1)? On the GPU this curve is measured (the 7x line); on the ANE it is
   unmeasured. If the ANE's depth curve is as steep as the GPU's, the stable
   layer must be hundreds of tokens, not thousands — and the envelope + stubs +
   interest surface has to be audited for size, not just written. This is
   measurable with the existing capture driver once the API question (1) is
   answered.

## Risks

- **Cache staleness is a new failure mode.** A cached stable layer is a frozen
  snapshot. Interests, the envelope, or standing rules change → the cache must
  be re-encoded, or the librarian reacts to stale state. The host must carry a
  version/epoch on the cached prefix and bump it when the stable layer changes.
  The note's digest is live; a cached prefix is not, and nothing in the current
  design invalidates it.
- **The depth tail eats the win if the stable layer grows.** The projection
  gate keeps the *event* slice small, but CAG adds a second budget: the *stable*
  layer size. Envelope + stubs + interest declarations must be audited as a
  memory budget, exactly as the note prices the digest slice.
- **Lost-in-the-middle is the ceiling.** The paper concedes the CAG-vs-RAG gap
  narrows as the corpus grows. The librarian's corpus must stay small enough
  that the model actually reads the interest + slice, not the middle of a
  bloated prefix.
- **Reset discipline must hold.** Truncate-to-reset assumes per-event reactions
  are ephemeral. State that must persist across events belongs in Monty (the
  executor), never in the model context — which the note already gets right;
  CAG makes violating it cheaper-looking (just append to the warm context) and
  therefore more tempting.

## Where CAG does not apply (negative space)

The librarian is the one component where CAG fits, because it is the one with
a **bounded, stable corpus** and a **long-lived warm session**. The main
agent's accumulated conversation is the opposite — unbounded, changing, and
depth-scaling is precisely its problem, which is why compaction exists to
shrink it. The P11 pool workers are short-lived and serialized, and the
house-style note already showed why their divergent prefixes do not pay; they
already ride the shared bootstrap prefix. CAG is not a general SwiftStar
technique. It is a specific fit for the watcher tier, and recognizing that
boundary is as much the finding as the fit itself.

## Filed

The higher-level reading — pre-chewed project state, the librarian/RLM role
split, and the 4k AFM capacity question — is filed in the ROADMAP's ANE
watcher tier entry ("CAG filing 2026-08-28"). Indexing is already P24's
deterministic job; this note's CAG mechanics sections stand unchanged.
