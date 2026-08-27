import Foundation

/// P9: the pure `request → result` mapping for the bidirectional tool wire
/// (D3). On a `.toolRequest` the host app answers with a `tool_result` line;
/// this type carries the logic that is **pure where possible** — the consent
/// check (D1/D6: the same rules P7 put in the engine, enforced host-side), the
/// condensation of the result (D3, via `ToolResultCondenser`), the
/// host-authoritative facts (D5), and the `tool_result` JSON line (D2). The
/// **side-effecting execution** (reading files, running bash) lives in the app
/// target and is injected as a closure, so the mapping is a pure function over
/// its inputs and is unit-testable with a fake executor.
///
/// The consent model (D1/D6): file tools (`read`/`more`/`write`/`list`/`edit`/
/// `search`) are confined to the workspace grant — a path that resolves outside
/// the workspace (an absolute path, or a `..` escape) is refused; shell tools
/// (`bash`/`bash_status`/`bash_stop`) require `shellAllowed`; everything else
/// (unknown tools, and the web tools `google_search`/`visit_page`, which are
/// not part of the workspace/shell consent) is refused. The path confinement is
/// pure: it resolves `..` via `URL.standardizedFileURL` (no filesystem I/O, so
/// no symlink resolution — a symlink under the workspace that points outside is
/// not caught here; the engine's `realpath`-based confinement catches that, and
/// a fuller host match would resolve symlinks in the executor). This catches the
/// common escapes (absolute paths, `..`) without I/O.

/// The consent verdict for one tool request (D1/D6): the host may proceed (and
/// the executor runs) or refuse (consent denied — the wire returns `ok:false`
/// with the reason, and no execution runs). Pure value.
public enum ToolConsent: Equatable, Sendable {
    case proceed(ToolExecutionRequest)
    case refuse(String)
}

/// The consent-cleared shape the app's executor consumes. Pure value; the
/// `consent` check produces it. `resolvedPath` is the confined absolute path
/// for file tools (the workspace-rooted, `..`-resolved path); it is `nil` for
/// shell tools (which have no confined path — they run in the workspace cwd).
public struct ToolExecutionRequest: Equatable, Sendable {
    public let name: String
    public let params: [ToolParam]
    public let workspace: URL
    public let resolvedPath: String?

    public init(name: String, params: [ToolParam], workspace: URL, resolvedPath: String?) {
        self.name = name
        self.params = params
        self.workspace = workspace
        self.resolvedPath = resolvedPath
    }
}

/// The raw result of executing one tool, before condensation (D3): the output
/// text and the host-authoritative facts (D5) — the actual mutation paths, the
/// command exit status, an output digest, and whether validation ran. The
/// side-effecting executor returns this; the responder condenses the text and
/// keeps the facts. `ok` is the executor's own verdict: `true` when the tool ran
/// (its result text is `text`, even if the tool itself reported an error);
/// `false` when the host could not run it (e.g. a missing file the executor
/// refused to fabricate a result for). A consent refusal never calls the
/// executor and is a separate `ok:false` path.
public struct ToolExecutionResult: Equatable, Sendable {
    public let ok: Bool
    public let text: String
    public let mutations: [String]
    public let exitStatus: Int?
    public let outputDigest: String?
    public let validationRan: Bool

    public init(ok: Bool, text: String, mutations: [String] = [],
                exitStatus: Int? = nil, outputDigest: String? = nil,
                validationRan: Bool = false) {
        self.ok = ok
        self.text = text
        self.mutations = mutations
        self.exitStatus = exitStatus
        self.outputDigest = outputDigest
        self.validationRan = validationRan
    }
}

/// The wire response to one `tool_request` (D2 + D5): the result line's
/// `idx`/`ok`/`s` (the condensed result text) plus the host-authoritative facts
/// the responder records into the open `TurnOutcomeBuilder`. Pure value; the
/// `respond` mapping produces it and `resultLine(_:)` serializes it.
public struct ToolCallbackResponse: Equatable, Sendable {
    public let idx: Int
    public let ok: Bool
    public let s: String
    public let mutations: [String]
    public let exitStatus: Int?
    public let outputDigest: String?
    public let validationRan: Bool

    public init(idx: Int, ok: Bool, s: String, mutations: [String] = [],
                exitStatus: Int? = nil, outputDigest: String? = nil,
                validationRan: Bool = false) {
        self.idx = idx
        self.ok = ok
        self.s = s
        self.mutations = mutations
        self.exitStatus = exitStatus
        self.outputDigest = outputDigest
        self.validationRan = validationRan
    }
}

/// The pure `request → result` mapping (D3). The side-effecting execution lives
/// in the app target; the responder's logic is pure — given a deterministic
/// `execute` closure, `respond` is a pure function over its inputs.
public enum ToolCallbackResponder {

