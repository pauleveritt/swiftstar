# SwiftStar P19.1 design: app shell

**Date:** 2026-08-27
**Status:** proposed (design approved in-session; implementation not started)
**Phase:** P19.1 — the Agent surface, reorganized. Sub-phase of P19 ("One
surface"); the two bounded polish items are P19.0 (tracked separately).

This spec is the authority on *how* the app's top-level window is reorganized.
P19's theme is "the Agent is the app"; P19.0 finished the *content* (Chat
retired, one surface), and P19.1 finishes the *frame*: a Tahoe-forward shell
with a real toolbar, a collapsible sidebar, and the engine lifecycle hidden
behind a single model choice. Scope is strict: the shell and its conventions.
No projects/sessions tree, no SDD mode, no model-switch *behavior* (that is
P22), no image pipeline (backlog).

## Problem

The Agent surface is complete in content but framed like a utility: `MainView`
is a five-tab `TabView` (Agent, Dispatch, Metrics, Diagnostics, Help), the
window has **no toolbar at all**, and the top "status bar" is an in-view
`HStack` carrying both telemetry and controls (workspace button, smart/dumb
picker, a "Stop Agent" button — with a second "End session" button in the bottom
bar that calls the same `stopAgent()`). Engine lifecycle is ambient and
exposed: model selection lives in Settings ("applies when the engine next
starts"), and there is no notion of switching a running session. The shell does
not yet know how to be lean (chat-only) and grow on demand (sidebar, panels),
which is the shape the ROADMAP's future work assumes (a projects/sessions
sidebar, SDD mode as a main-window mode with a phase-browser rail).

Two facts make a restructure the right move now rather than a bolt-on later:

1. **The surface will grow sidebars, not tabs.** The future items — a
   projects→sessions sidebar ("like most other desktop agent UIs") and SDD mode
   ("a dedicated UI, and thus context") — are columns and rails, not tabs. A
   `TabView` shell would need re-parenting to host them; a `NavigationSplitView`
   shell grows them as new sections/columns in place.
2. **The conventions should be compiled, not remembered.** The house rule
   ("style as a gate, not a prompt") applies to architecture as much as style.
   P19.1 lands the concurrency gates (Swift 6 language mode, MainActor default
   isolation) and a machine-readable component vocabulary at the same moment the
   shell is named — so the enforcement and the naming are grounded in the real
   components, not retrofitted.

## Scope (strict)

**In:** `NavigationSplitView` shell (sidebar = sections, detail = content) with
lean-by-default column visibility; a real window toolbar (`ToolbarCommands`,
customizable) absorbing the control surface; Settings moves (pool size, session
capture, smart/dumb default, workspace default); the model-choice toolbar menu
(control shape + lifecycle-hiding convention only); the component/region
vocabulary registry; the concurrency gates; Dispatch/Metrics/Diagnostics as
sidebar sections; the composer attachment *seam* (no paste implementation).

**Out (explicit):** the projects/sessions tree (structure reserved, not built);
SDD mode and the phase-browser rail (vocabulary term reserved, not built); the
model-switch *behavior* — stop/respawn, feasibility admission, transcript
preservation, pool re-spawn (P22); the AFM provider dimension; the image
description pipeline (backlog — consumes the vocabulary, does not ship here);
`WindowTabGroup` and multi-window; the composer paste/attachment implementation.

## Gardenable facts (verified against source)

