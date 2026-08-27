import SwiftUI
import SwiftStarKit

struct DiagnosticsView: View {
    let model: DiagnosticsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.provenance == .recorded {
                Text("Results computed from a recorded capture — not a live engine.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.awaitingCapture {
                // Distinct from "analyzed, found nothing": the session is up but
                // has not written an analyzable turn yet. Without this the empty
                // list reads as a clean bill of health.
                ContentUnavailableView(
                    "Waiting for the first turn",
                    systemImage: "hourglass",
                    description: Text("This session's capture has nothing to analyze yet."))
            } else if model.findings.isEmpty {
                ContentUnavailableView(
                    "No findings",
                    systemImage: "stethoscope",
                    description: Text("No diagnostic data available."))
            } else {
                List(model.findings, id: \.self) { finding in
                    FindingRow(finding: finding, phrase: model.phrase(finding))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FindingRow: View {
    let finding: Finding
    let phrase: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(phrase).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var severity: Severity {
        switch finding {
        case .contextPosition(_, _, let s): return s
        case .prefillThroughput: return .healthy
        case .baselineDrift(_, _, _, let s): return s
        case .prefixCache(_, let s): return s
        case .compactionObserved: return .healthy
        case .compactionVerdict(_, let s): return s
        }
    }

    private var title: String {
        switch finding {
        case .contextPosition: return "Context"
        case .prefillThroughput: return "Prefill throughput"
        case .baselineDrift: return "Baseline drift"
        case .prefixCache: return "Prefix cache"
        case .compactionObserved: return "Compaction"
        case .compactionVerdict: return "Would compaction help?"
        }
    }

    private var symbol: String {
        switch severity {
        case .healthy: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .critical: return "xmark.octagon"
        }
    }

    private var color: Color {
        switch severity {
        case .healthy: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}
