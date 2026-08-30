import SwiftUI

enum InspectorTab: CaseIterable, Hashable, Identifiable {
    case metrics, diagnostics

    var id: Self { self }

    var title: String {
        switch self {
        case .metrics: "Metrics"
        case .diagnostics: "Diagnostics"
        }
    }

    var systemImage: String {
        switch self {
        case .metrics: "gauge"
        case .diagnostics: "stethoscope"
        }
    }
}

struct InspectorView: View {
    @Binding var tab: InspectorTab
    let metricsModel: MetricsModel
    let diagnosticsModel: DiagnosticsModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                ForEach(InspectorTab.allCases) { item in
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            tab = item
                        }
                    } label: {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(tab == item ? .primary : .secondary)
                    .background {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(tab == item ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear))
                    }
                    .help(item.title)
                    .accessibilityLabel(item.title)
                    .accessibilityHint("Show (item.title) in the inspector")
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
                }

                Spacer()
            }
            .padding(.top, 10)
            .padding(.horizontal, 7)
            .frame(width: 46)

            Divider()

            Group {
                switch tab {
                case .metrics:
                    MetricsInspectorView(model: metricsModel)
                case .diagnostics:
                    DiagnosticsView(model: diagnosticsModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 280, idealWidth: 320)
    }
}

private struct MetricsInspectorView: View {
    let model: MetricsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.provenance == .recorded {
                    Label("Recorded session", systemImage: "film")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Context").font(.headline)
                    metricRow("Used", value: model.state.ctxUsed.map(String.init) ?? "—")
                    metricRow("Window", value: model.state.ctxSize.map(String.init) ?? "—")
                }
                .inspectorCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Throughput").font(.headline)
                    metricRow("Prompt", value: String(format: "%.1f tok/s", model.state.prefillTPS))
                    metricRow("Decode", value: String(format: "%.1f tok/s", model.state.genTPS))
                }
                .inspectorCard()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Machine").font(.headline)
                    metricRow("Memory", value: memoryValue)
                    metricRow("GPU", value: sampled("%.0f%%", model.machine.gpuUtilization))
                    metricRow("CPU", value: sampled("%.0f%%", model.machine.cpuUtilization))
                    metricRow("Power", value: sampled("%.1f W", model.machine.watts))
                    metricRow("Throttle", value: model.provenance == .live
                              ? String(format: "%.0f%%", model.state.throttlePercent) : "—")
                }
                .inspectorCard()
            }
            .padding(16)
        }
    }

    private var memoryValue: String {
        guard let resident = model.machine.residentBytes,
              let budget = model.memoryBudgetPlannedBytes else { return "—" }
        return resident.formatted(.byteCount(style: .memory)) + " / "
            + budget.formatted(.byteCount(style: .memory))
    }

    private func sampled(_ format: String, _ value: Double) -> String {
        model.sampling ? String(format: format, value) : "—"
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