- **Platform/toolchain.** `Package.swift` declares `.macOS(.v26)`,
  `swift-tools-version: 6.2`; the installed toolchain is Swift 6.3.3
  (swift-driver 1.148.6). **No `swiftSettings` is configured** — no language
  mode, no strict concurrency, no default isolation (compiles in v5 mode
  silently). `SwiftSetting.defaultIsolation(_: MainActor.Type?, ...)` and
  `SwiftSetting.swiftLanguageMode(_:)` are both present in the installed
  PackageDescription interface (verified via the toolchain's swiftinterface).
- **Shell.** `MainView` is a `TabView` with five `.tabItem`s: Agent, Dispatch,
  Metrics, Diagnostics, Help (the last a `PlaceholderView`). **Zero `.toolbar`
  usage exists anywhere in `Sources/`** (grep-empty).
- **Agent surface.** `AgentView` top bar is an in-view `HStack`: status dot +
  text, workspace button, smart/dumb segmented picker (`@AppStorage
  "dispatchDumb"`), and a **"Stop Agent"** button; a separate bottom bar holds
  **"End session"** — both buttons call `controller.stopAgent()` (duplicate
  affordance, same action).
- **Controller ownership.** `AgentController` is `@Observable @MainActor`, with
  `static weak var shared` (set in init) used only by `AppDelegate`'s
  quit handler (`applicationWillTerminate` → `stopAgent`). It is owned as
  `@State` in `MainView`. `MetricsModel`/`DiagnosticsModel` are `@Observable`,
  started in `MainView.onAppear`, re-keyed on `runningPid` changes — the models
  are shell-owned regardless of where their views live.
- **Engine argv / capture.** The agent spawn argv hardcodes `--subagent-pool 2`
  (`AgentController.swift:328`); `PoolEngine` takes `workers` → `--subagent-pool
  N`. Live-session capture writes to `captures/live/<name>` and is always-on
  today (no toggle). Context default is `51_200` (50k).
- **Model selection.** Settings holds `selectedVariantID`/`modelPath`/`contextSize`
  etc.; `VariantRegistry.all == [mellum]` (Laguna S is the hardcoded fallback,
  not a registry entry). Selecting a variant "applies when the engine next
  starts" — there is no in-session switch.
- **APIs (verified against Apple docs this session).** `NavigationSplitView`
  (3-column + `columnVisibility` binding + `.prominentDetail` style),
  `.inspector(isPresented:)` composes with it, and macOS toolbar customization
  is `.toolbar(id:)` + `ToolbarItem(id:)` + `.customizationBehavior` +
  `ToolbarCommands()` in the scene's `.commands`.

## Design

### Components

1. **`AppShellView`** (replaces `MainView`'s `TabView`): a `NavigationSplitView`
   with `columnVisibility` bound to persisted state. Sidebar column = a `List`
   with the four sections (Agent, Dispatch, Metrics, Diagnostics; the Help
   placeholder tab is removed). Detail column = the selected section's view. Style:
   `.prominentDetail` so the detail holds size as columns toggle. `columnVisibility`
   defaults to `.detailOnly` on first launch and is persisted
   (`@SceneStorage`), so "lean" is the default and the sidebar is reveal-on-demand
   (toolbar toggle + View menu, ⌘⌥S — system-provided).
2. **Window toolbar** (`.toolbar`, unified style): sidebar toggle, workspace
   button (moved from the in-view bar), the model menu (D4), End session. Wired
   with `ToolbarCommands()` and `.toolbar(id:)` + `customizationBehavior` so
   the busy items are user-removable — the literal "lean by default, opt into
   more" mechanism. The telemetry **rings/rates stay in the bottom in-view
   status bar** (their identity is "glanceable, not chrome"); the top in-view
   `HStack` dissolves — controls go to the toolbar, status text to the toolbar
   trailing or bottom bar.
3. **Settings moves** (D3): pool size (`--subagent-pool`, default 2), session
   capture on/off (default on), smart/dumb default, workspace default. The
   division of labor is explicit: **Settings = defaults; toolbar = the active
   session's value.**
4. **Model menu** (D4): a single toolbar "Model" control enumerating
   `VariantRegistry.all` + custom. Same-selection is a no-op; the *switch
   behavior* is P22's (this phase ships the control + convention, disabled while
   generating). Engine lifecycle is hidden: no Start/Stop Agent buttons; the
   one explicit affordance is End session (stops the run); quitting the app
   stops the engine (already wired in `applicationWillTerminate`).
5. **Component/region vocabulary** (D5): a machine-readable registry — name +
   stable `id` + semantic role for each shell region (sidebar, toolbar, detail,
   inspector, composer, transcript, tool card, status bar, ring gauge, model
   menu, workspace control, phase-browser rail, picker, segmented control,
   toggle, slider, text field, disclosure, section, list, grid). Lives in
   `SwiftStarKit` (pure, testable). Two consumers: the future image-describer
   (emits descriptions in these terms) and the agent developing SwiftStar
   (reasons about the layout in these terms).
6. **Concurrency gates** (D6): `.swiftLanguageMode(.v6)` and
   `defaultIsolation(MainActor.self)` on the **SwiftStar (app) target only** —
   `SwiftStarKit`/`SwiftStarAppKit` keep the default (nonisolated) so the
   engine-facing seams (wire drain, `ProcessStatsCollector`, pool) stay
   explicitly isolated, not defaulted away. Landed incrementally: strict
   concurrency `complete` under v5 → fix → `.v6` → `defaultIsolation(MainActor)`,
   tests green at each step.

### Data flow

- **Launch (lean):** `AppShellView` shows the Agent detail at `.detailOnly`;
  sidebar/toolbar are present but not prominent. `AgentController` is still
  created once at shell level (`@State`), `weak shared` unchanged.
- **Reveal:** sidebar toggle (toolbar button / ⌘⌥S) flips `columnVisibility` to
  `.all`; the View menu and toolbar toggle are system-provided. Inspector
  (off by default) opens via `.inspector(isPresented:)` for glanceable telemetry.
- **Model choice:** toolbar menu reads the active model; a change is deferred to
  P22's switch path (this phase: the control renders and reflects state, disabled
  mid-generation).
