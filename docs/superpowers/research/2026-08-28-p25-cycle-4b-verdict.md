# P25 Cycle 4b verdict — Metal working-set admission denominator

**2026-08-28.** Cycle 4b closes: the admission denominator switch is landed,
Fable-reviewed across three passes, and fast-tier + live-integration tested.
Design: [`2026-08-27-p25-deepseek-v4-flash-variant-design.md`](../specs/2026-08-27-p25-deepseek-v4-flash-variant-design.md#cycle-4b--ask-the-right-question).

## What shipped

1. **`VariantGate` denominator switch** (`ca2dc33`) — admission now checks
   against `MetalWorkingSet`'s wired-limit-aware ceiling
   (`recommendedMaxWorkingSetSize`, overridden by the live
   `iogpu.wired_limit_mb` sysctl when raised) instead of `MemorySnapshot`'s
   free+inactive RAM pages — the actual constraint a large GPU-resident
   launch is bound by. Shared, cross-variant change: every registered
   variant now admits against a more accurate, more permissive ceiling.
   `VariantGate.admit` gained an optional `wiredLimitAdvisoryBytes`
   parameter (default `nil`; every pre-4b call site and test unchanged), so
   a refusal can name the exact `sudo sysctl -w iogpu.wired_limit_mb=N` fix.
2. **Two Fable-review fixes landed in the same commit**: the sysctl advisory
   was suggesting the launch's own bare requirement (zero headroom for
   anything else sharing the system-wide GPU wired ceiling) instead of the
   already-computed RAM-minus-reserve advisory — a real hang risk, now
   regression-guarded by a test pinning the specific number; and
   `swiftstar-agenttest`'s capture telemetry still logged the old
   `MemorySnapshot` denominator while admission used the new one, breaking
   capture reproducibility — now logs `VariantAdmissionSource.availableBytes()`.
3. **DeepSeek `maxContext` correction** (same commit) — 524,288 cleared the
   OS-default Metal limit (526,267) by only ~30 MiB, indistinguishable from
   the Cycle 3 oracle's own tolerance and with no allowance for other
   GPU-wired usage. Corrected to **450,000** (~1.76 GiB real headroom under
   the 107.52 GiB ceiling on this machine).
4. **`MetalWorkingSet` unit coverage** (`624b640`) — Fable's review flagged
   zero unit coverage and that the sysctl-override-wins precedence had never
   executed on this machine (`iogpu.wired_limit_mb` unset here). Ported
   ds4-control's `DEBUG`-only env-var override pattern as
   `SWIFTSTAR_EMULATE_WIRED_LIMIT_MB`, exercising the previously-dead branch.
5. **Machine-readable advisory** (`1b5ee9d`) — Fable's last finding: the
   remedy was prose-only, unusable by a future UI without string-parsing.
   `FeasibilityReason` gained `wiredLimitAdvisoryBytes` and a computed
   `wiredLimitFixBytes` (non-nil only when raising the limit would truly
   admit the launch), and `VariantGate.infeasibleMessage` now routes through
   the same formula the computed property uses, so prose and machine-
   readable fact can't silently disagree.

Commits: `ca2dc33`, `624b640`, `1b5ee9d`. Fast tier: 732 tests green; 9/9
live integration tests green under `SWIFTSTAR_INTEGRATION=1` on this machine
(M5 Max, 128 GiB, `iogpu.wired_limit_mb` unset).

## Gate (from the design doc) — met

> table-driven tests over both regimes; on this machine the flagship admits
> at ctx ≤ ~526k and refuses above it with the advisory number. Mellum/XS/S
> admission outcomes must be re-confirmed — nothing that should refuse now
> admits.

Covered by `VariantGateTests.swift`, `MetalWorkingSetTests.swift`, and
`WiredLimitAdmissionIntegrationTests.swift`. No prior variant's admission
outcome regressed under the new denominator in these tests.

## What's still open in P25

- **Cycle 5** (live 91 GiB acceptance run) — **skipped by decision
  2026-08-27**, not blocking. The 450,000 `maxContext` correction was made
  precisely because this validation is not happening; the margin is
  derived, not measured.
- **Cycle 6** (SSD streaming) — deferred; re-open only with a reason, and
  re-check [`antirez/ds4#635`](https://github.com/antirez/ds4/issues/635)
  first.

## Note on ROADMAP staleness

[ROADMAP.md](../../../ROADMAP.md) P25 row said "4b wants review" — stale as
of this doc. 4b was reviewed (Fable, three passes) and shipped before the
P22 closure commits landed on top of it in history.
