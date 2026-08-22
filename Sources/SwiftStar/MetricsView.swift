import SwiftUI
import SwiftStarKit

struct MetricsView: View {
    @Bindable var model: MetricsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if model.isReplayingWire {
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
                Text(DialLogic.fixedWidth(String(format: "%.1f", Double(resident) / 1_073_741_824), width: 8) + " GiB of " +
                     String(format: "%.1f", Double(budget) / 1_073_741_824) + " GiB")
                    .font(.system(.body, design: .monospaced))
            } else {
                Text("—")
            }
        }
    }

    private var gpuDial: some View {
        dialCard("GPU", severity: .healthy) {
            Text(DialLogic.fixedWidth(String(format: "%.0f%%", model.machine.gpuUtilization), width: 6))
                .font(.system(.body, design: .monospaced))
        }
    }

    private var cpuDial: some View {
        dialCard("CPU", severity: .healthy) {
            Text(DialLogic.fixedWidth(String(format: "%.0f%%", model.machine.cpuUtilization), width: 6))
                .font(.system(.body, design: .monospaced))
        }
    }

    private var powerDial: some View {
        dialCard("Power", severity: .healthy) {
            Text(DialLogic.fixedWidth(String(format: "%.1f W", model.machine.watts), width: 8))
                .font(.system(.body, design: .monospaced))
        }
    }

    private func dialCard(_ title: String, severity: Severity, @ViewBuilder value: () -> some View) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color(for: severity))
                .frame(width: 12, height: 12)
            value()
            Text(title).font(.caption).foregroundStyle(.secondary)
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
