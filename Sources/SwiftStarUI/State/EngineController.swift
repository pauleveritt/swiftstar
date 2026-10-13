import Foundation
import Observation
import SwiftStarEngine
import SwiftStarKit

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
    var sessionDirectory: URL? { model.sessionDirectory }
    public var isActive: Bool { model.phase.isActive }
    /// The git root the current or last session worked from (its `--source`),
    /// kept after the session ends so its tool cards still resolve.
    private(set) var source: URL?
    var workspace: URL? {
        didSet {
            guard let workspace else { return }
            UserDefaults.standard.set(workspace.path, forKey: DefaultsKey.workspace.rawValue)
        }
    }

    /// The Settings choices the toolbar menus own ("" / 0 = engine default).
    private(set) var modelID: String
    private(set) var contextSize: Int
    private(set) var recentWorkspaces: [String]
    /// The engine's model list; nil until loaded or when the engine has no
    /// `models --json` (the menus then use their fallbacks).
    private(set) var catalog: EngineModelList?
    @ObservationIgnored private var catalogNote: String?
    @ObservationIgnored private var noteGate = CatalogNoteGate()
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
        workspace = Self.defaultWorkspace()
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
    init(model: EngineSessionModel) {
        self.graces = .standard
        self.model = model
        workspace = nil
        modelID = ""
        contextSize = 0
        recentWorkspaces = []
        isFixture = true
    }

    /// The last chosen folder, else the checkout the app runs from, else home.
    private static func defaultWorkspace() -> URL {
        if let dir = UserDefaults.standard.string(forKey: DefaultsKey.workspace.rawValue), !dir.isEmpty {
            return URL(fileURLWithPath: dir)
        }
        let anchor = Bundle.main.executableURL?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return ProjectRoot.locate(anchor: anchor) ?? FileManager.default.homeDirectoryForCurrentUser
    }

    /// Choosing a value that differs from the current one writes Settings and,
    /// while a session runs, restarts it; the menu choice is the confirmation.
    /// Ignored while a session starts or quits, and when nothing changes.
    var canChoose: Bool {
        !isTerminating && model.phase != .starting && model.phase != .quitting
    }

    func select(workspace url: URL) {
        guard canChoose else { return }
        let list = RecentWorkspaces.updated(recentWorkspaces, adding: url.path)
        recentWorkspaces = list
        UserDefaults.standard.set(list, forKey: DefaultsKey.recentWorkspaces.rawValue)
        guard url.standardizedFileURL.path != workspace?.standardizedFileURL.path else { return }
        workspace = url
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
        UserDefaults.standard.set(id, forKey: DefaultsKey.modelID.rawValue)
        restartIfRunning()
    }

    func select(contextSize size: Int) {
        guard canChoose else { return }
        let size = max(0, size)
        guard size != contextSize else { return }
        contextSize = size
        UserDefaults.standard.set(size, forKey: DefaultsKey.contextSize.rawValue)
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
              noteGate.claim(path: path) else { return }
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
                UserDefaults.standard.set(modelID, forKey: DefaultsKey.modelID.rawValue)
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

        let folder = workspace ?? FileManager.default.homeDirectoryForCurrentUser
        let source = ProjectRoot.locate(anchor: folder) ?? folder
        self.source = source

        let session = EngineSession(
            executable: executable,
            arguments: override ?? EngineCommand.arguments(
                source: source,
                modelID: modelID, contextSize: contextSize),
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
        // Per-session state: a bound or a pending /model from an earlier
        // session must not carry into this one.
        quitBoundFired = false
        pendingModelCommand = nil
        if let notice { model.apply(.notice(notice)) }
        showCatalogNote()
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
        switch event {
        case .relaunch(let r): Task { await relaunch(r) }
        case .refused: pendingModelCommand = nil
        default: break
        }
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
            return
        }
        if r.kind == .model, let id = r.modelID {
            modelID = id
            UserDefaults.standard.set(id, forKey: DefaultsKey.modelID.rawValue)
        }
        await start(relaunch: r)
    }

    func send(_ text: String) {
        guard let session, model.send(text) else { return }
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
        if quitBoundFired { return }
        await withCheckedContinuation { quitWaiters.append($0) }
    }

    private func resumeQuitWaiters() {
        let waiters = quitWaiters
        quitWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    private func handleExit(_ exit: EngineExit, _ directory: URL?) {
        session = nil
        pendingModelCommand = nil
        model.didExit(exit, directory: directory)
        quitGeneration += 1
        resumeQuitWaiters()
    }
}
