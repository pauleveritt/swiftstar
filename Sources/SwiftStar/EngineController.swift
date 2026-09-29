import Foundation
import Observation
import SwiftStarAppKit
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
        workspace = Self.defaultWorkspace()
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

    /// True while a session runs and the given Settings values name a
    /// different model or context size than the one loaded. The view passes
    /// its `@AppStorage` values so SwiftUI tracks Settings edits.
    func restartNeeded(modelID: String?, contextSize: Int?) -> Bool {
        model.phase == .running && EngineCommand.restartNeeded(
            session: model.transcript.session, modelID: modelID, contextSize: contextSize)
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
                modelID: UserDefaults.standard.string(forKey: Self.modelIDDefaultsKey),
                contextSize: UserDefaults.standard.integer(forKey: Self.contextSizeDefaultsKey)),
            workingDirectory: source,
            stopGrace: Self.stopGrace, termGrace: Self.termGrace, killGrace: Self.killGrace)
        session.onEvent = { [weak self] event in self?.model.apply(event) }
        session.onExit = { [weak self] exit, directory in self?.handleExit(exit, directory) }
        model.didStart()
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
