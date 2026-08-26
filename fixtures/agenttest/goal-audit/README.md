# Synthetic cells for the /goal auditor's V4 fixtures

V4 could not fire at all through v1–v3 because `main.swift` captured only
`phases[0]`, so no real capture carries the `phase-packet-N.json` artifact V4
reads. These two minimal cells exist so the check is proven to fire in both
directions before it is trusted — "never trust a check that has never fired".

They are deliberately synthetic and deliberately small: each is one phase, one
dispatched packet, one verdict reason.

- `v4-traceable/`   — the reason cites `RedirectResponse`, which the dispatched
  packet contains. Must PASS.
- `v4-untraceable/` — the reason cites `WebSocketMiddleware`, which no
  dispatched packet mentions: the model is being faulted for something it was
  never shown. Must FAIL.

**These do not satisfy done-when (d)**, which requires a known-bad drawn from a
real batch. The first pipeline run after the V4 capture fix should supply one,
and this directory should not outlive that.
