import SwiftUI
import SwiftStarKit

struct InspectorView: View {
    @Environment(EngineController.self) private var engine

    var body: some View {
        let state = engine.metrics
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Context").font(.headline)
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
                    Text("Throughput").font(.headline)
                    metricRow("Prefill avg", value: MetricsFormatting.rate(state.prefillTPS))
                    metricRow("Generation avg", value: MetricsFormatting.rate(state.generationTPS))
                }
                .inspectorCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("GPU memory").font(.headline)
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
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).font(.system(.body, design: .monospaced))
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
