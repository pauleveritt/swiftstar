import AppKit
import Foundation
import Observation
import SwiftStarEngine
import SwiftStarKit

/// A switch to another project, optionally resuming one of its
/// conversations (SU.7b).
public struct ProjectSwitch: Equatable, Sendable {
    public let folder: URL
    public let resuming: Conversation?

    public init(folder: URL, resuming: Conversation?) {
        self.folder = folder; self.resuming = resuming
    }
}

/// Thin app-side owner of one `EngineSession`: it resolves the executable,
/// picks the source repository, and feeds engine events to the transcript and
/// metrics folds. The logic lives in the tested Kit types.
@Observable
public final class EngineController {
    /// Every session rule (phase, busy/stop/pending, labels) lives in the
    /// model; the controller forwards to it and owns the process.
    private(set) var model = EngineSessionModel()
    var transcript: EngineTranscript { model.transcript }
    var metrics: EngineMetricsState { model.metrics }
    var phase: EngineSessionPhase { model.phase }
    var composer: EngineComposer { model.composer }
    var canAnalyze: Bool { model.canAnalyze }
    var analysis: EngineAnalysis? { model.analysis }
    public var isActive: Bool { model.phase.isActive }
    /// Makes the session report from the executable and a session
    /// directory (AN.2, AN.4); tests replace it.
    @ObservationIgnored var reportLoader: (String, URL) async -> Result<String, SessionReportFailure> = {
        await SessionReportLoader.load(executable: $0, sessionDirectory: $1)
    }
    /// The git root the current or last session worked from (its `--source`),
    /// kept after the session ends so its tool cards still resolve.
    private(set) var source: URL? {
        didSet { rebuildFileLinks() }
    }
    /// The engine's candidate worktree while its session runs, from the
    /// session's `receipt.json` at each pause (SU.16, D3); nil otherwise.
    private(set) var worktree: URL? {
        didSet { if worktree != oldValue { rebuildFileLinks() } }
    }
    /// The transcript's file links (SU.16): rebuilt, with a fresh cache,
    /// whenever the checkout, the worktree or the tracked files change.
    private(set) var fileLinks: FileLinkLookup?

    private func rebuildFileLinks() {
        fileLinks = source.map { FileLinkLookup(source: $0, worktree: worktree, files: workspaceFiles) }
    }
    var workspace: URL? {
        didSet {
            guard let workspace else { return }
            persist(workspace.path, .workspace)
        }
    }

    /// The most recent ended session's directory, kept across launches
    /// (SU.6c, D2).
    private(set) var lastSessionDirectory: URL?

    /// `ds4-dogfood apply <id>` for the last session, while its directory
    /// still exists.
    var applyCommand: String? {
        guard let dir = lastSessionDirectory, FileManager.default.fileExists(atPath: dir.path) else { return nil }
        return EngineCommand.applyCommand(sessionDirectory: dir)
    }

    /// Copies the last session's apply command and says so in the transcript.
    public func copyApplyCommand() {
        guard canCopyApplyCommand, let command = applyCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        model.apply(.notice("Copied: \(command)"))
    }

    /// Whether a last session's apply command can be copied (the menu item):
    /// never while a session runs, since applying changes the checkout under
    /// it (ds4-engine TUI.21's non-goal).
    public var canCopyApplyCommand: Bool { !isActive && applyCommand != nil }

    // MARK: conversations (SU.7a)

    /// This project's conversations, newest first; empty until loaded and
    /// with no workspace.
    private(set) var conversations: [Conversation] = []
    @ObservationIgnored private var sessionListNote: String?
    /// Roots whose "Session list unavailable" note was shown: once each.
    @ObservationIgnored private var notedSessionListRoots: Set<String> = []

    /// The conversation the running session belongs to, if it's listed;
    /// nil once it has ended, so that conversation can be resumed again.
    var currentConversationID: String? {
        guard isActive else { return nil }
        return Conversations.current(sessionIDs: model.sessionIDs, in: conversations)?.id
    }

    /// The running conversation, for the window's title (SU.11, D2).
    var currentConversation: Conversation? {
        currentConversationID.flatMap { id in conversations.first { $0.id == id } }
    }

    /// The session id the list last reloaded for, so an unlisted one reloads
    /// it once, not on every event.
    @ObservationIgnored private var listReloadedFor: String?