- **Settings → spawn:** pool size and capture toggle read from `@AppStorage`
  where `AgentController` builds argv and where capture initializes; smart/dumb
  default from the existing `dispatchDumb` store.

### Error handling

- The shell introduces no new failure class. Model-menu and section state are
  pure UI; the engine's existing failure paths (`.infeasible`, `.variantMismatch`,
  spawn errors) render in the detail column's existing error surface unchanged.

### Testing

- **Vocabulary registry:** unit tests pin that every shell region has a unique
  stable id and a non-empty role string (the seam the image pipeline will depend
  on — a renamed id is a test failure by design).
- **Section/model state:** the section selection and `columnVisibility`
  default/persistence are extracted as observable state where they can be tested
  without a window (Kit-side); the persistence key round-trips.
- **Settings → argv:** pool size and capture toggle flow into the spawn argv and
  capture base (extend the existing argv/capture tests, which already assert the
  `--subagent-pool 2` and `captures/live` shapes).
- **Concurrency gates:** no new tests per se — the gate is the compiler; each
  incremental step ends with the existing suite green (fast + integration).

## Decisions

- **D1** — Shell is a `NavigationSplitView` (sidebar = sections, detail =
  content), not a `TabView(.sidebarAdaptable)`. Rationale: the projects/sessions
  tree wants to *be* the top-level sidebar, and `NavigationSplitView` grows it
  as a section/column in place without a nested second sidebar; `.prominentDetail`
  + `columnVisibility` give the lean/reveal story; the migration is ~5 views.
- **D2** — Real window toolbar (Tahoe-forward), `ToolbarCommands` +
  `.toolbar(id:)` customization. Controls move out of the in-view top bar; the
  telemetry rings/rates stay in the bottom in-view status bar.
- **D3** — Settings = defaults (pool size, capture, smart/dumb, workspace,
  model), toolbar = active-session values. Never two sources of truth for the
  same knob.
