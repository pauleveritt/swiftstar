import SwiftUI
import SwiftStarKit

/// GPU memory allocated against the engine's budget: a small ring and the
/// two figures.
struct MemoryStatusView: View {
    let allocatedBytes: Int64
    let budgetBytes: Int64
    @Environment(\.fontSize) private var fontSize: CGFloat

    var body: some View {
        let tooltip = "GPU memory: \(MetricsFormatting.bytes(allocatedBytes)) allocated of \(MetricsFormatting.bytes(budgetBytes)) budget."
        HStack(spacing: 4) {
            ValueGaugeView(
                fraction: min(Double(allocatedBytes) / Double(budgetBytes), 1.0),
                trackColor: .green,
                diameter: 15)
            Text("\(MetricsFormatting.bytes(allocatedBytes)) / \(MetricsFormatting.bytes(budgetBytes))")
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

#Preview("Half full") {
    MemoryStatusView(allocatedBytes: 10_000_000_000, budgetBytes: 20_000_000_000)
        .padding()
}