    /// Resuming mid-turn ends the turn: the view asks first.
    var resumeNeedsConfirmation: Bool { transcript.isBusy }

    /// The git root the list is for: the workspace's, else the folder itself.
    private var conversationRoot: URL? { workspace.map { ProjectRoot.locate(anchor: $0) ?? $0 } }

    /// Loads the list for the current workspace. A result for a workspace
    /// that has since changed is dropped; a failure keeps the list and notes
    /// why once per root.
    func reloadConversations() async {
        guard !isFixture else { return }
        // The `@` picker's files reload with the list, at the same moments
        // (SU.14, D5): the list's first show, a switch, a session's end.
        Task { await reloadWorkspaceFiles() }
        guard let root = conversationRoot, let path = resolveExecutablePath() else {
            conversations = []
            return
        }
        let result = await SessionListLoader.load(executable: path, source: root)
        guard conversationRoot?.standardizedFileURL.path == root.standardizedFileURL.path else { return }
        switch result {
        case .success(let entries):
            conversations = Conversations.group(entries)
            sessionListNote = nil
        case .failure(let error):
            sessionListNote = "Session list unavailable: \(error.reason)"
            if session != nil { showSessionListNote() }
        }
    }

    /// The workspace's files for the `@` picker (SU.14); empty outside git.
    private(set) var workspaceFiles: [String] = [] {
        didSet { rebuildFileLinks() }
    }

    func reloadWorkspaceFiles() async {
        guard !isFixture else { return }
        guard let root = conversationRoot else {
            workspaceFiles = []
            return
        }
        let files = await WorkspaceFileLister.list(root: root)
        // A result for a workspace that has since changed is dropped.
        guard conversationRoot?.standardizedFileURL.path == root.standardizedFileURL.path else { return }
        workspaceFiles = files
    }

    private func showSessionListNote() {
        guard let note = sessionListNote, let root = conversationRoot?.path,
              notedSessionListRoots.insert(root).inserted else { return }
        model.apply(.notice(note))
    }

    /// Ends the current session and resumes `c` (SU.7a, D3), through the
    /// relaunch path. Ignored while starting or quitting, for a conversation
    /// that can't be resumed, and for the one already running.
    func resume(_ c: Conversation) async {
        guard !isFixture, canChoose, c.resumable, c.id != currentConversationID,
              let root = conversationRoot else { return }
        await relaunch(EngineRelaunch(
            kind: .resume, argv: EngineCommand.resumeArguments(id: c.id, source: root, allowBash: allowBash),
            reason: ""))
    }

    /// The Settings toggle (SU.18, D1): start the engine with `--allow-bash`.
    /// Read at each spawn, as the model choice is. On unless turned off
    /// (the owner's call, 2026-10-18).
    var allowBash: Bool {
        UserDefaults.standard.object(forKey: DefaultsKey.allowBash.rawValue) as? Bool ?? DefaultsKey.allowBashDefault
    }

    /// The running session was spawned with `--allow-bash` (SU.18, D3), its
    /// engine `relaunch` argv included. The engine reports no tool policy.
    private(set) var bashFallbackOn = false

    // MARK: recent projects (SU.7b)

    /// Every repository's sessions, for the Recent menus' labels; empty until
    /// loaded, and kept as it was when a load fails.
    private(set) var allSessions: [EngineSessionEntry] = []
    /// Raised by each load; a result from an older one is dropped.
    @ObservationIgnored private var recentProjectsGeneration = 0

    /// The Recent folders, each with its project's newest conversation.
    public var recentProjects: [RecentProject] {
        RecentProjects.items(
            recents: recentWorkspaces, entries: allSessions, current: workspace?.path,
            exists: { FileManager.default.fileExists(atPath: $0) }, rootOf: { ProjectRoot.locate(anchor: $0) },
            now: .now)
    }

    /// Loads every repository's sessions. A failure changes nothing and says
    /// nothing: the menus just show no labels.
    func reloadRecentProjects() async {
        guard !isFixture, let path = resolveExecutablePath() else { return }
        recentProjectsGeneration += 1
        let generation = recentProjectsGeneration
        let result = await SessionListLoader.loadAll(executable: path)
        guard generation == recentProjectsGeneration, case .success(let entries) = result else { return }
        allSessions = entries
    }

