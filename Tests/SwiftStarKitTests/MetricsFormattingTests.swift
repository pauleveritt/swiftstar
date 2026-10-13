import Foundation
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
        #expect(MetricsFormatting.contextTooltip(used: 512, size: 2048, locale: Locale(identifier: "en_US"))
            == "Context window: 512 of 2,048 tokens (25% used).")
    }

    @Test func formattingFollowsLocale() {
        #expect(MetricsFormatting.number(8192, locale: Locale(identifier: "de_DE")) == "8.192")
        #expect(MetricsFormatting.number(8192, locale: Locale(identifier: "en_US")) == "8,192")
        #expect(MetricsFormatting.gib(bytes: 6_442_450_944, locale: Locale(identifier: "de_DE")) == "6,0 GiB")
        #expect(MetricsFormatting.gib(bytes: 6_442_450_944, locale: Locale(identifier: "en_US")) == "6.0 GiB")
    }

    @Test func durationOneStyle() {
        #expect(MetricsFormatting.duration(seconds: 75) == "75s")
        #expect(MetricsFormatting.duration(seconds: 1.83) == "1.8s")
        #expect(MetricsFormatting.duration(seconds: 9.96) == "10s")
    }

    @Test func trimmedOrNil() {
        #expect("  \n".trimmedOrNil == nil)
        #expect(" a \n".trimmedOrNil == "a")
    }

    @Test func gracesStandard() {
        #expect(EngineGraces.standard.safetyBound == .seconds(30))
        #expect(EngineSessionConstants.stderrTailLimit == 4096)
    }

    @Test func statusLineRunningAndNot() {
        var m = EngineMetricsState()
        EngineMetricsReducer.reduce(&m, .pause(PauseMetrics(prefillTokens: 100, prefillMs: 1000, evalCount: 10, evalMs: 1000)))
        #expect(MetricsFormatting.statusLine(phase: .running, label: "Ready", metrics: m)
            == "Prefill avg 100.0 tok/s · Generation avg 10.0 tok/s · Ready")
        #expect(MetricsFormatting.statusLine(phase: .idle, label: "Not started", metrics: m) == "Not started")
    }
}