- **D4** — One toolbar "Model" menu; engine lifecycle is implicit. No Start/Stop
  Agent buttons; single "End session"; engine stops at quit. The switch
  *behavior* is P22's — this phase ships the control and the convention, disabled
  mid-generation. The menu reflects the **effective** model: the Laguna S
  default (today's hardcoded fallback) plus `VariantRegistry.all` plus custom —
  not the registry alone (which today holds only Mellum). P22 completes the
  enumeration when Laguna XS becomes a registry variant.
- **D5** — A machine-readable component/region vocabulary registry in
  `SwiftStarKit`, named *as the shell is built* (not retrofitted). It is the
  shared substrate for the future image-describer and the agent's own layout
  reasoning. Stable ids are load-bearing: renaming one is a deliberate,
  test-visible act.
- **D6** — Concurrency gates land incrementally and land **only** in this phase
  (not silently in P19.0): strict concurrency → `.v6` → `defaultIsolation(MainActor)`
  on the app target only. Kit/AppKit keep explicit isolation.
- **D7** — Dispatch, Metrics, Diagnostics are secondary sidebar sections
  (Dispatch is **not** folded into orchestrate — it is P10's worktree-isolated
  capability, a distinct mechanism). Metrics/Diagnostics *models* stay
  shell-owned; only their views move.
- **D8** — The composer is shaped to accept a future attachment/paste seam
  (an attachment chip above the input), but no paste/attachment code ships.
- **D9** — Controller ownership is preserved: one `AgentController` at shell
  level, `weak shared` for quit. If SDD later becomes a second window, the
  controller design is revisited then — recorded, not solved here.

## Verification (done-when)

1. `MainView` is a `NavigationSplitView`; the sidebar lists Agent, Dispatch,
   Metrics, Diagnostics; first launch is `.detailOnly`; the choice persists
   across relaunches.
2. A real window toolbar is present with `ToolbarCommands`; "Customize Toolbar"
   works; the workspace control, model menu, and End session live there; the
   telemetry rings remain in the bottom bar; there is exactly one End-session
   affordance and no Start/Stop Agent buttons.
3. Settings exposes pool size (default 2), session capture (default on),
   smart/dumb default, and workspace default; each flows to the spawn/capture
   path (asserted by the argv/capture tests).
4. The toolbar Model menu enumerates the registry variants + custom, is disabled
   mid-generation, and a same-model selection is a no-op.
5. The component/region registry enumerates every shell region with a unique
   stable id and role; its unit tests pass.
6. Concurrency gates land in the three incremental steps with the full suite
   green at each (fast + integration); the app target compiles under
   `defaultIsolation(MainActor)`.
7. `swift test` green with no new warnings; no regression in the existing 552
   fast-tier tests.

## Deferred (not this phase)

- **Projects/sessions sidebar** — grouped tree with rename; P19.1 reserves the
  sidebar structure, builds nothing.
- **SDD mode** — main-window mode with a secondary left rail (phase browser) as
  a listing; the `phaseBrowserRail` vocabulary term is reserved, the mode is not
  built. Placement (sidebar section vs. mode vs. separate window) is re-decided
  when SDD is planned.
- **Model-switch behavior** — stop/respawn, feasibility/VariantGate admitted
  before stop, transcript preservation, pool re-spawn, mid-generation refusal
  semantics: **P22**. P19.1 ships only the control + the lifecycle-hiding
  convention.
- **AFM provider dimension** — engine vs. AFM in the model menu; the control's
  data shape is kept able to grow a provider field, nothing more.
- **Image support** — clipboard paste → deterministic description → context;
  the `image_*` tool family; feature-print + vocabulary index; captioner/MLX/AFM
  escalation. Backlog; consumes the D5 vocabulary.
- **Composer paste/attachment implementation** — the seam (D8) only.
- **`WindowTabGroup` / multi-window** — overkill for the one-surface app.
- **Autoscroll / markdown render preferences** — Settings candidates, "only if
  trivial"; not part of the shell.