    /// Whether there's a Recent list to clear: cheap, unlike `recentProjects`,
    /// for the menu bar's commands, which rebuild often (final review).
    public var hasRecents: Bool { !recentWorkspaces.isEmpty }

    /// File › Open Recent › Clear Menu. The current workspace stays.
    public func clearRecents() {
        recentWorkspaces = []
        persist(nil, .recentWorkspaces)
    }

    /// Ends the current session and starts a fresh one with Settings.
    func newConversation() async {
        guard !isFixture else { return }
        await restart()
    }

    /// `start()` found no usable workspace: the view opens the folder picker
    /// (SU.6c, D1). Reset by a folder choice or `folderPickerDismissed()`.
    private(set) var wantsFolder = false
    /// Why the workspace isn't the saved one, or why there is none; shown at
    /// the next start.
    @ObservationIgnored private var workspaceNote: String?

    /// The Settings choices the toolbar menus own ("" / 0 = engine default).
    private(set) var modelID: String
    private(set) var contextSize: Int
    private(set) var recentWorkspaces: [String]
    /// The engine's model list; nil until loaded or when the engine has no
    /// `models --json` (the menus then use their fallbacks).
    private(set) var catalog: EngineModelList?
    @ObservationIgnored private var catalogNote: String?
    /// Engine paths whose "Model list unavailable" note was shown: once each.
    @ObservationIgnored private var notedPaths: Set<String> = []
    @ObservationIgnored private var catalogCacheKey: CatalogCacheKey?
    /// The model-list load for `catalogCacheKey`, kept so a caller that finds
    /// the key already set (a load in flight) can wait for its result.
    @ObservationIgnored private var catalogLoad: Task<Void, Never>?
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    /// The Settings executable string the observer last saw: other defaults
    /// writes (font size, inspector, the menus' own) change nothing here.
    @ObservationIgnored private var seenExecutableSetting: String?
    /// A `/model` sent and not yet relaunched or refused.
    @ObservationIgnored private var pendingModelCommand: String?
    /// Set only by `init(model:)`: fixture controllers neither load the catalog
    /// nor start an engine, so a preview never spawns `ds4-dogfood`.
    @ObservationIgnored private var isFixture = false

    @ObservationIgnored private var session: EngineSession?
    @ObservationIgnored private var quitGeneration = 0
    /// Set once app termination has begun: nothing may start an engine after.
    @ObservationIgnored private var isTerminating = false
    /// The safety bound fired for the current quit; later joiners return at once.
    @ObservationIgnored private var quitBoundFired = false

    /// Quit's escalation; `safetyBound` is only reached if even SIGKILL fails.
    @ObservationIgnored private let graces: EngineGraces
    @ObservationIgnored private var quitWaiters: [CheckedContinuation<Void, Never>] = []

