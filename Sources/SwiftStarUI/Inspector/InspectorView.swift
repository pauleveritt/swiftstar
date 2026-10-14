import SwiftUI
import SwiftStarKit

struct InspectorView: View {
    @Environment(EngineController.self) private var engine
    @Environment(\.transcriptFontSize) private var transcriptFontSize: CGFloat

    var body: some View {
        let state = engine.metrics
        let session = engine.transcript.session
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Session").font(.scaled(.headline, base: transcriptFontSize))
                    metricRow("Model", value: session?.modelID ?? "—")
                    metricRow("DFlash", value: session?.dflash.map { $0.on ? "On" : "Off" } ?? "—")
                    if let dflash = session?.dflash {
                        // The engine's reason, word for word (SU.6b, D2).
                        Text(dflash.reason)
                            .font(.scaled(.caption, base: transcriptFontSize))
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
                    Text("Context").font(.scaled(.headline, base: transcriptFontSize))
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
                    Text("Throughput").font(.scaled(.headline, base: transcriptFontSize))
                    metricRow("Prefill avg", value: MetricsFormatting.rate(state.prefillTPS))
                    metricRow("Generation avg", value: MetricsFormatting.rate(state.generationTPS))
                }
                .inspectorCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("GPU memory").font(.scaled(.headline, base: transcriptFontSize))
                    metricRow("Allocated", value: MetricsFormatting.bytes(state.gpuAllocatedBytes))
                    metricRow("Budget", value: MetricsFormatting.bytes(state.gpuBudgetBytes))
                    metricRow("Plan", value: state.planGiB.map { MetricsFormatting.gib($0) } ?? "—")
                }
                .inspectorCard()
            }
            .padding(16)
        }
        .frame(minWidth: 280, idealWidth: 320)
    }

    private func metricRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.system(size: transcriptFontSize)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).font(.system(size: transcriptFontSize, design: .monospaced))
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
