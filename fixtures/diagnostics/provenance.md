# `pathological` — synthetic diagnostic fixture (NOT a verbatim capture)

**Synthetic.** This fixture was hand-written to exercise the P6 analyzer's
decision logic, not captured from the real engine. It is typed test input to a
pure decision function (like the synthetic sequences in `DialLogicTests`), not a
fake engine binary — the "fakes are generated from captures" rule is about fake
*binaries* that simulate the wire, not about unit-test inputs to pure functions.

The `status` sequence reproduces the measured prefill curve from
`docs/harvest/telemetry-findings.md` (≈330 tok/s at `ctx_used` 3,400 down to
≈44 tok/s at 92,500 — the ~7x degradation). The trace's single `prefill sync
done` line reports a healthy prefix cache (1024/1074 ≈ 95%), so the analyzer's
"would compaction help" finding must answer `willNotFixRate`: the slowdown is
context size, not cache misses.
