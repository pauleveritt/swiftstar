# Modern SwiftUI layout, previews, Swift Testing and build settings (Xcode 27, Swift 6.4)

> Research for SU.4 (Xcode-first UI loop) and SU.5 (cleanup and test
> modernisation), gathered 2026-10-04 by a research agent against current Apple, swift.org and Swift Evolution sources plus the installed toolchain. Kept as
> written, apart from this header. Each finding carries its own confidence tag; treat
> **UNCONFIRMED** items as leads, not facts, and re-check before building on
> them. Related: [`2026-10-04-su4-handoff-brief.md`](2026-10-04-su4-handoff-brief.md).

Tools verified locally: Xcode 27.0 (27A266a), Apple Swift 6.4 (swiftlang-6.4.0.34.1), SwiftPM 6.4.
Confidence tags: [LOCAL] = verified by running the installed toolchain; [PRIMARY] = Apple/swift.org/Swift Evolution
source; [CONSENSUS] = many practitioners agree; [OPINION] = practitioner judgment; [UNCONFIRMED] = could not verify
against a primary source. Several 2026 blog hits (iosbuddy, theswift.dev, theswiftk.it.com, agenthicks, medium) read as
low-quality or AI-generated; they are used only for color and marked accordingly.

---------------------------------------------------------------------------------------------------
## 1. Project / file layout
---------------------------------------------------------------------------------------------------

1.1 **MV with @Observable is the Apple-documented default; add a view model/controller only where there is logic worth testing.**
 - Apple's "Managing model data in your app" teaches `@Observable` model types read directly by views ("separation ...
   promotes modularity, improves testability"), with no view-model layer. [PRIMARY]
   https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app
 - avanderlee (2026-08-31): "You do not have to introduce a view model for every SwiftUI view"; introduce one when a
   view coordinates async work, validation, multiple services, or testable behavior; make it `@Observable` + `@MainActor`.
   [CONSENSUS on "don't force it", OPINION on exact threshold]
   https://www.avanderlee.com/swiftui/mvvm-architectural-coding-pattern-to-structure-views/
 - Fit for SwiftStar: `EngineController` (@Observable, owns async subprocess state) is the legit "model/controller"
   object; leaf views (ToolCardView, PromptBubble, ThinkingDisclosure...) should take plain value inputs, not the
   controller. Naming it ViewModel vs Controller vs Store is cosmetic. [OPINION]
 - Whether MVVM is "the default in 2026" is contested: some blogs say yes, others (Apple docs) show MV. Treat as
   [OPINION]. A Medium comparison (MVVM/MV/TCA) concludes "each earns its keep in different places"; low-quality source.

1.2 **Lazy `@State` for @Observable objects (new in 27 SDK, back-deployed).** `@State` is now a macro; a reference type in
   `@State private var store = Store()` is created once for the view's lifetime instead of on every parent re-init.
   Breaking changes: assigning a `@State` in `init` before all other stored properties are initialized now errors;
   composing another property wrapper with `@State` errors; views with private `@State` no longer get a synthesized
   memberwise init. Also `@ContentBuilder` replaces per-container builders (faster type-check). [PRIMARY]
   https://developer.apple.com/documentation/Technotes/tn3211-resolving-swiftUI-source-incompatibilities-for-state-and-contentbuilder
   https://developer.apple.com/videos/play/wwdc2026/269/
   Implication: a controller owned via `@State private var controller = EngineController()` in the App/root view is
   now cheap to re-init and the pattern is blessed. [PRIMARY]

1.3 **Feature folders over layer folders once the target is non-trivial.** Broad practitioner agreement that
   Models/Views/ViewModels/Services folders stop scaling around ~30 files; group by feature (Chat/, Settings/,
   Gauges/) with shared `Components/`. [CONSENSUS, weak sources: medium/swiftprogramming; no Apple statement found]
   The claim "Apple recommends feature-based" (agenthicks.com) is unverified: that page misattributes `@StateObject`
   guidance to Apple; do not cite it. [UNCONFIRMED]
   Practical for SwiftStar: the module boundary (Kit / Engine / UI / App) already is the primary "layer" split;
   inside SwiftStarUI use feature subfolders; keep `Fixtures`/`Previews` in the same module (see 2.5).

