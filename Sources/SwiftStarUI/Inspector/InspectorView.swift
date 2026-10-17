import SwiftUI
import SwiftStarKit

struct InspectorView: View {
    @Environment(EngineController.self) private var engine
    @Environment(\.fontSize) private var fontSize: CGFloat

    var body: some View {
        let state = engine.metrics
        let session = engine.transcript.session
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Session").font(.scaled(.caption, base: fontSize).bold())
                    metricRow("Model", value: session?.modelID ?? "—")
                    metricRow("DFlash", value: session?.dflash.map { $0.on ? "On" : "Off" } ?? "—")
                    if let dflash = session?.dflash {
                        // The engine's reason, word for word (SU.6b, D2).
                        Text(dflash.reason)
                            .font(.scaled(.caption, base: fontSize))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if dflash.on, let drafter = dflash.drafter {
                            metricRow("Drafter", value: URL(fileURLWithPath: drafter).lastPathComponent)
                        }
                    }
                    metricRow("Prefix cache", value: state.prefixCache.map { MetricsFormatting.prefixCacheLine($0) } ?? "—")
                    // Sent only on resume (EN.2, D4).
                    if let saved = state.conversationState {
                        metricRow("Saved state", value: MetricsFormatting.conversationStateLine(saved, subject: false))
                    }
                }
                .inspectorCard()

                // The engine's start-up reports, as it sent them (EN.2, D2).
                let startup = MetricsFormatting.startupRows(state.startup)
                if !startup.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Start-up").font(.scaled(.caption, base: fontSize).bold())
                        ForEach(startup, id: \.0) { row in
                            metricRow(row.0, value: row.1)
                        }
                    }
                    .inspectorCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Context").font(.scaled(.caption, base: fontSize).bold())
                    HStack(spacing: 10) {
                        if let used = state.contextUsed, let size = state.contextSize, size > 0 {
                            ValueGaugeView(
                                fraction: Double(used) / Double(size),
                                trackColor: Severity.ofContext(used: used, size: size).color,
                                diameter: 30)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            metricRow("Used", value: state.contextUsed.map { MetricsFormatting.number($0) } ?? "—")
                            metricRow("Window", value: state.contextSize.map { MetricsFormatting.number($0) } ?? "—")
                        }
                    }
                }
                .inspectorCard()

                VStack(alignment: .leading, spacing: 10) {
                    // SU.6g, D1: the engine's counters run over the session.
                    Text("Session averages").font(.scaled(.caption, base: fontSize).bold())
                    metricRow("Prefill", value: MetricsFormatting.rate(state.prefillTPS))
                    metricRow("Generation", value: MetricsFormatting.rate(state.generationTPS))
                }
                .inspectorCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("GPU memory").font(.scaled(.caption, base: fontSize).bold())
                    // SU.6g, D2: actual against planned; macOS's limit last.
                    metricRow("Allocated", value: MetricsFormatting.bytes(state.gpuAllocatedBytes))
                    metricRow("Planned", value: state.planGiB.map { MetricsFormatting.gib($0) } ?? "—")
                    metricRow("GPU limit", value: MetricsFormatting.bytes(state.gpuBudgetBytes))
                }
                .inspectorCard()
            }
            .padding(16)
        }
        // A fixed column width, the owner's call (2026-10-14): a narrow info
        // panel needn't resize. A `.frame` on the content doesn't size the
        // column (it clipped); MainView's minimum keeps the session column
        // from being squeezed, which looped AppKit's layout (SU.11).
        .inspectorColumnWidth(300)
    }

    /// Label and value on one line when they fit; otherwise the value goes
    /// under its label, so a long one (a drafter file, the prefix cache
    /// line) doesn't wrap into a column beside it at large font sizes.
    private func metricRow(_ title: String, value: String) -> some View {
        // The conversation list's size (owner, 2026-10-14); values in the
        // labels' font, digits fixed-width (SU.11, D5).
        let label = Text(title).font(.scaled(.caption, base: fontSize)).foregroundStyle(.secondary)
        let shown = Text(value).font(.scaled(.caption, base: fontSize)).monospacedDigit()
        return ViewThatFits(in: .horizontal) {
            HStack {
                label
                Spacer(minLength: 8)
                shown.lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                label
                shown
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension View {
    func inspectorCard() -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview("Running", traits: .runningSession) {
    InspectorView()
}

// The owner's 2026-10-14 screenshot: at 18 pt and the inspector's minimum
// width, the drafter and prefix-cache values wrapped beside their labels.
#Preview("Narrow", traits: .runningSession) {
    InspectorView()
        .frame(width: 280, height: 900)
}

// EN.2, D4: a resumed conversation's saved state, loaded.
#Preview("Resumed") {
    var model = EngineController.runningModel(withGPU: true)
    model.apply(.conversationState(EngineConversationState(
        outcome: "loaded", bytes: 365_000_000, loadMs: 1200, error: nil)))
    return InspectorView()
        .environment(EngineController(model: model))
        .frame(height: 900)
}
