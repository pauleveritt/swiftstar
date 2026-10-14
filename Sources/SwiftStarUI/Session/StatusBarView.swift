import SwiftUI
import SwiftStarKit

/// Bottom readout bar: left = the composer's label; right = the two token
/// rates while running, memory and the context-fill ring.
struct StatusBarView: View {
    let phase: EngineSessionPhase
    /// The composer's status label (it carries the exit message once the
    /// session has ended).
    let composerLabel: String
    let metrics: EngineMetricsState
    @Environment(\.fontSize) private var fontSize: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Text(statusText)
                .font(.system(size: fontSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.default, value: statusText)
            Spacer(minLength: 12)
            if phase == .running {
                RatesView(prefill: metrics.prefillTPS, generation: metrics.generationTPS)
            }
            if let allocated = metrics.gpuAllocatedBytes,
               let budget = metrics.gpuBudgetBytes, budget > 0 {
                MemoryStatusView(allocatedBytes: allocated, budgetBytes: budget)
            }
            if let used = metrics.contextUsed,
               let size = metrics.contextSize, size > 0 {
                let tooltip = MetricsFormatting.contextTooltip(used: used, size: size)
                ValueGaugeView(
                    fraction: Double(used) / Double(size),
                    trackColor: Severity.ofContext(used: used, size: size).color,
                    diameter: 15)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                    .help(tooltip)
                    .accessibilityElement()
                    .accessibilityLabel("Context window")
                    .accessibilityValue(tooltip)
                    .nativeTooltip(tooltip)
            }
        }
        .padding(.horizontal, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
    }

    /// The composer's label alone (it carries the exit message once ended).
    private var statusText: String { composerLabel }
}

/// The two session-average rates as bare numbers, prefill then generation
/// (SU.10). Each sits in a slot sized for the widest expected number, so
/// they hold still as digits come and go; the tooltip names them.
private struct RatesView: View {
    let prefill: Double?
    let generation: Double?
    @Environment(\.fontSize) private var fontSize: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            // Both hug the slash; the slots' spare width falls outside.
            number(prefill, alignment: .trailing)
            Text("/").foregroundStyle(.tertiary)
            number(generation, alignment: .leading)
        }
        .font(.scaled(.caption, base: fontSize))
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .help(MetricsFormatting.ratesTooltip(prefill: prefill, generation: generation))
        .accessibilityElement()
        .accessibilityLabel("Token rates")
        .accessibilityValue(MetricsFormatting.ratesTooltip(prefill: prefill, generation: generation))
    }

    /// The number in a hidden slot of the widest width.
    private func number(_ value: Double?, alignment: Alignment) -> some View {
        Text(MetricsFormatting.rateSlot)
            .hidden()
            .overlay(alignment: alignment) {
                Text(MetricsFormatting.rateNumber(value))
                    .contentTransition(.numericText())
                    .animation(.default, value: value)
            }
    }
}

#Preview("Running") {
    StatusBarView(phase: .running, composerLabel: "Ready", metrics: .previewRunning)
        .frame(width: 700)
}

#Preview("Idle") {
    StatusBarView(phase: .idle, composerLabel: "Not started", metrics: EngineMetricsState())
        .frame(width: 700)
}

#Preview("No GPU metrics") {
    StatusBarView(phase: .running, composerLabel: "Ready", metrics: EngineController.previewRunningNoGPU.metrics)
        .frame(width: 700)
}

// SU.3's Backlog: the memory widget crashed the preview agent in SwiftUI's
// debug view storage when GPU metrics went from present to absent. Open this
// preview in the live canvas: it flips them both ways six times on its own
// (then by hand with the toggle). RenderPreview can't run this check; it
// snapshots the first frame, before any flip ("Automatic flips: 0 of 6").
#Preview("GPU toggle") {
    @Previewable @State var showsGPU = true
    @Previewable @State var flips = 0
    VStack(alignment: .leading) {
        Toggle("GPU metrics", isOn: $showsGPU)
        // Shows in a snapshot that the automatic flips really ran.
        Text("Automatic flips: \(flips) of 6")
            .font(.caption)
            .foregroundStyle(.secondary)
        StatusBarView(
            phase: .running, composerLabel: "Ready",
            metrics: showsGPU ? .previewRunning : EngineController.previewRunningNoGPU.metrics)
    }
    .padding()
    .frame(width: 700)
    .task {
        // On the main actor, a short pause apart, so each flip is its own
        // update (the old DispatchQueue closures were nonisolated and touched
        // this main-actor state: six warnings).
        while flips < 6 {
            try? await Task.sleep(for: .milliseconds(100))
            showsGPU.toggle()
            flips += 1
        }
    }
}
