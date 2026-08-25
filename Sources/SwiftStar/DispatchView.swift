import SwiftUI
import SwiftStarKit

/// P10 Dispatch tab (D2/D3/D4): a minimal surface that accepts a handoff
/// packet (task text + the exact writable files, one per line + an optional
/// validation command) and submits it to `AgentController.dispatchAttempt`,
/// then shows the `DispatchOutcome` — a candidate ref (a real commit the
/// parent reviews) or a typed `Receipt` naming why not. The caller's tree is
/// never touched; nothing merges.
struct DispatchView: View {
    @Bindable var controller: AgentController
    @State private var taskText = ""
    @State private var writableFilesText = ""
    @State private var validationCommand = ""

    var body: some View {
        VStack(spacing: 0) {
            packetForm
            Divider()
            outcomeView
        }
        .navigationTitle("Dispatch")
        .frame(minWidth: 520, minHeight: 420)
    }

    /// The writable files as a list of non-empty, trimmed, one-per-line paths
    /// (relative to the worktree root, matching `HandoffPacket.writableFiles`).
    private var writableFiles: [String] {
        writableFilesText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The packet built from the form, or nil when the task or writable files
    /// are empty (the Dispatch button is disabled until both are set).
    private var packet: HandoffPacket? {
        let task = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty, !writableFiles.isEmpty else { return nil }
        return HandoffPacket(
            taskText: task,
            writableFiles: writableFiles,
            validationCommand: validationCommand.isEmpty ? nil : validationCommand,
            baselines: [:],
            turnBudget: 100_000,
            toolCallBudget: 64)
    }

    private var packetForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Task").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $taskText)
                .frame(minHeight: 72)
                .font(.system(.body, design: .monospaced))

            Text("Writable files (one per line, worktree-relative)")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $writableFilesText)
                .frame(minHeight: 72)
                .font(.system(.body, design: .monospaced))

            Text("Validation command (optional, runs parent-side)")
                .font(.caption).foregroundStyle(.secondary)
            TextField("e.g. swift test", text: $validationCommand)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Dispatch", action: dispatch)
                    .disabled(controller.isDispatching || packet == nil)
                if controller.isDispatching {
                    ProgressView().scaleEffect(0.7)
                    Button("Cancel") { controller.cancelDispatch() }
                }
                Spacer()
                Text("Shell off · host-tools · revision-checked")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var outcomeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let error = controller.dispatchError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).textSelection(.enabled)
                } else if let outcome = controller.dispatchOutcome {
                    outcomeRow(outcome)
                } else {
                    Text(controller.isDispatching ? "Dispatching…" :
                            "Enter a packet and Dispatch.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func outcomeRow(_ outcome: DispatchOutcome) -> some View {
        switch outcome {
        case .candidate(let ref, let carried, let baselines):
            VStack(alignment: .leading, spacing: 4) {
                Label("Candidate ref", systemImage: "checkmark.seal")
                    .font(.headline).foregroundStyle(.green)
                Text(ref)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Text("\(carried.mutations.count) mutation(s) · "
                     + "\(carried.toolCalls.count) tool call(s) · "
                     + "\(baselines.count) baseline(s) · "
                     + "stop=\(carried.stopReason.rawValue)")
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        case .receipt(let receipt):
            VStack(alignment: .leading, spacing: 4) {
                Label("Receipt", systemImage: "doc.text")
                    .font(.headline).foregroundStyle(.orange)
                receiptRow(receipt)
            }
        }
    }

    @ViewBuilder
    private func receiptRow(_ receipt: Receipt) -> some View {
        switch receipt {
        case .refusedTool(let path):
            Text("Refused tool — mutation outside the contract: \(path)")
                .foregroundStyle(.orange).textSelection(.enabled)
        case .budgetExceeded:
            Text("Budget exceeded (turn or tool-call cap).")
                .foregroundStyle(.orange).textSelection(.enabled)
        case .validationFailed(let exit, let digest):
            VStack(alignment: .leading, spacing: 2) {
                Text("Validation failed (exit \(exit)).")
                    .foregroundStyle(.orange).textSelection(.enabled)
                Text(digest)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        case .noChanges:
            Text("No changes — the turn mutated nothing to commit.")
                .foregroundStyle(.secondary).textSelection(.enabled)
        case .repairExhausted:
            Text("Repair exhausted — no candidate reached a passing grade.")
                .foregroundStyle(.orange).textSelection(.enabled)
        }
    }

    private func dispatch() {
        guard let packet else { return }
        controller.dispatchAttempt(packet: packet)
    }
}