1.4 **Local SwiftPM modules per layer/feature for build + preview speed.** Apple's own guidance: modularize "networking
   logic, utilities" into local packages. [PRIMARY]
   https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages
   Practitioner consensus: small modules with narrow dependency graphs rebuild/preview faster; previews of a view
   depend only on that view's module graph. [CONSENSUS] Caveat: more modules = more public API, more `public`
   boilerplate; with `InternalImportsByDefault`/`MemberImportVisibility` (see 4.3) this stays manageable. [OPINION]
   SwiftStar already follows the best-known shape: pure logic (Kit) -> I/O (Engine) -> UI -> executable.

1.5 **Previews must live in a library target, not the executable.** SwiftStar's Package.swift already documents this
   (executable targets of bare packages can't preview). Recent regressions to know: Xcode 26.4 broke previews in packages
   when the *target name != library product name* ("Could not find target description for ..."); fixed 26.5 b1 for
   one reporter, persisted in 26.6 for multi-target files. Safest: keep UI target name == product name
   (SwiftStarUI == SwiftStarUI, already true). Not re-verified on Xcode 27. [PRIMARY forum + UNCONFIRMED on 27]
   https://developer.apple.com/forums/thread/820802

1.6 **Xcode 27: bare `.swift` file previews.** Opening a standalone .swift file via File > Open gives a live canvas for
   `#Preview` without a project (scratch/prototype use; not for the package workflow). [Third-party, plausible;
   UNCONFIRMED against Apple release notes] https://swiftchronicle.com/features/whats-new-in-xcode-27

---------------------------------------------------------------------------------------------------
## 2. Previews through Xcode 27
---------------------------------------------------------------------------------------------------

2.1 **`#Preview` is the only supported form; `PreviewProvider` is deprecated.** Apple's Previews topic page lists
   `PreviewProvider` under "Deprecated". The body closure is `@MainActor` (so main-actor-isolated calls need no
   `MainActor.assumeIsolated`). Signatures: `Preview(_:body:)`, `Preview(_:traits:_:body:)`, `+cameras:`,
   `+arguments:`, plus scene variants (windowStyle/immersionStyle). [PRIMARY]
   https://developer.apple.com/documentation/swiftui/previews-in-xcode
   https://developer.apple.com/documentation/swiftui/preview(_:traits:_:body:)

2.2 **`#Preview("name", traits:, arguments: [T]) { value in ... }` = parameterized preview grid. LOCAL FINDING: on a
   macOS 26 deployment target it does not compile.** Apple docs: iOS 26.0 but **macOS 27.0**. Compiling with
   `-target arm64-apple-macosx26.0` gives "'Preview(_:traits:arguments:body:)' is only available in macOS 27.0 or newer";
   wrapping in `@available(macOS 27, *)` also fails ("struct cannot be more available than enclosing scope",
   macro-generated struct). So for SwiftStar (macOS 26 floor) use: (a) several named `#Preview`s, (b) one `#Preview`
   with a `ForEach`/`VStack` over a fixture array, or (c) raise the deployment target to `.v27` (tools 6.4 adds
   `.macOS(.v27)`). [LOCAL + PRIMARY]
   https://developer.apple.com/documentation/swiftui/preview(_:traits:arguments:body:)
   Note: the arguments overload is not documented as "new in Xcode 27" by Apple; the iOS availability is 26.0.
   Third-party "new in 27" claims are [UNCONFIRMED].

2.3 **`@Previewable`** (Xcode 16+, macOS 14+): put `@State`/`@Binding`-style dynamic properties inline as the first
   lines of a `#Preview` body, avoiding wrapper structs. Only valid inside a `#Preview` body (LOCAL: using it at file
   scope errors). Use for interactive bindings (toggles, sliders, text fields). [PRIMARY]
   https://developer.apple.com/documentation/swiftui/previewable()

2.4 **`PreviewModifier` + `.modifier(...)` trait for shared fixtures/environment.** `@MainActor protocol PreviewModifier`
   (macOS 15+). `static func makeSharedContext() async throws -> Context` runs once and is *cached across previews*
   that use the modifier; `func body(content:context:)` applies it (e.g. `content.environment(context)`).
   `#Preview(traits: .modifier(SampleControllerModifier())) { ChatView() }`. Apple docs example injects a
   `ModelContainer`; the same shape works for an `@Observable` controller via `.environment(controller)`.
   Caveat: the shared context is shared by reference, so previews that *mutate* it can leak state into each other;
   for mutation-heavy previews build a fresh object in `body` or in the preview closure. [PRIMARY + OPINION on caveat]
   https://developer.apple.com/documentation/swiftui/previewmodifier
   https://swiftjectivec.com/Making-Xcode-Previews-Faster-With-PreviewModifier-in-SwiftUI/ (explanatory)
   Composable: pass multiple modifiers via `traits: .modifier(A()), .modifier(B())`; define static members on
   `PreviewTrait` (`extension PreviewTrait where T == Preview.ViewTraits { static var chatFixture: Self { .modifier(...) } }`)
   so call sites read `traits: .chatFixture`. [CONSENSUS pattern, Majid/Apple WWDC24]

2.5 **Fixture/sample data placement.**
   - "Preview Content" / Development Assets are an Xcode-project concept (DEVELOPMENT_ASSET_PATHS); there is no
     SwiftPM equivalent. In a bare package, keep fixtures as ordinary Swift source in the UI module, either `#if DEBUG`
     or in a dedicated `SwiftStarPreviewSupport`-style target depended on by UI tests/previews. [CONSENSUS; no Apple
     statement for packages]
   - Prefer plain value-type fixtures (`static let sample`, `static let samples`) on the model types + a
     `PreviewModifier` that builds an `EngineController` in a *fixture/idle* state that never starts the engine
     (SwiftStar's SU.3 commit already did this: "fixture controllers never start the engine"). [OPINION, aligned with repo]
   - Don't put `#if DEBUG` around `#Preview` itself: previews are stripped from release builds automatically. [PRIMARY-ish,
     Apple docs: preview blocks are debug-only code]
   - Keep fixtures out of the executable target; they must be visible to previews in the library target and (optionally)
     to tests via `@testable import` or a public fixtures target.

2.6 **Keeping previews fast.** (all [CONSENSUS] unless noted)
   - Preview only compiles the file's target + its deps; so small modules with few/fast deps (SwiftStarUI should avoid
     pulling heavy packages into leaf views; MarkdownView is the heavy one: isolate `MarkdownText` so other views'
     previews don't link it if possible, which depends on SwiftPM dependency granularity).
   - Don't launch subprocesses/network/file I/O in preview init; use fixture controllers.
   - Use `makeSharedContext` for one-time setup. Use `.sizeThatFitsLayout` / `.fixedLayout` traits for component previews.
   - Avoid `@testable` and test targets being rebuilt by preview (old forum reports: test targets in the same package can
     break/extend preview builds). [UNCONFIRMED on Xcode 27]
   - Xcode 27 moves `ContentBuilder` unification (faster type-checking of deep view trees) which indirectly speeds
     preview builds. [PRIMARY via TN3211]

2.7 **Xcode 27 canvas features.**
   - Live Previews get *resize handles* (test interactive resizing; for macOS windows it helps verify flexible layout). [PRIMARY]
     https://developer.apple.com/videos/play/wwdc2026/269/
   - Per-`#Preview` tabs, pinning, localization preview, variants (Dynamic Type/dark/RTL) in the canvas controls.
     The Xcode MCP `RenderPreview` tool exposes `previewLocalizationOverride`, `previewVariantOverrides`,
     `previewCanvasControlOverrides`, so these are first-class. [Third-party doc of Xcode MCP; plausible, UNCONFIRMED]
     https://cuteios.dev/2026/07/14/previews-and-mcp/
   - "Preview groups": the old `Group { }` inside `PreviewProvider` is gone; use multiple named `#Preview`s. [PRIMARY]
   - I did not find an Apple doc for a macOS-specific "Resizable canvas" beyond the live-preview resize handles. [UNCONFIRMED]

2.8 **`#Playground`** (Xcode 26+): `import Playgrounds` + `#Playground { ... }` runs snippets in the canvas inside any
   .swift file (can see `private` declarations in the same file); keep it outside View declarations. A `swift play`
   SwiftPM subcommand was pitched/announced; **it is NOT installed in Swift 6.4 here** ("unable to invoke subcommand:
   swift-play"). [CONSENSUS (avanderlee) + LOCAL]
   https://www.avanderlee.com/swift/playground-macro-running-code-snippets-in-xcodes-canvas/

2.9 **Agent-facing preview tool.** Xcode 27 exposes `RenderPreview` via `mcpbridge` (renders a #Preview to a PNG;
   params: sourceFilePath, previewDefinitionIndexInFile, timeout, localization/variant overrides). It is an Xcode-host
   tool for agents, not an in-process Swift API you can call from a Swift Testing test. WWDC26 "Xcode, agents, and you"
   shows agents using preview rendering, build, and unit tests as validation tools. [PRIMARY (WWDC session) +
   third-party for parameter names]
   https://developer.apple.com/videos/play/wwdc2026/259/

---------------------------------------------------------------------------------------------------
## 3. Swift Testing (Swift 6.2 - 6.4)
---------------------------------------------------------------------------------------------------
Status of each proposal is from swift-evolution `proposals/testing/` (all [PRIMARY]).
Base URL: https://github.com/swiftlang/swift-evolution/tree/main/proposals/testing

3.1 **What shipped where.**
   - 6.1: ST-0007 Test scoping traits (`TestScoping`). 
   - 6.2: ST-0008 exit tests; ST-0009 attachments; ST-0010 `ConditionTrait.evaluate()`; ST-0011 issue-handling traits.
   - 6.3: ST-0012 value capture in exit tests; ST-0013 issue severity (`Issue.record(..., severity: .warning)`);
     ST-0014/0017 image attachments (CGImage/NSImage/etc. on Apple platforms); ST-0016 test cancellation (`Test.cancel()`).
   - 6.4: ST-0021 targeted XCTest<->Swift Testing interop (XCTAssert in Swift Testing and `#expect` in XCTest no longer silently
     misbehave; warning-severity issue by default, configurable in test plan); ST-0022 `CustomTestReflectable`;
     ST-0023 `Transferable` attachments (Apple platforms); ST-0024 per-test-case repetition.
   - NOT yet (Swift 6.5): ST-0025 tag-based filtering, ST-0026 `@TaskLocal` test trait, ST-0028 Attachment/Encodable revision.
     ST-0018 (conditional attachment saving) returned for revision.
   The swiftlee list of Swift 6.4 *language* proposals shows no testing SEs because testing proposals use a separate "ST-" track.

3.2 **Parameterized tests.** `@Test(arguments: collection)`; two collections = Cartesian product, use `zip` for pairing;
   keep argument types `Sendable`; give them `CustomTestStringConvertible` for readable names; Xcode 27 reportedly improved
   perf for suites with many parameterized cases. [PRIMARY for API; perf claim third-party UNCONFIRMED]
   https://github.com/swiftlang/swift-testing (ctx7 `/swiftlang/swift-testing`)

3.3 **Traits.** `.tags(...)` (declare with `extension Tag { @Tag static var x: Self }`), `.timeLimit(.minutes(n))`
   (granularity: whole minutes only, ST-0004), `.serialized` (ST-0003; only serializes within the annotated suite/
   parameterized test; not global), `.enabled(if:)`/`.disabled(...)`, `.bug(...)`, `.timeLimit`.
   Custom traits: conform to `TestTrait & SuiteTrait & TestScoping` and implement
   `provideScope(for:testCase:performing:)`; wrap `performing` in a `@TaskLocal` binding or setup/teardown. [PRIMARY]
   https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0007-test-scoping-traits.md
   https://swiftwithmajid.com/2025/04/15/introducing-swift-testing-scoping/ (example)
   Point-Free's `swift-dependencies` ships a `.dependencies { }` test trait built this way (use only if you adopt it).

3.4 **Exit tests** (macOS/Linux/Windows; not iOS): `await #expect(processExitsWith: .failure) { ... }`; 6.3 added capture of
   values (`[x]` capture list, Sendable/Codable). Use for `precondition`/`fatalError` paths in SwiftStarKit/Engine parsers.
   Runs the closure in a child process. [PRIMARY]

3.5 **Attachments.** `Attachment.record(value, named:)`; Data/String/URL-file/`Encodable`(JSON/plist);
   6.3 added images (`Attachment.record(cgImage, named:, as: .png)`); 6.4 adds `Transferable`. `swift test
   --attachments-path <dir>` writes them (LOCAL: flag exists; otherwise discarded). Use for failing-render dumps or
   captured engine transcripts. [PRIMARY + LOCAL]

3.6 **`#expect(throws:)` forms.** `#expect(throws: MyError.self) { }`, `#expect(throws: MyError.specific) { }` (Equatable),
   `#expect(throws: Never.self)` (record a thrown error as an issue without aborting), trailing-closure predicate form,
   and ST-0006: the macro *returns* the caught error so you can assert on its payload
   (`let e = #expect(throws: E.self) {...}`). `#require(throws:)` stops the test on mismatch. [PRIMARY]
   `Issue.record("msg", severity: .warning)` (6.3) for non-failing diagnostics; plain `Issue.record` fails the test.

3.7 **`confirmation`.** `await confirmation("evt", expectedCount: 3) { confirm in ... }`; ranges allowed (`1...`, ST-0005,
   lower bound required). Replaces XCTestExpectation for callback/event streams; the closure must complete before the
   confirmation checks (no awaiting beyond the body), so await your async source inside it. [PRIMARY]

3.8 **Test plans.** `.xctestplan` is an Xcode scheme feature; SwiftPM itself has no test plan concept. For a bare package,
   use tags + `--filter/--skip` in `swift test`, and (6.4) Xcode's test-plan "interoperability" setting for XCTest mixing.
   Whether Xcode attaches a test plan to SwiftPM-package-generated schemes was not confirmed. [UNCONFIRMED]

3.9 **`swift test` in 6.4 / Xcode 27.** [LOCAL: confirmed in `swift test --help`]
   - `--maximum-repetitions N` and `--repeat-until pass|fail` (Swift Testing suites only); per-test-*case* repetition
     (only the failing/passing case reruns, not the whole target).
     e.g. `swift test --filter EngineControllerTests --maximum-repetitions 50 --repeat-until fail` for flake hunting.
     https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0024-per-test-case-repetitions.md
   - `--attachments-path`, `--filter/--skip` (regex), `--xunit-output`, `--parallel/--no-parallel` (default no-parallel
     for XCTest process-level; Swift Testing parallelizes within the process by default), `--skip-build`.
   - **Swift Build is now the default SwiftPM build system** in 6.4 (`--build-system native` is "deprecated"). [LOCAL+PRIMARY]
     https://www.swift.org/blog/swift-6.4-released/
   - A failure summary at end of run is reported by third-party writeups (dev.to, medium); I did not isolate a flag for it
     in `--help`; treat as [UNCONFIRMED]. 

3.10 **Testing `@Observable` / `@MainActor` controllers.** (no dedicated Apple page found) 
   - Annotate the suite or tests `@MainActor` (or rely on `.defaultIsolation(MainActor.self)` on the test target; SwiftStar's
     SwiftStarIntegrationTests already does). Prefer `@Suite @MainActor struct ...Tests`. [CONSENSUS]
   - Assert on state after awaiting the async operation rather than polling; for change *streams* use
     `Observations { controller.value }` (SE-0475, Swift 6.2, async sequence of transactional values) or
     `withObservationTracking`; 6.4's SE-0506 adds `withObservationTracking(options:)` /
     `withContinuousObservationTracking` for advanced use. [PRIMARY]
   - Inject fakes through initializer parameters (protocol or closure-struct); avoid singletons. For the Engine's subprocess
     boundary, fake the process runner in Kit/Engine and test the controller without spawning. [OPINION; matches repo style]
   - `confirmation` for event callbacks; `.timeLimit(.minutes(1))` as a hang guard; `Test.cancel()` (6.3) to skip when a
     precondition (e.g. missing local model/binary) is unmet instead of failing. [PRIMARY]

3.11 **UI-level verification without XCUITest.**
   - *Preview snapshots*: `getsentry/SnapshotPreviews` (v0.19.0, 2026-09-15, active) renders every `#Preview` to PNG and
     can attach them; its test harness is XCTest-based (README), so with a Swift-Testing-only policy use it as a
     separate CI/dev step or call its renderer from your own test. [Third-party; XCTest requirement from README search
     summary, UNCONFIRMED for Swift Testing]  https://github.com/getsentry/SnapshotPreviews
   - `pointfreeco/swift-snapshot-testing` 1.19.6 (2026-09-21): supports Swift Testing (`assertSnapshot` works inside
     `@Test`, since 1.17.0 era); records image diffs; known gap: Xcode report-navigator attachments for Swift Testing
     (Discussion #909/#972, status unconfirmed). SwiftUI-on-macOS image strategy renders NSHostingView. [Third-party, PRIMARY repo]
     https://github.com/pointfreeco/swift-snapshot-testing   https://www.pointfree.co/blog/posts/146-swift-testing-support-for-snapshottesting
   - *In-house*: `ImageRenderer` (SwiftUI, macOS 13+) on `@MainActor` -> `CGImage` -> `Attachment.record(cgImage, as: .png)`
     (Swift 6.3+). No dependency, produces artifacts, can compare hash/pixels. [PRIMARY APIs; pattern is OPINION]
   - *ViewInspector* (nalexn): 0.10.5 released 2026-09-30, compatible with Swift 6.0-6.3 per search; fine for structural
     assertions but depends on SwiftUI internals so lags new SDKs; Xcode 27/@State-macro/ContentBuilder compatibility
     UNCONFIRMED. Quality Coding warns of risks. [Third-party]  https://github.com/nalexn/ViewInspector
   - *Xcode `RenderPreview` MCP tool*: agent-side visual check, not part of `swift test` (see 2.9).
   - Recommended split [OPINION, matches Apple's agent-era guidance of "tests prove behavior, previews for look"]:
     logic in Kit/Engine/controller via Swift Testing; look via previews; optional ImageRenderer/snapshot for regression.
     Apple's own WWDC26 session pairs preview rendering with unit tests, not UI snapshot tests. [PRIMARY]

---------------------------------------------------------------------------------------------------
## 4. Build settings for a SwiftPM SwiftUI app
---------------------------------------------------------------------------------------------------

4.1 **Manifest tools version.** `swift-tools-version: 6.4` adds almost nothing for you: LOCAL inspection of the 6.4
   `PackageDescription.swiftinterface` shows 6.4-gated API is only the new `.v27` platform constants (and deprecation of
   very old platform versions like macOS 12). 6.2 already added `defaultIsolation`, `strictMemorySafety`,
   `treatAllWarnings(as:)`, `treatWarning(_:as:)`. Also 6.4: SBOM generation (SE-0509), `swift package add-target-plugin`
   (SE-0511), Android in Swift Build. Staying on 6.2 is fine; bump to 6.4 only when you want `.macOS(.v27)` or want to
   require the new toolchain. [LOCAL + PRIMARY]  https://www.swift.org/blog/swift-6.4-released/

4.2 **Upcoming-feature inventory (LOCAL `swiftc -print-supported-features`).** Features that become default in the *next*
   language mode ("enabled_in: 7"): `ExistentialAny`, `InternalImportsByDefault`, `MemberImportVisibility`,
   `InferIsolatedConformances`, `NonisolatedNonsendingByDefault`, `ImmutableWeakCaptures`. Features already default in
   Swift 6 mode (so no flag needed in `.v6`): StrictConcurrency, RegionBasedIsolation, InferSendableFromCaptures,
   IsolatedDefaultValues, GlobalConcurrency, DisableOutwardActorInference, etc. Swift 7 is therefore the "approachable"
   bundle; enabling these now is the migration path. `StrictMemorySafety` is optional. [LOCAL]

4.3 **Recommended per-target swiftSettings today** (my synthesis; each item's status noted):
   ```swift
   let common: [SwiftSetting] = [
     .swiftLanguageMode(.v6),
     .enableUpcomingFeature("NonisolatedNonsendingByDefault"), // SE-0461, 6.2: nonisolated async runs on caller's actor
     .enableUpcomingFeature("InferIsolatedConformances"),      // SE-0470, 6.2: the other half of Xcode "Approachable Concurrency"
     .enableUpcomingFeature("MemberImportVisibility"),         // SE-0444, 6.1
     .enableUpcomingFeature("InternalImportsByDefault"),       // SE-0409: forces `public import` where API leaks a dependency
     .enableUpcomingFeature("ExistentialAny"),                 // SE-0335: explicit `any`
     .treatAllWarnings(as: .error),                            // tools 6.2+; see 4.5
   ]
   // UI targets add: .defaultIsolation(MainActor.self)        // SE-0466
   ```
   - "ApproachableConcurrency" is an **Xcode build setting** (`SWIFT_APPROACHABLE_CONCURRENCY`) that toggles
     NonisolatedNonsendingByDefault + InferIsolatedConformances; in SwiftPM you enable the two upcoming features by name.
     Packages created by SwiftPM do not get it automatically. [PRIMARY SEs + CONSENSUS (Donny Wals/useyourloaf)]
     https://useyourloaf.com/blog/approachable-concurrency-in-swift-packages/
     https://www.donnywals.com/what-is-approachable-concurrency-in-xcode-26/
   - Apply `.defaultIsolation(MainActor.self)` only to UI/executable targets (SwiftStar already does). Keep Kit/Engine on
     default (nonisolated) isolation so they stay pure/Sendable; NonisolatedNonsendingByDefault is most valuable there
     because async helpers inherit caller isolation rather than hopping to the global executor. [CONSENSUS]
   - Known sharp edges with MainActor default isolation: `Codable`/`CodingKey` conformances and generated `Bundle.module`
     become MainActor-isolated; mark pure data types `nonisolated` (or put them in the non-MainActor Kit target).
     Test targets that import UI types need the same `defaultIsolation` (SwiftStarIntegrationTests already mirrors it).
     [CONSENSUS (useyourloaf)]
   - `MemberImportVisibility` fixes the "extension member visible only because some other file imported the module" bug
     class; low risk. `InternalImportsByDefault` is higher churn (add `public import` for re-exported types); gain is real
     for a multi-module package. `ExistentialAny` is churn for little behavioral benefit now. All three are [OPINION]
     on priority; their availability is [LOCAL].
   - `ImmutableWeakCaptures` (`weak let` captures) is also a 7-mode upcoming feature; a third-party recap says 6.4 ships `weak let`; low
     value for a small app. [LOCAL list; value OPINION]

4.4 **Strict memory safety** (SE-0458, 6.2): `.strictMemorySafety()` flags every unsafe construct; `unsafe` expression
   acknowledgement. For SwiftStar it matters mostly in SwiftStarEngine (subprocess/pipe/`UnsafeMutablePointer`/
   `posix_spawn` code). Consider enabling only on Kit + Engine, not UI. [PRIMARY + OPINION on scope]
   Swift 6.4 adds `@diagnose(Group, as: error|warning|ignored, reason:)` (SE-0522, experimental flag `SourceWarningControl`
   per the proposal header; shipped in 6.4) for scoped suppression, plus target-wide `EmbeddedRestrictions` warnings. [PRIMARY]
   https://github.com/swiftlang/swift-evolution/blob/main/proposals/0522-source-warning-control.md

4.5 **Warnings as errors.** Two options: (a) `.treatAllWarnings(as: .error)` in `swiftSettings` (tools 6.2+;
   per-target, local) + `.treatWarning("Name", as: .warning)` to demote a specific group; (b) `-Xswiftc -warnings-as-errors`
   on the CI command line (does not affect dependencies' diagnostics being compile-only but may break on third-party
   package warnings). Community norm: enforce in CI and in the *manifest for your own targets*, not for dependencies;
   avoid `unsafeFlags(["-warnings-as-errors"])` since `unsafeFlags` blocks use as a dependency (irrelevant for an app
   root package but still discouraged). `@diagnose` gives per-declaration escape hatches in 6.4. [CONSENSUS; the
   treatAllWarnings/treatWarning APIs are LOCAL-verified in the 6.4 PackageDescription interface]
   Pitfall: enabling warnings-as-errors together with a forked git dependency (MarkdownView) is fine as long as only your
   targets get the setting.

4.6 **Swift Build default (6.4)** can change diagnostics/ordering vs 6.2's native build; run `swift build --build-system
   native` as a fallback comparison if a build behaves differently. [LOCAL]

4.7 **Xcode 27 project-level facts that affect a bare package.** Intel: `ARCHS_STANDARD` drops `x86_64` once the deployment
   target is macOS 27+; `-ld_classic` removed; Clang module names must be unique per scan. (Third-party recap of release
   notes; Apple page was not retrievable.) macOS 26 target is unaffected. [UNCONFIRMED]
   https://dev.to/arshtechpro/xcode-27-everything-developers-need-to-know-6lh

---------------------------------------------------------------------------------------------------
## Suggested actions for SwiftStar (derived, not sourced)
---------------------------------------------------------------------------------------------------
 1. Keep MV: leaf views take values; `EngineController` stays the single `@Observable` app object, owned via `@State` at root.
 2. In SwiftStarUI add one `PreviewModifier` (e.g. `.sampleController`) returning an idle fixture controller + 3-4 named
    `#Preview`s per view (empty/streaming/error/long text); use `ForEach` not `arguments:` unless you move to macOS 27.
 3. Add `NonisolatedNonsendingByDefault`, `InferIsolatedConformances`, `MemberImportVisibility` (+ optionally
    `InternalImportsByDefault`) via a shared `let common` array; leave tools at 6.2 unless you want `.v27`.
 4. Add `.treatAllWarnings(as: .error)` for own targets; consider `strictMemorySafety()` for SwiftStarEngine.
 5. Testing: `@MainActor` suites for controller; custom `TestScoping` trait for fixture setup; `Attachment.record` of
    `ImageRenderer` output for render regressions; `swift test --maximum-repetitions N --repeat-until fail` for flakes.
