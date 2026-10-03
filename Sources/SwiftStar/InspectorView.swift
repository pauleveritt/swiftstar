import SwiftUI
import SwiftStarKit

struct InspectorView: View {
    let metricsModel: MetricsModel

    var body: some View {
        let state = metricsModel.state
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Context").font(.headline)
                    HStack(spacing: 10) {
                        if let used = state.contextUsed, let size = state.contextSize, size > 0 {
                            ValueGaugeView(
                                fraction: Double(used) / Double(size),
                                text: nil, textFontSize: 0,
                                trackColor: Severity.ofContext(used: used, size: size).color,
                                diameter: 30)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            metricRow("Used", value: state.contextUsed.map { $0.formatted() } ?? "—")
                            metricRow("Window", value: state.contextSize.map { $0.formatted() } ?? "—")
                        }
                    }
                }
                .inspectorCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Throughput").font(.headline)
                    metricRow("Prefill avg", value: rate(state.prefillTPS))
                    metricRow("Generation avg", value: rate(state.generationTPS))
                }
                .inspectorCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("GPU memory").font(.headline)
                    metricRow("Allocated", value: bytes(state.gpuAllocatedBytes))
                    metricRow("Budget", value: bytes(state.gpuBudgetBytes))
                    metricRow("Plan", value: state.planGiB.map { String(format: "%.1f GiB", $0) } ?? "—")
                }
                .inspectorCard()
            }
            .padding(16)
        }
        .frame(minWidth: 280, idealWidth: 320)
    }

    private func rate(_ value: Double?) -> String {
        value.map { String(format: "%.1f tok/s", $0) } ?? "—"
    }

    private func bytes(_ value: Int64?) -> String {
        value.map { $0.formatted(.byteCount(style: .memory)) } ?? "—"
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
