import Foundation
import Testing
@testable import SwiftStarKit

struct MetricsFormattingTests {
    // Dropped in SU.5b: bytesFormatsByteCount (it compared the formatter with itself).

    enum Value: Sendable {
        case rate(Double?), bytes(Int64?), number(Int, String), gib(Int64, String), duration(Double)
    }

    struct FormatCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let value: Value
        let text: String
    }

    static let formatCases: [FormatCase] = [
        .init(testDescription: "rateFormatsOneDecimalWithUnit", value: .rate(12.34), text: "12.3 tok/s"),
        .init(testDescription: "rateIsEmDashForNil", value: .rate(nil), text: "—"),
        .init(testDescription: "bytesIsEmDashForNil", value: .bytes(nil), text: "—"),
        .init(testDescription: "formattingFollowsLocale (number, de_DE)", value: .number(8192, "de_DE"), text: "8.192"),
        .init(testDescription: "formattingFollowsLocale (number, en_US)", value: .number(8192, "en_US"), text: "8,192"),
        .init(testDescription: "formattingFollowsLocale (GiB, de_DE)", value: .gib(6_442_450_944, "de_DE"),
              text: "6,0 GiB"),
        .init(testDescription: "formattingFollowsLocale (GiB, en_US)", value: .gib(6_442_450_944, "en_US"),
              text: "6.0 GiB"),
        .init(testDescription: "durationOneStyle (whole)", value: .duration(75), text: "75s"),
        .init(testDescription: "durationOneStyle (one decimal)", value: .duration(1.83), text: "1.8s"),
        .init(testDescription: "durationOneStyle (rounds up to whole)", value: .duration(9.96), text: "10s"),
    ]

    @Test(arguments: formatCases) func formats(_ c: FormatCase) {
        let text = switch c.value {
        case .rate(let v): MetricsFormatting.rate(v)
        case .bytes(let v): MetricsFormatting.bytes(v)
        case .number(let n, let id): MetricsFormatting.number(n, locale: Locale(identifier: id))
        case .gib(let b, let id): MetricsFormatting.gib(bytes: b, locale: Locale(identifier: id))
        case .duration(let s): MetricsFormatting.duration(seconds: s)
        }
        #expect(text == c.text)
    }

    // SU.6b: the Session card's prefix-cache line.
    @Test(arguments: [
        (EnginePrefixCache(outcome: "hit", tokens: 944, loadMs: 20, fillMs: nil), "hit · 944 tokens in 20 ms"),
        (EnginePrefixCache(outcome: "miss", tokens: 944, loadMs: nil, fillMs: 3880), "miss · 944 tokens filled in 3.9s"),
        (EnginePrefixCache(outcome: "error", tokens: 944, loadMs: nil, fillMs: nil), "error · 944 tokens"),
    ]) func prefixCacheLine(_ p: EnginePrefixCache, _ line: String) {
        #expect(MetricsFormatting.prefixCacheLine(p, locale: Locale(identifier: "en_US")) == line)
    }

    @Test func contextTooltipMatchesTodaysWording() {
        #expect(MetricsFormatting.contextTooltip(used: 512, size: 2048, locale: Locale(identifier: "en_US"))
            == "Context window: 512 of 2,048 tokens (25% used).")
    }

    @Test(arguments: [("  \n", String?.none), (" a \n", "a")]) func trimmedOrNil(_ s: String, _ trimmed: String?) {
        #expect(s.trimmedOrNil == trimmed)
    }

    @Test func gracesStandard() {
        #expect(EngineGraces.standard.safetyBound == .seconds(30))
        #expect(EngineSessionConstants.stderrTailLimit == 4096)
    }

    /// SU.10: the status bar's two numbers, and the tooltip that names them.
    @Test func statusRates() {
        var m = EngineMetricsState()
        #expect(MetricsFormatting.rateNumber(m.prefillTPS) == "—")
        #expect(MetricsFormatting.ratesTooltip(prefill: nil, generation: nil)
            == "Prefill and generation, in tokens per second: averages over this session, once a turn has run.")
        EngineMetricsReducer.reduce(&m, .pause(PauseMetrics(prefillTokens: 100, prefillMs: 1000, evalCount: 10, evalMs: 1000)))
        #expect(MetricsFormatting.rateNumber(m.prefillTPS) == "100.0")
        #expect(MetricsFormatting.rateNumber(m.generationTPS) == "10.0")
        #expect(MetricsFormatting.ratesTooltip(prefill: m.prefillTPS, generation: m.generationTPS)
            == "Prefill 100.0 tok/s, generation 10.0 tok/s: averages over this session.")
        #expect(MetricsFormatting.rateSlot == "8888.8")
    }
}