    /// The tool families the host executes (D6): file tools confined to the
    /// workspace grant, and shell tools gated by the shell toggle. Web tools
    /// (`google_search`/`visit_page`) and anything else are not host-executed.
    private static let fileTools: Set<String> = ["read", "more", "write", "list", "edit", "search"]
    private static let shellTools: Set<String> = ["bash", "bash_status", "bash_stop"]
    /// P10 (D2): the file tools that *mutate* the worktree (versus the read
    /// aids `read`/`more`/`list`/`search`). A dispatched attempt confines these
    /// to `writableFiles`; the read aids stay free.
    private static let mutatingTools: Set<String> = ["write", "edit"]

    /// The pure consent check (D1/D6): given the request, the workspace grant,
    /// and the shell toggle, decide whether the host may execute. File tools are
    /// confined to `workspace` (an absolute path or a `..` escape is refused);
    /// shell tools require `shellAllowed`; unknown tools and the web tools are
    /// refused. No I/O — the path is resolved via `URL.standardizedFileURL`
    /// (resolves `..`, not symlinks). Returns `.proceed` with the
    /// consent-cleared `ToolExecutionRequest` (carrying the confined
    /// `resolvedPath` for file tools), or `.refuse` with a reason.
    /// `writableFiles` (P10/D2, default `nil`): when set, a dispatched attempt
    /// revision-checks each *mutating* file tool (`write`/`edit`) against the
    /// contract — a path whose workspace-relative form is not in the set is
    /// **refused host-side, not executed** (the host returns `ok:false`; the
    /// engine never sees the tool). The read aids (`read`/`more`/`list`/
    /// `search`) are unaffected — the worker may read anywhere in the
    /// workspace. `nil` (the normal Agent-tab mode) disables the check.
    public static func consent(
        idx: Int, name: String, params: [ToolParam],
        workspace: URL, shellAllowed: Bool,
        writableFiles: [String]? = nil
    ) -> ToolConsent {
        let wsStd = workspace.standardizedFileURL

        if Self.fileTools.contains(name) {
            let rawPath = params.first(where: { $0.name == "path" })?.value ?? "."
            let resolved: URL
            if rawPath.hasPrefix("/") {
                // An absolute path is resolved as-is (the engine's realpath
                // treats it as absolute); it must already be inside the
                // workspace or it is refused.
                resolved = URL(fileURLWithPath: rawPath).standardizedFileURL
            } else {
                resolved = wsStd.appendingPathComponent(rawPath).standardizedFileURL
            }
            guard resolved.path == wsStd.path || resolved.path.hasPrefix(wsStd.path + "/") else {
                return .refuse("refused: path is outside the workspace grant")
            }
            // P10 (D2): dispatched-mode revision check. A mutating tool may
            // only touch a path whose workspace-relative form is in
            // `writableFiles`; the read aids are unaffected. The host refuses
            // (ok:false, not executed) — the engine never sees it.
            if let writableFiles, Self.mutatingTools.contains(name) {
                let rel = Self.workspaceRelative(resolved.path, workspace: wsStd.path)
                guard writableFiles.contains(rel) else {
                    return .refuse("refused: path is outside the writable-files contract")
                }
            }
            return .proceed(ToolExecutionRequest(
                name: name, params: params, workspace: wsStd, resolvedPath: resolved.path))
        }

        if Self.shellTools.contains(name) {
            guard shellAllowed else {
                return .refuse("refused: shell is not allowed (--shell off)")
            }
            return .proceed(ToolExecutionRequest(
                name: name, params: params, workspace: wsStd, resolvedPath: nil))
        }

        // P11 (D3): `dispatch` is a host-control tool — the host enqueues a
        // worker. A well-formed dispatch carries a non-empty taskText; the
        // actual enqueue is the controller's job (no filesystem confinement
        // applies — it is not a file tool).
        if name == "dispatch" {
            let taskText = params.first(where: { $0.name == "taskText" })?.value ?? ""
            guard !taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .refuse("refused: dispatch requires a non-empty taskText")
            }
            return .proceed(ToolExecutionRequest(
                name: name, params: params, workspace: wsStd, resolvedPath: nil))
        }

