import Testing
@testable import SwiftStarKit

struct MetricsFormattingTests {
    @Test func rateFormatsOneDecimalWithUnit() {
        #expect(MetricsFormatting.rate(12.34) == "12.3 tok/s")
    }

    @Test func rateIsEmDashForNil() {
        #expect(MetricsFormatting.rate(nil) == "—")
    }

    @Test func bytesFormatsByteCount() {
        #expect(MetricsFormatting.bytes(1_048_576)
            == Int64(1_048_576).formatted(.byteCount(style: .memory)))
    }

    @Test func bytesIsEmDashForNil() {
        #expect(MetricsFormatting.bytes(nil) == "—")
    }

    @Test func contextTooltipMatchesTodaysWording() {
        #expect(MetricsFormatting.contextTooltip(used: 512, size: 2048)
            == "Context window: 512 of 2,048 tokens (25% used).")
    }
}