    public init(graces: EngineGraces = .standard) {
        self.graces = graces
        let defaults = UserDefaults.standard
        modelID = defaults.string(forKey: DefaultsKey.modelID.rawValue) ?? ""
        contextSize = defaults.integer(forKey: DefaultsKey.contextSize.rawValue)
        recentWorkspaces = defaults.stringArray(forKey: DefaultsKey.recentWorkspaces.rawValue) ?? []
        lastSessionDirectory = defaults.string(forKey: DefaultsKey.lastSessionDirectory.rawValue)
            .map { URL(fileURLWithPath: $0) }
        let choice = WorkspaceChoice.resolve(
            saved: defaults.string(forKey: DefaultsKey.workspace.rawValue),
            recents: recentWorkspaces, checkout: Self.checkout(), isUsable: WorkspaceChoice.isUsable)
        workspace = choice.workspace
        // `@Observable` makes `workspace` computed, so its `didSet` runs here
        // too and saves a fallback.
        workspaceNote = choice.notice
        seenExecutableSetting = defaults.string(forKey: DefaultsKey.executable.rawValue)
        // Reload the model list when Settings names another engine.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let setting = UserDefaults.standard.string(forKey: DefaultsKey.executable.rawValue)
                guard setting != self.seenExecutableSetting else { return }
                self.seenExecutableSetting = setting
                guard let path = self.resolveExecutablePath(),
                      self.catalogCacheKey(forPath: path) != self.catalogCacheKey else { return }
                Task { await self.loadCatalog() }
            }
        }
    }

    isolated deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    /// Preview/test fixture construction: starts from a given model state,
    /// skipping `init()`'s `UserDefaults` reads and the live catalog-reload
    /// observer (previews don't restart a session).
    /// Swaps a fixture controller's state (the gallery's GPU flips, SU.13);
    /// a real controller ignores it.
    func replaceFixtureModel(_ model: EngineSessionModel) {
        guard isFixture else { return }
        self.model = model
    }

    init(model: EngineSessionModel, conversations: [Conversation] = [], workspace: URL? = nil,
         workspaceFiles: [String] = [], catalog: EngineModelList? = nil, source: URL? = nil,
         bashFallbackOn: Bool = false) {
        self.bashFallbackOn = bashFallbackOn
        self.graces = .standard
        // First: `workspace`'s `didSet` runs in this init and must not persist.
        isFixture = true
        self.model = model
        // A fixture's catalog, given rather than loaded (EN.2: the menus' titles).
        self.catalog = catalog
        self.conversations = conversations
        self.workspaceFiles = workspaceFiles
        self.workspace = workspace
        // A fixture's checkout, so its file links resolve (SU.16).
        self.source = source
        modelID = ""
        contextSize = 0
        recentWorkspaces = []
        rebuildFileLinks()  // `didSet`s don't run in an initializer
    }

    /// Every write to the app's defaults. A fixture controller (a preview's,
    /// the gallery's, a test's) persists nothing (SU.17).
    private func persist(_ value: Any?, _ key: DefaultsKey) {
        guard !isFixture else { return }
        if let value { UserDefaults.standard.set(value, forKey: key.rawValue) }
        else { UserDefaults.standard.removeObject(forKey: key.rawValue) }
    }

    /// The checkout the app runs from, if any: anchored to the executable,
    /// never the launch directory's guess.
    private static func checkout() -> URL? {
        let anchor = Bundle.main.executableURL?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return ProjectRoot.locate(anchor: anchor, maxDepth: ProjectRoot.executableWalkDepth)
    }

    /// The folder picker closed without a choice.
    func folderPickerDismissed() { wantsFolder = false }

    /// Choosing a value that differs from the current one writes Settings and,
    /// while a session runs, restarts it; the menu choice is the confirmation.
    /// Ignored while a session starts or quits, and when nothing changes.
    var canChoose: Bool {
        !isTerminating && model.phase != .starting && model.phase != .quitting
    }

    /// Every project switch but the no-folder picker's comes here (SU.7b,
    /// D3): mid-turn it waits for `confirmSwitch()`; otherwise it switches.
    /// Ignored while a session starts or quits.
    public func requestSwitch(to folder: URL, resuming conversation: Conversation? = nil) {
        guard canChoose else { return }
        // The current folder isn't a switch: don't ask to end the turn for it.
        if conversation == nil, folder.standardizedFileURL.path == workspace?.standardizedFileURL.path {
            remember(folder)
            return
        }
        let request = ProjectSwitch(folder: folder, resuming: conversation)
        if transcript.isBusy {
            pendingSwitch = request
        } else {
            perform(request)
        }
    }

    /// A switch asked for mid-turn, waiting for the alert's answer.
    public private(set) var pendingSwitch: ProjectSwitch?

    public func confirmSwitch() {
        guard let request = pendingSwitch else { return }
        confirmSwitch(request)
    }

    /// The alert's "Switch", with the request it presented: it holds even if
    /// the alert's binding cleared `pendingSwitch` first (final review).
    public func confirmSwitch(_ request: ProjectSwitch) {
        pendingSwitch = nil
        perform(request)
    }

    public func cancelSwitch() { pendingSwitch = nil }

    /// A plain switch is `select(workspace:)`. One that resumes sets the
    /// workspace without restarting, so the resume is the only spawn.
    private func perform(_ request: ProjectSwitch) {
        guard canChoose else { return }
        // A switch made another way supersedes one still waiting to be confirmed.
        pendingSwitch = nil
        guard let conversation = request.resuming else {
            select(workspace: request.folder)
            return
        }
        remember(request.folder)
        wantsFolder = false
        workspaceNote = nil
        workspace = request.folder
        conversations = []
        Task {
            await resume(conversation)
            await reloadConversations()
            await reloadRecentProjects()
        }
    }

    /// Puts `url` first in the Recent list, and saves it.
    private func remember(_ url: URL) {
        let list = RecentWorkspaces.updated(recentWorkspaces, adding: url.path)
        recentWorkspaces = list
        persist(list, .recentWorkspaces)
    }

    func select(workspace url: URL) {
        guard canChoose else { return }
        remember(url)
        wantsFolder = false
        workspaceNote = nil
        guard url.standardizedFileURL.path != workspace?.standardizedFileURL.path else { return }
        workspace = url
        conversations = []
        Task { await reloadConversations() }
        Task { await reloadRecentProjects() }
        restartIfRunning()
    }

    /// While a session runs, a model pick goes through the engine's `/model`,
    /// which relaunches with the same files and a new conversation; the
    /// relaunch saves the choice (EN.1, D3). Otherwise the pick is saved for
    /// the next start. "Engine default" ("") has no `/model` form, so it
    /// restarts fresh as before.
    func select(modelID id: String) {
        guard canChoose else { return }
        let id = id.trimmedOrNil ?? ""
        guard id != modelID else { return }
        if !id.isEmpty, ModelMenu.selectionAction(phase: model.phase) == .sendModelCommand {
            guard pendingModelCommand == nil else {
                model.apply(.notice("A model switch is already pending."))
                return
            }
            pendingModelCommand = id
            send("/model \(id)")
            return
        }
        modelID = id
        persist(id, .modelID)
        restartIfRunning()
    }

    func select(contextSize size: Int) {
        guard canChoose else { return }
        let size = max(0, size)
        guard size != contextSize else { return }
        contextSize = size
        persist(size, .contextSize)
        restartIfRunning()
    }

    private func restartIfRunning() {
        guard model.phase == .running else { return }
        Task { await restart() }
    }

    /// The engine executable: the Settings path, then `PATH`, then
    /// `~/.local/bin` (`EngineCommand.resolveExecutable`).
    private func resolveExecutable() -> EngineResolution {
        EngineCommand.resolveExecutable(
            settingsPath: UserDefaults.standard.string(forKey: DefaultsKey.executable.rawValue),
            pathEnv: ProcessInfo.processInfo.environment["PATH"],
            home: FileManager.default.homeDirectoryForCurrentUser,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    private func resolveExecutablePath() -> String? {
        if case .found(let path) = resolveExecutable() { return path }
        return nil
    }

    /// `path`'s current cache key: its modification date travels with the
    /// path, so an engine upgraded in place (same path, new binary) compares
    /// unequal to a prior load and is refetched rather than served stale.
    private func catalogCacheKey(forPath path: String) -> CatalogCacheKey {
        let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        return CatalogCacheKey(path: path, modifiedAt: modifiedAt)
    }

    /// Loads the list once per engine path and modification date (a failed
    /// load is not retried until the path or the binary itself changes).
    func loadCatalogIfNeeded() async {
        guard !isFixture else { return }
        guard let path = resolveExecutablePath() else { return }
        guard catalogCacheKey(forPath: path) != catalogCacheKey else {
            // Loaded, or loading (the defaults observer can start a load at
            // launch, before the session's start asks): wait for it.
            await catalogLoad?.value
            return
        }
        await loadCatalog()
    }

    /// Reads the engine's model list; never blocks a session start. On failure
    /// the menus fall back and one transcript note says why.
    func loadCatalog() async {
        guard let path = resolveExecutablePath() else { return }
        let key = catalogCacheKey(forPath: path)
        catalogCacheKey = key
        let load = Task { await self.fetchCatalog(path: path, key: key) }
        catalogLoad = load
        await load.value
    }

    private func fetchCatalog(path: String, key: CatalogCacheKey) async {
        let result = await EngineModelCatalogLoader.load(executable: path)
        guard key == catalogCacheKey else { return }
        switch result {
        case .success(let list):
            catalog = list
            catalogNote = nil
        case .failure(let error):
            catalog = nil
            catalogNote = "Model list unavailable: \(error.reason)"
            // Only into a live session's transcript: a load during a start's
            // "Starting…" is shown by that start, after its transcript resets.
            if session != nil { showCatalogNote() }
        }
    }

    private func showCatalogNote() {
        guard let note = catalogNote, let path = catalogCacheKey?.path,
              notedPaths.insert(path).inserted else { return }
        model.apply(.notice(note))
    }

    /// Quits the running session, then starts a new one with current Settings.
    func restart() async {
        guard model.phase != .quitting, !isTerminating else { return }
        await quit()
        guard !isTerminating else { return }
        // After the safety bound the old engine may still hold the GPU: a
        // menu pick must not start a second one (a deliberate Start may).
        guard !quitBoundFired, !isActive else {
            model.apply(.notice("Restart skipped: the engine has not exited yet. Try again in a moment."))
            return
        }
        await start()
    }

    /// Called when the app is terminating; quit waiters are still released.
    public func beginTerminating() { isTerminating = true }

    /// Starts a session. Without `relaunch` it first loads the model list and
    /// clears a saved model the engine no longer offers (EN.1, D1); with one
    /// the engine's argv is used exactly as given, and the rows stay until
    /// the relaunched process reports what it kept.
    func start(relaunch: EngineRelaunch? = nil) async {
        let override = relaunch?.argv
        guard !isFixture, !isActive, !isTerminating else { return }
        guard let folder = workspace else {
            // No usable folder (SU.6c, D1): say why and ask; spawn nothing.
            model.apply(.notice(workspaceNote ?? "Choose a folder in a git repository to start."))
            wantsFolder = true
            return
        }
        var notice: String?
        if override == nil {
            // "Starting…" while the model list loads; a second Start sees an
            // active phase and returns.
            model.willStart()
            await loadCatalogIfNeeded()
            guard !isTerminating, model.phase == .starting, session == nil else { return }
            let checked = ModelMenu.validated(saved: modelID, list: catalog)
            if checked.modelID != modelID {
                modelID = checked.modelID
                persist(modelID, .modelID)
            }
            notice = checked.notice
        }
        let executable: String
        switch resolveExecutable() {
        case .found(let path):
            executable = path
        case .notFound(let searched):
            model.didNotFind(searched: searched)
            return
        }

        let source = ProjectRoot.locate(anchor: folder) ?? folder
        self.source = source

        let arguments = override ?? EngineCommand.arguments(
            source: source, modelID: modelID, contextSize: contextSize, allowBash: allowBash)
        bashFallbackOn = EngineCommand.allowsBash(arguments)
        let session = EngineSession(
            executable: executable,
            arguments: arguments,
            workingDirectory: source,
            stopGrace: graces.stop, termGrace: graces.term, killGrace: graces.kill)
        // A session the safety bound gave up on may still exit or speak
        // later; only the current session's events and exit count.
        session.onEvent = { [weak self, weak session] event in
            guard let self, let session, self.session === session else { return }
            self.handle(event)
        }
        session.onExit = { [weak self, weak session] exit, directory in
            guard let self, let session, self.session === session else { return }
            self.handleExit(exit, directory)
        }
        if let relaunch { model.didRelaunch(relaunch) } else { model.didStart() }
        worktree = nil  // a new process: its receipt names its own
        // Per-session state: a bound or a pending /model from an earlier
        // session must not carry into this one.
        quitBoundFired = false
        pendingModelCommand = nil
        if let note = workspaceNote { model.apply(.notice(note)); workspaceNote = nil }
        if let notice { model.apply(.notice(notice)) }
        showCatalogNote()
        showSessionListNote()
        do {
            try session.start()
            self.session = session
        } catch {
            model.didExit(EngineExit.launchFailure(
                path: executable, reason: error.localizedDescription), directory: nil)
        }
    }

    private func handle(_ event: EngineEvent) {
        model.apply(event)
        // The engine refreshes its receipt at every pause (SU.16, D3).
        if case .pause = event, let directory = model.sessionDirectory {
            worktree = ReceiptReader.worktree(sessionDirectory: directory)
        }
        // SU.11, D4: a new conversation's id is in, but the list is behind:
        // reload once for it, so its row appears and is selected.
        if let id = model.currentSessionID, id != listReloadedFor,
           Conversations.isUnlisted(sessionID: id, in: conversations) {
            listReloadedFor = id
            Task { await reloadConversations() }
        }
        switch event {
        case .relaunch(let r): Task { await relaunch(r) }
        case .refused: pendingModelCommand = nil
        default: break
        }
        // The fork is at its first `input`: ask about the report, once.
        if let prompt = model.takeAnalysisPrompt() {
            send(prompt.text, shown: prompt.shown)
        }
    }

    /// Analyze (AN.2): make the report from this session's directory, then
    /// resume the session as a fork to talk about it there.
    func analyze() async {
        guard let target = model.analysisTarget, let source else { return }
        guard let executable = resolveExecutablePath() else {
            model.apply(.error("Analyze: \(EngineCommand.executableName) not found"))
            return
        }
        let result = await reportLoader(executable, target.directory)
        // A report for a session that has moved on is dropped (SU.17, finding 1).
        guard model.analysisTarget == target else { return }
        switch result {
        case .failure(let failure):
            model.apply(.error("Analyze: \(failure.message)"))
        case .success(let report):
            // The fork keeps the running session's shell policy (SU.18).
            guard let fork = model.beginAnalysis(report: report, source: source, allowBash: bashFallbackOn)
            else { return }
            await relaunch(fork)
        }
    }

    /// Done (AN.2): resume the main session; the engine sends the relaunch.
    func doneAnalyzing() {
        guard let command = model.analysisDoneCommand else { return }
        model.markAnalysisReturning()
        send(command)
    }

    /// The engine's TUI.34 contract: end this session, then start the
    /// executable with `relaunch` exactly as given (no `--commit`, nothing
    /// added). A `/model` relaunch saves its model, so the toolbar agrees.
    func relaunch(_ r: EngineRelaunch) async {
        guard !isTerminating else { return }
        await quit()
        pendingModelCommand = nil
        guard !isTerminating else { return }
        guard !quitBoundFired, !isActive else {
            model.apply(.notice("Relaunch skipped: the engine did not exit."))
            model.abandonAnalysisTransition()
            return
        }
        if r.kind == .model, let id = r.modelID {
            modelID = id
            persist(id, .modelID)
        }
        await start(relaunch: r)
    }

    func send(_ text: String, shown: String? = nil) {
        guard let session, model.send(text, shown: shown) else { return }
        do {
            try session.send(prompt: text)
        } catch {
            model.apply(.error("Could not send: \(error.localizedDescription)"))
        }
    }

    func stop() {
        guard model.composer.canStop, let session else { return }
        do {
            try session.stop()
        } catch {
            model.apply(.error("Could not stop: \(error.localizedDescription)"))
        }
    }

    /// Asks the engine to quit and returns once it has exited. A quit already
    /// in flight is joined, not restarted. Returns after a safety bound even
    /// if the engine has not exited, so app quit can never hang.
    public func quit() async {
        guard let session, session.isRunning else { return }
        if model.phase != .quitting {
            model.willQuit()
            session.quit()
            quitGeneration += 1
            quitBoundFired = false
            let generation = quitGeneration
            Task { [weak self, graces] in
                try? await Task.sleep(for: graces.safetyBound)
                // The bound releases only the quit it was started for.
                guard let self, self.quitGeneration == generation else { return }
                self.quitBoundFired = true
                // End the session here: its exit may never come, and the
                // phase must not stay "quitting" with Start disabled.
                if self.session != nil {
                    self.session = nil
                    self.model.didExit(EngineExit(
                        code: -1, message: "the engine did not exit after quit; it may still be running"),
                        directory: nil)
                }
                self.resumeQuitWaiters()
            }
        }
        await withCheckedContinuation { quitWaiters.append($0) }
    }

    private func resumeQuitWaiters() {
        let waiters = quitWaiters
        quitWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    private func handleExit(_ exit: EngineExit, _ directory: URL?) {
        session = nil
        worktree = nil  // the engine removes it as it ends (SU.16, D3)
        pendingModelCommand = nil
        if let directory {
            lastSessionDirectory = directory
            persist(directory.path, .lastSessionDirectory)
        }
        // A resume the engine refused to start (its `.resumed` never came):
        // a model it no longer offers can still give back the files.
        let refusedResume = model.pendingRelaunch.flatMap { r -> String? in
            guard r.kind == .resume, let i = r.argv.firstIndex(of: "--resume"), i + 1 < r.argv.count else { return nil }
            return r.argv[i + 1]
        }
        model.didExit(exit, directory: directory)
        if let id = refusedResume, exit.message.contains("model") {
            model.apply(.notice(
                "Its files can still be recovered by starting a new conversation from it in Terminal: "
                + "`ds4-dogfood tui --resume \(id) --new-conversation`"))
        }
        Task { await reloadConversations() }
        Task { await reloadRecentProjects() }
        quitGeneration += 1
        resumeQuitWaiters()
    }
}
