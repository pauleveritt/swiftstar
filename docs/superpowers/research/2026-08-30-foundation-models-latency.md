# Apple Foundation Models latency research (2026-08-30)

This note records the latency measurements and optimization findings from the
small Foundation Models CLI experiment in `/tmp/foundation-models-chat`.

## What the sample measures

The timed interval starts immediately before `session.respond(to:)` and ends
when the complete response is returned. It therefore includes the request's
prompt processing and output generation, but not process launch, framework
import, session construction, or the explicit `prewarm` call.

Observed on 2026-08-30, macOS 26.6.2 / Xcode 26.6 / arm64 Mac17,7, release
build, after adding the documented 1.1-second prewarm lead time:

- First request after the prewarm request: **1.410 s**.
- Second request in the same session: **1.015 s**.
- Second-turn reduction in this run: **28.0%**.

This is one observation, not a hardware-independent benchmark. The model
generated five sentences for both lookup requests. The earlier run requested
prewarm and immediately called `respond`; its first/second values were 1.925 s
and 0.969 s, respectively, so those numbers should not be treated as a
controlled comparison with the lead-time run.

### Follow-up rerun

At 17:29:49 EDT, with the same 1.1-second prewarm lead time, a second run
measured **1.799 s** for the first request and **1.127 s** for the warmed second
request, a **37.4%** reduction from the first turn. The prewarm call itself
returned in **0.002 s**; that is request/dispatch overhead, not cache-build
completion. The variation from the earlier lead-time run (1.410 s / 1.015 s)
means this sample does not establish a causal prewarm speedup. It does confirm
that the revised sample continues to run correctly with the documented lead
time.

The first request establishes a real transcript entry. The second request is
the warmed measurement in the same `LanguageModelSession`; it is not an
independent cold request. Run-to-run comparisons should use the same build,
OS, model availability state, power state, prompt, and response length.

## Prefill and KV cache

For a transformer, prefill processes the input tokens before decode begins.
Longer instructions, tools, and conversation history increase this work. The
decode phase then generates output tokens, so response length and token rate
also affect end-to-end latency.

`LanguageModelSession.prewarm(promptPrefix:)` asks Foundation Models to build
cached state for the stable session prefix (including instructions and the
provided prefix) before the request arrives. This can reduce first-token
latency when the actual prompt shares that prefix. Prewarming is not the same
as generating a response, and its cost is intentionally outside the reported
request timings. The API returns immediately; the CLI's 0.001 s “prewarm
requested” value is dispatch overhead, not proof that cache construction has
completed. The sample now deliberately waits 1.1 seconds before each first
request so prewarm has a reasonable opportunity to do work.

The session retains a transcript between turns. That gives later turns a
contextual KV-cache opportunity, but the cache is only useful while the prefix
remains compatible. Changing instructions, tools, model configuration, or
earlier transcript content can invalidate or reduce the hit. A longer
transcript also means more context to account for even when some prefix is
cached. Recreating a session for every prompt discards this benefit.

Apple’s Foundation Models documentation recommends the Foundation Models
Instrument in Instruments for token-level analysis. In particular, compare
cached input tokens with total input tokens to estimate cache hit rate and
look for cache invalidation. The CLI’s wall-clock values alone cannot separate
prefill, cache reuse, decode, asset loading, and scheduling.

## Highest-value ways to speed it up

1. **Prewarm early and keep the session alive.** Call `prewarm()` when there
   is a strong signal that interaction is imminent, ideally at least one second
   before `respond` or `streamResponse`. Avoid constructing a new session for
   every request. Prewarm is opportunistic: background execution and system
   load can delay asset/model loading.
2. **Protect the stable prefix.** Put invariant instructions and tool
   definitions first. Put conditional or frequently changing instructions at
   the end. Append new transcript turns rather than rewriting earlier
   content. Any changed token invalidates the dependent cache suffix, so a
   small change near the beginning can force extensive reprocessing.
3. **Keep input context compact.** Large instructions, tool schemas, attached
   data, and long transcripts increase prefill time and memory traffic. Summarize
   old turns or create a contextual session containing only the entries needed
   for the next task when that quality trade-off is acceptable.
4. **Bound output deliberately.** `GenerationOptions` supports
   `maximumResponseTokens`. Set a limit appropriate to the product response;
   fewer generated tokens generally means less decode time. Leave enough headroom
   to avoid truncation, since retries or repair prompts cost more than the
   saved tokens.
5. **Stream for perceived speed.** `streamResponse` can display the first
   generated content sooner. It improves time-to-first-content, not necessarily
   total completion time. Apple specifically recommends non-streaming
   `respond` in background execution to reduce the chance of rate-limit errors.
6. **Minimize tool work.** Every tool definition adds prompt material, and each
   tool invocation adds a tool execution interval plus another model turn.
   Expose only relevant tools, keep their schemas small, and avoid serial tool
   chains when one operation can answer the request.

## Classic latency slowdowns

- **Cold model/assets:** process launch, first framework use, model loading,
  asset loading, and Apple Intelligence/model readiness can dominate a first
  request. Keep a process/session warm when low latency matters.
- **Long prefill:** verbose system instructions, tool catalogs, examples,
  retrieved documents, and accumulated chat history all increase input-token
  processing before decoding can begin.
- **Cache misses:** changing instructions/tools, changing content in the
  middle of a prefix, recreating a session, or using a mismatched prewarm
  prefix removes KV-cache reuse. Stable content should precede dynamic content.
- **Long decode:** response length is a direct cost. “Explain everything,”
  unconstrained lists, and retries increase generated tokens; sampling choices
  affect output behavior but are not a substitute for an output limit.
- **Tool and application overhead:** database/network/file calls, serial tool
  calls, JSON/schema validation, UI rendering, and synchronous work on the
  critical path can make end-to-end latency much larger than model inference.
- **Resource contention:** thermal throttling, battery/power policy, memory
  pressure, competing CPU/GPU/ANE work, background execution, and concurrent
  sessions can reduce throughput or delay model loading.
- **Measurement noise:** a single wall-clock sample conflates prefill, cache
  reuse, decode, model loading, tools, scheduling, and printing. CLI process
  startup and terminal output should be excluded when measuring request
  latency.

## How to verify the bottleneck

Use Apple’s Foundation Models Instrument in Instruments. Its timeline has
separate lanes for Session, Request, Instructions, Model Inference, Tool, and
Model Loading. Compare cached input tokens with total input tokens to estimate
KV-cache hit rate. For user experience, also measure time to first streamed
content and time to complete response; for service quality, collect repeated
warm runs and report median and tail latency rather than one value.

## Multi-turn result

The second session deliberately asks the model to ask one clarifying question
on turn 1. Turn 2 supplies the missing constraints and asks the model to
continue. This demonstrates that a single `LanguageModelSession` carries
conversation state across `respond(to:)` calls; it is a genuine multi-turn
interaction rather than two unrelated prompts.

## Sources consulted

- [Optimizing key-value caching in language model sessions](https://developer.apple.com/documentation/foundationmodels/optimizing-key-value-caching-in-language-model-sessions)
- [Analyzing the runtime performance of your Foundation Models app](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app)
- [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession) and `SystemLanguageModel`, consulted via Context7.
