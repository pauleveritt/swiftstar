import Foundation
import Observation
import SwiftStarAppKit
import SwiftStarKit

/// Thin app-side owner of one `EngineSession`: it resolves the executable,
/// picks the source repository, and feeds engine events to the transcript and
/// metrics folds. The logic lives in the tested Kit types.
@Observable
final class EngineController {
    enum Phase: Equatable {
        case idle
        case starting
        case running
        case ended(EngineExit)
        case notFound([String])
    }

    static let workspaceDefaultsKey = "agentWorkspace"
    static let executableDefaultsKey = "engineExecutable"

    private(set) var transcript = EngineTranscript()
    private(set) var metrics = EngineMetricsState()
    private(set) var phase: Phase = .idle
    private(set) var sessionDirectory: URL?
    var workspace: URL? {
        didSet {
            guard let workspace else { return }
            UserDefaults.standard.set(workspace.path, forKey: Self.workspaceDefaultsKey)
        }
    }

    @ObservationIgnored private var session: EngineSession?
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

    var isActive: Bool { phase == .starting || phase == .running }

    func start() {
        guard !isActive else { return }
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
            phase = .notFound(searched)
            return
        }

        let folder = workspace ?? FileManager.default.homeDirectoryForCurrentUser
        let source = ProjectRoot.locate(anchor: folder) ?? folder
        transcript = EngineTranscript()
        metrics = EngineMetricsState()
        sessionDirectory = nil

        let session = EngineSession(
            executable: executable,
            arguments: EngineCommand.arguments(source: source),
            workingDirectory: source)
        session.onEvent = { [weak self] event in self?.handle(event) }
        session.onExit = { [weak self] exit, directory in self?.handleExit(exit, directory) }
        do {
            try session.start()
            self.session = session
            phase = .starting
        } catch {
            // `describe` with no ready line reads as a start refusal.
            let exit = EngineExit.describe(
                code: -1, stderrTail: "could not launch \(executable): \(error.localizedDescription)",
                sawReady: false)
            transcript.appendSystem(exit.message)
            phase = .ended(exit)
        }
    }

    func send(_ text: String) {
        guard phase == .running, let session else { return }
        transcript.appendUser(text)
        do {
            try session.send(prompt: text)
        } catch {
            transcript.appendSystem("Could not send: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard transcript.canStop, let session else { return }
        try? session.stop()
    }

    /// Asks the engine to quit and returns once it has exited.
    func quit() async {
        guard let session, session.isRunning else { return }
        session.quit()
        await withCheckedContinuation { quitWaiters.append($0) }
    }

    private func handle(_ event: EngineEvent) {
        if case .ready = event { phase = .running }
        if case .protocolError(let message) = event {
            transcript.appendSystem("Protocol error: \(message)")
        }
        transcript.apply(event)
        EngineMetricsReducer.reduce(&metrics, event)
    }

    private func handleExit(_ exit: EngineExit, _ directory: URL?) {
        session = nil
        sessionDirectory = directory
        transcript.appendSystem(exit.message)
        if let directory {
            transcript.appendSystem(
                "Session: \(directory.path)\nTo take its changes: \(EngineCommand.applyCommand(sessionDirectory: directory))")
        }
        phase = .ended(exit)
        let waiters = quitWaiters
        quitWaiters = []
        for waiter in waiters { waiter.resume() }
    }
}
