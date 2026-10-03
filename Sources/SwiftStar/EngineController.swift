import Foundation
import Observation
import SwiftStarEngine
import SwiftStarKit

/// Thin app-side owner of one `EngineSession`: it resolves the executable,
/// picks the source repository, and feeds engine events to the transcript and
/// metrics folds. The logic lives in the tested Kit types.
@Observable
final class EngineController {
    static let workspaceDefaultsKey = "agentWorkspace"
    static let executableDefaultsKey = "engineExecutable"
    static let modelIDDefaultsKey = "engineModelID"
    static let contextSizeDefaultsKey = "engineContextSize"
    static let recentWorkspacesDefaultsKey = "recentWorkspaces"

    /// Every session rule (phase, busy/stop/pending, labels) lives in the
    /// model; the controller forwards to it and owns the process.
    private(set) var model = EngineSessionModel()
    var transcript: EngineTranscript { model.transcript }
    var metrics: EngineMetricsState { model.metrics }
    var phase: EngineSessionPhase { model.phase }
    var composer: EngineComposer { model.composer }
    var sessionDirectory: URL? { model.sessionDirectory }
    var isActive: Bool { model.phase.isActive }
    var workspace: URL? {
        didSet {
            guard let workspace else { return }
            UserDefaults.standard.set(workspace.path, forKey: Self.workspaceDefaultsKey)
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
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?

    @ObservationIgnored private var session: EngineSession?
    @ObservationIgnored private var quitGeneration = 0
    /// Set once app termination has begun: nothing may start an engine after.
    @ObservationIgnored private var isTerminating = false
    /// The safety bound fired for the current quit; later joiners return at once.
    @ObservationIgnored private var quitBoundFired = false

    private static let stopGrace: Duration = .seconds(10)
    private static let termGrace: Duration = .seconds(5)
    private static let killGrace: Duration = .seconds(10)
    /// Only reached if even SIGKILL fails to end the engine.
    private static let quitSafetyBound: Duration = stopGrace + termGrace + killGrace + .seconds(5)
    @ObservationIgnored private var quitWaiters: [CheckedContinuation<Void, Never>] = []

    init() {
        let defaults = UserDefaults.standard
        modelID = defaults.string(forKey: Self.modelIDDefaultsKey) ?? ""
        contextSize = defaults.integer(forKey: Self.contextSizeDefaultsKey)
        recentWorkspaces = defaults.stringArray(forKey: Self.recentWorkspacesDefaultsKey) ?? []
        workspace = Self.defaultWorkspace()
        // Reload the model list when Settings changes the engine path.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let path = self.resolveExecutablePath() else { return }
                guard self.catalogCacheKey(forPath: path) != self.catalogCacheKey else { return }
                Task { await self.loadCatalog() }
            }
        }
    }

    /// The last chosen folder, else the checkout the app runs from, else home.
    private static func defaultWorkspace() -> URL {
        if let dir = UserDefaults.standard.string(forKey: workspaceDefaultsKey), !dir.isEmpty {
            return URL(fileURLWithPath: dir)
        }
        let anchor = Bundle.main.executableURL?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return ProjectRoot.locate(anchor: anchor) ?? FileManager.default.homeDirectoryForCurrentUser
    }

    /// Choosing a value that differs from the current one writes Settings and,
    /// while a session runs, restarts it; the menu choice is the confirmation.
    /// Ignored while a session starts or quits, and when nothing changes.
    private var canChoose: Bool {
        !isTerminating && model.phase != .starting && model.phase != .quitting
    }

    func select(workspace url: URL) {
        guard canChoose else { return }
        let list = RecentWorkspaces.updated(recentWorkspaces, adding: url.path)
        recentWorkspaces = list
        UserDefaults.standard.set(list, forKey: Self.recentWorkspacesDefaultsKey)
        guard url.standardizedFileURL.path != workspace?.standardizedFileURL.path else { return }
        workspace = url
        restartIfRunning()
    }

