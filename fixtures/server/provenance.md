# `golden.sse` — capture notes (P1 first capture)

This fixture is a **verbatim, byte-for-byte copy of `ds4-server`'s stdout** (an SSE response
stream) from real `/v1/chat/completions` streaming requests against the P1 pinned submodule
SHA. Nothing in it was hand-written or reformatted. This is the **first** SSE capture from
`ds4-server` — no prior SSE fixture exists anywhere in the project.

## Provenance

- Submodule (`external/ds4`) SHA: `b3d2b5e0d4b15f223d333921797b4a6fd018aeae`
  (branch `swiftstar-integration`, tip of the fork at capture time; the SwiftStar gitlink pins
  this exact SHA — confirmed by `git submodule status` and `git -C external/ds4 rev-parse HEAD`).
- Built with: `just engine` (which runs `git submodule update --init external/ds4` then
  `make -C external/ds4 ds4-server ds4-agent`). Binary run in place,
  `external/ds4/ds4-server`.
- Server command line actually run:

  ```
  ./ds4-server -m ~/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf \
    -c 32768 --host 127.0.0.1 --port 8000
  ```

  (no `DS4_METAL_*_SOURCE` vars needed — the server has no `--chdir`, so the relative
  `metal/*.metal` defaults resolve from the submodule checkout. `DS4_LOCK_FILE` was set to
  `/tmp/ds4-capture-server.lock` so the session didn't collide with any other `ds4` instance's
  `/tmp/ds4.lock`.)

- Model file used: `laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf` (Laguna S 2.1, 48 GiB) at
  `~/projects/ds4/gguf/`.
- Requests sent with curl (`-sS -N`, `stream:true`), stdout piped through `tee` (byte-for-byte
  wire copy) into a one-timestamp-per-line sidecar (`date +%s%N` per newline-terminated line).

## Two captures taken; `golden.sse` is canonical

1. **Short capture** (kept as `golden.short.sse` + sidecar): one request —

   ```
   {"messages":[{"role":"user","content":"Explain, in three sentences, why the sky is blue."}],"stream":true}
   ```

   674 wire lines; 336 `data: {...}` chunks. Shows the minimal shape: role delta, then
   `reasoning_content` + `content` deltas, then `finish_reason` and `data: [DONE]`.

2. **Rich capture** (`golden.sse`, canonical): one request —

   ```
   {"messages":[{"role":"user","content":"Five people (Alice, Bob, Carol, Dave, Eve) occupy houses numbered 1 to 5, one each. Constraints: Alice is not in house 1 or house 5. Bob is directly to the right of Carol. Dave is in an even-numbered house. Eve is somewhere to the left of Bob. Carol is not in house 3. Work out every assignment that satisfies all constraints, showing your deductions."}],"stream":true}
   ```

   6312 wire lines; 3155 `data: {...}` chunks: 2590 chunks carrying `reasoning_content` deltas
   and 563 carrying `content` deltas, ending in `finish_reason` and `data: [DONE]`. This is the
   richest single capture, so it is the committed canonical fixture.

## Event shape observed

Each `data: {...}` chunk:

```
{"id":"chatcmpl-2","object":"chat.completion.chunk","created":<epoch>,"model":"laguna-s-2.1",
 "choices":[{"index":0,"delta":{...},"finish_reason":null}]}
```

- First chunk: `"delta":{"role":"assistant"}`.
- Reasoning tokens: `"delta":{"reasoning_content":"<token>"}` (Laguna emits reasoning; both
  captures show it).
- Text tokens: `"delta":{"content":"<token>"}`.
- Final chunk: `"finish_reason":"stop"` (then a blank line), followed by the terminal
  `data: [DONE]` line, which is the last non-blank line of the stream.
- `id` is constant within each request and **increments per request served by the process**:
  `chatcmpl-1` in `golden.short.sse` (the first request of the server session), `chatcmpl-2` in
  the canonical `golden.sse` (the second request). Do not assume a fixed id across requests.
- `created` is **epoch seconds at emit time, advancing across the stream** (~once per second),
  not a constant request epoch: the canonical capture has 57 distinct values spanning 56 s,
  matching its sidecar's 56.28 s span exactly (first/last sidecar seconds equal first/last
  `created` values). Unlike OpenAI's SSE shape (constant request-creation time), ds4-server
  stamps each chunk with its emit second — do not assume it is fixed within a request.

## Gaps — what was not captured, and why

- **Only `/v1/chat/completions` with `stream:true` was exercised.** This is the one endpoint and
  mode the plan calls for and the only one SwiftStar will consume at P1. No non-streaming
  response, no other endpoints (e.g. `/v1/models`), no multi-request session continuity.
- **No `finish_reason` other than `stop`.** No tool-call/function-call finish (the server does
  not expose agent tools — it is plain chat), no length/context exhaustion, no abort.
- **SSE comment/keepalive lines were not observed.** The server emits pure `data:` chunks; no
  `:` comment lines or `event:` fields appeared in either capture.

## Sanity checks run

- Wire line counts match the sidecar exactly (`golden.sse` 6312 = sidecar 6312;
  `golden.short.sse` 674 = sidecar 674).
- Every `data: {...}` chunk parses as valid JSON (all 3155 chunks of the canonical capture
  spot-checked programmatically — zero failures; the short capture's chunks also parse).
- Both streams end with `data: [DONE]` as the final non-blank line.
- The canonical capture's first chunk carries `"role":"assistant"`, its last data chunk carries
  `"finish_reason":"stop"`, and `reasoning_content` deltas are present (2590 chunks) alongside
  `content` deltas (563 chunks).
