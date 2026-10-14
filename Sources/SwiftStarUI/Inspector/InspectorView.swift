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
                }
                .inspectorCard()

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
                    Text("Throughput").font(.scaled(.caption, base: fontSize).bold())
                    metricRow("Prefill avg", value: MetricsFormatting.rate(state.prefillTPS))
                    metricRow("Generation avg", value: MetricsFormatting.rate(state.generationTPS))
                }
                .inspectorCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("GPU memory").font(.scaled(.caption, base: fontSize).bold())
                    metricRow("Allocated", value: MetricsFormatting.bytes(state.gpuAllocatedBytes))
                    metricRow("Budget", value: MetricsFormatting.bytes(state.gpuBudgetBytes))
                    metricRow("Plan", value: state.planGiB.map { MetricsFormatting.gib($0) } ?? "—")
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
        .frame(width: 280, height: 560)
}