    func select(modelID id: String) {
        guard canChoose else { return }
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id != modelID else { return }
        modelID = id
        UserDefaults.standard.set(id, forKey: Self.modelIDDefaultsKey)
        restartIfRunning()
    }

    func select(contextSize size: Int) {
        guard canChoose else { return }
        let size = max(0, size)
        guard size != contextSize else { return }
        contextSize = size
        UserDefaults.standard.set(size, forKey: Self.contextSizeDefaultsKey)
        restartIfRunning()
    }

    private func restartIfRunning() {
        guard model.phase == .running else { return }
        Task { await restart() }
    }

    private func resolveExecutablePath() -> String? {
        let settingsPath = UserDefaults.standard.string(forKey: Self.executableDefaultsKey)
        if case .found(let path) = EngineCommand.resolveExecutable(
            settingsPath: settingsPath,
            pathEnv: ProcessInfo.processInfo.environment["PATH"],
            home: FileManager.default.homeDirectoryForCurrentUser,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }
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
        guard let path = resolveExecutablePath() else { return }
        guard catalogCacheKey(forPath: path) != catalogCacheKey else { return }
        await loadCatalog()
    }

    /// Reads the engine's model list; never blocks a session start. On failure
    /// the menus fall back and one transcript note says why.
    func loadCatalog() async {
        guard let path = resolveExecutablePath() else { return }
        let key = catalogCacheKey(forPath: path)
        catalogCacheKey = key
        let result = await EngineModelCatalogLoader.load(executable: path)
        guard key == catalogCacheKey else { return }
        switch result {
        case .success(let list):
            catalog = list
            catalogNote = nil
        case .failure(let error):
            catalog = nil
            catalogNote = "Model list unavailable: \(error.reason)"
            if isActive { showCatalogNote() }
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
        guard !isActive else {
            model.apply(.notice("Restart skipped: the engine has not exited yet. Try again in a moment."))
            return
        }
        start()
    }

    /// Called when the app is terminating; quit waiters are still released.
    func beginTerminating() { isTerminating = true }

    func start() {
        guard !isActive, !isTerminating else { return }
        let settingsPath = UserDefaults.standard.string(forKey: Self.executableDefaultsKey)
        let resolution = EngineCommand.resolveExecutable(
            settingsPath: settingsPath,
            pathEnv: ProcessInfo.processInfo.environment["PATH"],
            home: FileManager.default.homeDirectoryForCurrentUser,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) })
        let executable: String
        switch resolution {
        case .found(let path):
            executable = path
        case .notFound(let searched):
            model.didNotFind(searched: searched)
            return
        }

        let folder = workspace ?? FileManager.default.homeDirectoryForCurrentUser
        let source = ProjectRoot.locate(anchor: folder) ?? folder

        let session = EngineSession(
            executable: executable,
            arguments: EngineCommand.arguments(
                source: source,
                modelID: modelID, contextSize: contextSize),
            workingDirectory: source,
            stopGrace: Self.stopGrace, termGrace: Self.termGrace, killGrace: Self.killGrace)
        session.onEvent = { [weak self] event in self?.model.apply(event) }
        session.onExit = { [weak self] exit, directory in self?.handleExit(exit, directory) }
        model.didStart()
        showCatalogNote()
        do {
            try session.start()
            self.session = session
        } catch {
            model.didFailToLaunch(EngineExit.launchFailure(
                path: executable, reason: error.localizedDescription))
        }
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
    func quit() async {
        guard let session, session.isRunning else { return }
        if model.phase != .quitting {
            model.willQuit()
            session.quit()
            quitGeneration += 1
            quitBoundFired = false
            let generation = quitGeneration
            Task { [weak self] in
                try? await Task.sleep(for: Self.quitSafetyBound)
                // The bound releases only the quit it was started for.
                guard let self, self.quitGeneration == generation else { return }
                self.quitBoundFired = true
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
        model.didExit(exit, directory: directory)
        quitGeneration += 1
        resumeQuitWaiters()
    }
}
