import SwiftUI
import SwiftStarKit

/// Bottom readout bar: left = fixed-width prefill/generation rates and the
/// phase, right = memory and the context-fill ring.
struct StatusBarView: View {
    let phase: EngineSessionPhase
    /// The composer's status label (it carries the exit message once the
    /// session has ended).
    let composerLabel: String
    let metrics: EngineMetricsState
    @Environment(\.transcriptFontSize) private var transcriptFontSize: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Text(statusText)
                .font(.system(size: transcriptFontSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.default, value: statusText)
            Spacer(minLength: 12)
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

    private var statusText: String {
        MetricsFormatting.statusLine(phase: phase, label: composerLabel, metrics: metrics)
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
    .onAppear {
        // One flip per main run-loop turn, so each one is its own update.
        func flip() {
            guard flips < 6 else { return }
            showsGPU.toggle()
            flips += 1
            DispatchQueue.main.async { flip() }
        }
        DispatchQueue.main.async { flip() }
    }
}
