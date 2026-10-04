import SwiftUI
import SwiftStarKit

/// GPU memory allocated against the engine's budget: a small ring and the
/// two figures.
struct MemoryStatusView: View {
    let allocatedBytes: Int64
    let budgetBytes: Int64

    var body: some View {
        let tooltip = "GPU memory: \(MetricsFormatting.bytes(allocatedBytes)) allocated of \(MetricsFormatting.bytes(budgetBytes)) budget."
        HStack(spacing: 4) {
            ValueGaugeView(
                fraction: min(Double(allocatedBytes) / Double(budgetBytes), 1.0),
                trackColor: .green,
                diameter: 15)
            Text("\(MetricsFormatting.bytes(allocatedBytes)) / \(MetricsFormatting.bytes(budgetBytes))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
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