        return .refuse("refused: unknown or unsupported tool: \(name)")
    }

    /// The consent-check step shared by both `respond` overloads (item 3, P22
    /// cleanup): either a finished response (a consent refusal, or `dispatch`'s
    /// host-control admit — neither calls `execute`) or the consent-cleared
    /// request for the caller to run through its own (sync or async)
    /// `execute` closure.
    private enum PreExecute {
        case response(ToolCallbackResponse)
        case execute(ToolExecutionRequest)
    }

    private static func preExecute(
        idx: Int, name: String, params: [ToolParam],
        workspace: URL, shellAllowed: Bool, writableFiles: [String]?
    ) -> PreExecute {
        // P11 (D3): `dispatch` is a host-control tool — the host enqueues the
        // worker. The responder admits a well-formed call and returns ok:true
        // (the controller overwrites `s` with "dispatched as worker N" after
        // enqueueing). No `execute` runs.
        if name == "dispatch" {
            switch consent(idx: idx, name: name, params: params,
                           workspace: workspace, shellAllowed: shellAllowed,
                           writableFiles: writableFiles) {
            case .refuse(let reason):
                return .response(ToolCallbackResponse(idx: idx, ok: false,
                    s: ToolResultCondenser.condense(reason)))
            case .proceed:
                return .response(ToolCallbackResponse(idx: idx, ok: true, s: "dispatched"))
            }
        }
        switch consent(idx: idx, name: name, params: params,
                       workspace: workspace, shellAllowed: shellAllowed,
                       writableFiles: writableFiles) {
        case .refuse(let reason):
            return .response(ToolCallbackResponse(
                idx: idx, ok: false, s: ToolResultCondenser.condense(reason),
                mutations: [], exitStatus: nil, outputDigest: nil, validationRan: false))
        case .proceed(let req):
            return .execute(req)
        }
    }

    /// The pure `request → result` mapping: consent-check, execute (the
    /// injected, side-effecting closure), condense, and assemble the response.
    /// A consent refusal returns `ok:false` with the condensed reason and does
    /// **not** call `execute`; a proceed calls `execute` and condenses its
    /// `text` via `ToolResultCondenser`, carrying the host facts straight
    /// through. Pure given a deterministic `execute`.
    /// `writableFiles` (P10/D2, default `nil`): thread the dispatched attempt's
    /// revision check through `consent`. `nil` (the normal Agent-tab call) keeps
    /// the pre-P10 behavior — mutating tools proceed anywhere in the workspace.
    public static func respond(
        idx: Int, name: String, params: [ToolParam],
        workspace: URL, shellAllowed: Bool,
        writableFiles: [String]? = nil,
        execute: (ToolExecutionRequest) -> ToolExecutionResult
    ) -> ToolCallbackResponse {
        switch preExecute(idx: idx, name: name, params: params,
                          workspace: workspace, shellAllowed: shellAllowed,
                          writableFiles: writableFiles) {
        case .response(let response):
            return response
        case .execute(let req):
            let raw = execute(req)
            return ToolCallbackResponse(
                idx: idx, ok: raw.ok, s: ToolResultCondenser.condense(raw.text),
                mutations: raw.mutations, exitStatus: raw.exitStatus,
                outputDigest: raw.outputDigest, validationRan: raw.validationRan)
        }
    }

    /// The async twin of `respond` (item 3, P22 cleanup): identical mapping,
    /// but awaits an async `execute` closure. `AgentController` routes both
    /// its orchestrator and pool-worker tool requests through this overload
    /// now that its host executor can run a `bash` call via
    /// `SubprocessRunner`'s async `run` without blocking the MainActor.
    public static func respond(
        idx: Int, name: String, params: [ToolParam],
        workspace: URL, shellAllowed: Bool,
        writableFiles: [String]? = nil,
        execute: (ToolExecutionRequest) async -> ToolExecutionResult
    ) async -> ToolCallbackResponse {
        switch preExecute(idx: idx, name: name, params: params,
                          workspace: workspace, shellAllowed: shellAllowed,
                          writableFiles: writableFiles) {
        case .response(let response):
            return response
        case .execute(let req):
            let raw = await execute(req)
            return ToolCallbackResponse(
                idx: idx, ok: raw.ok, s: ToolResultCondenser.condense(raw.text),
                mutations: raw.mutations, exitStatus: raw.exitStatus,
                outputDigest: raw.outputDigest, validationRan: raw.validationRan)
        }
    }

    /// The workspace-relative form of an absolute `resolvedPath` (P10/D2): the
    /// path with the workspace prefix stripped, so the revision check can
    /// compare it against `writableFiles` (which are worktree-relative). A path
    /// that is the workspace root itself yields `""`; a path outside the
    /// workspace (already refused by the grant check) is returned as-is.
    private static func workspaceRelative(_ absPath: String, workspace ws: String) -> String {
        if absPath == ws { return "" }
        if absPath.hasPrefix(ws + "/") { return String(absPath.dropFirst(ws.count + 1)) }
        return absPath
    }

    /// The `tool_result` JSON line (D2) to write to the agent's stdin:
    /// `{"t":"tool_result","idx":N,"ok":...,"s":"..."}`. Keys are sorted
    /// (`.sortedKeys`) for deterministic output; `s` is JSON-escaped by
    /// `JSONSerialization` (quotes/backslashes/newlines are safe).
    public static func resultLine(_ response: ToolCallbackResponse) -> String {
        let obj: [String: Any] = [
            "t": "tool_result",
            "idx": response.idx,
            "ok": response.ok,
            "s": response.s,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            // Unreachable for these value types, but fail closed: an empty `s`
            // and ok:false never hang the agent waiting for a real result.
            return #"{"idx":\#(response.idx),"ok":false,"s":"","t":"tool_result"}"#
        }
        return json
    }
}
