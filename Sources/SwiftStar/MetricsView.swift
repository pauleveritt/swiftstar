import SwiftUI
import SwiftStarKit

struct MetricsView: View {
    let model: MetricsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if model.provenance == .recorded {
                    Label("capture replay — context and throughput are from a recorded session",
                          systemImage: "film")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 32) {
                    contextDial
                    throughputReadouts
                }

                Divider()

                HStack(spacing: 32) {
                    memoryDial
                    gpuDial
                    cpuDial
                    powerDial
                }
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    private var contextDial: some View {
        let ctx = model.state.ctxUsed
        let severity = ctx.map(DialLogic.contextSeverity(ctxUsed:)) ?? .healthy
        return VStack(spacing: 8) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 12)
                // Full ring colored by severity (a fixed-size ring is
                // jitter-proof by construction; a partial arc would read as a
                // fraction, which is the anchor we rejected).
                Circle().stroke(color(for: severity), lineWidth: 12)
                Text(ctx.map { DialLogic.fixedWidth(String($0), width: 8) } ?? "—")
                    .font(.system(.body, design: .monospaced))
            }
            .frame(width: 96, height: 96)
            // Learning #4: widen the hit region to the frame so the tooltip is
            // reachable (a stroked ring hit-tests only the stroke).
            .contentShape(Circle())
            .help(contextTooltip)
            Text("Context")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var throughputReadouts: some View {
        VStack(alignment: .leading, spacing: 8) {
            readout("Prompt", value: String(format: "%.1f tok/s", model.state.prefillTPS))
            readout("Decode", value: String(format: "%.1f tok/s", model.state.genTPS))
            if let ctx = model.state.ctxUsed, let size = model.state.ctxSize {
                Text("\(DialLogic.fixedWidth(String(ctx), width: 10)) of \(size) tokens")
                    .font(.system(.body, design: .monospaced))
            }
        }
    }

    private func readout(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Text(DialLogic.fixedWidth(value, width: 14))
                .font(.system(.body, design: .monospaced))
        }
    }

    private var memoryDial: some View {
        let budget = model.memoryBudgetPlannedBytes
        let resident = model.machine.residentBytes
        let severity = (resident != nil && budget != nil)
            ? DialLogic.memorySeverity(residentBytes: resident!, plannedBytes: budget!)
            : .healthy
        return dialCard("Memory", severity: severity) {
            if let resident, let budget {
                Text(resident.formatted(.byteCount(style: .memory)) + " of " +
                     budget.formatted(.byteCount(style: .memory)))
                    .font(.system(.body, design: .monospaced))
            } else {
                Text("—")
            }
        }
    }

    private var gpuDial: some View {
        // No agent pid = no sample taken. Rendering the zeroed snapshot as "0%"
        // would present an absence of measurement as a measured idle machine.
        dialCard("GPU", severity: .healthy) {
            sampledText(String(format: "%.0f%%", model.machine.gpuUtilization), width: 6)
        }
    }

    private var cpuDial: some View {
        dialCard("CPU", severity: .healthy) {
            sampledText(String(format: "%.0f%%", model.machine.cpuUtilization), width: 6)
        }
    }

    private var powerDial: some View {
        dialCard("Power", severity: .healthy) {
            sampledText(String(format: "%.1f W", model.machine.watts), width: 8)
        }
    }

    @ViewBuilder
    private func sampledText(_ value: String, width: Int) -> some View {
        Text(model.sampling ? DialLogic.fixedWidth(value, width: width) : "—")
            .font(.system(.body, design: .monospaced))
    }

    private func dialCard(_ title: String, severity: Severity, @ViewBuilder value: () -> some View) -> some View {
        VStack(spacing: 6) {
            // Severity pairs a symbol with the color: color alone is the sole
            // channel otherwise, which fails for red/green deficiency.
            // DiagnosticsView already does this; Metrics did not.
            Image(systemName: symbol(for: severity))
                .foregroundStyle(color(for: severity))
                .font(.system(size: 12))
                .accessibilityLabel("\(title) status: \(severity.label)")
            value()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func symbol(for severity: Severity) -> String {
        switch severity {
        case .healthy: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .critical: "xmark.octagon"
        }
    }

    private func color(for severity: Severity) -> Color {
        switch severity {
        case .healthy: .green
        case .warning: .yellow
        case .critical: .red
        }
    }

    private var contextTooltip: String {
        guard let ctx = model.state.ctxUsed else { return "No data yet" }
        return "\(ctx) tokens used"
    }
}
