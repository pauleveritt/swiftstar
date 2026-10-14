import SwiftUI
import SwiftStarKit

/// GPU memory allocated against what the engine planned for this model and
/// context, a small ring and the two figures in GiB (SU.6g, D2). Before a
/// plan arrives, macOS's GPU limit stands in.
struct MemoryStatusView: View {
    let allocatedBytes: Int64
    let planGiB: Double?
    let limitBytes: Int64
    @Environment(\.fontSize) private var fontSize: CGFloat

    /// What the ring fills against, in bytes: the plan, else the limit.
    private var targetBytes: Double {
        planGiB.map { $0 * 1_073_741_824 } ?? Double(limitBytes)
    }

    var body: some View {
        let tooltip = MetricsFormatting.gpuTooltip(allocated: allocatedBytes, planGiB: planGiB, limit: limitBytes)
        let target = planGiB.map { MetricsFormatting.gib($0) } ?? MetricsFormatting.bytes(limitBytes)
        HStack(spacing: 4) {
            ValueGaugeView(
                fraction: min(Double(allocatedBytes) / targetBytes, 1.0),
                trackColor: .green,
                diameter: 15)
            Text("\(MetricsFormatting.bytes(allocatedBytes)) / \(target)")
                .font(.scaled(.caption2, base: fontSize))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                // One line: it wrapped beside the rates in a narrow window.
                .lineLimit(1)
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .help(tooltip)
        .accessibilityElement()
        .accessibilityLabel("GPU memory")
        .accessibilityValue(tooltip)
        .nativeTooltip(tooltip)
    }
}

#Preview("Against the plan") {
    MemoryStatusView(allocatedBytes: 6_442_450_944, planGiB: 26.07, limitBytes: 115_448_000_000)
        .padding()
}

#Preview("No plan yet") {
    MemoryStatusView(allocatedBytes: 10_000_000_000, planGiB: nil, limitBytes: 20_000_000_000)
        .padding()
}
