import Foundation
import Testing
@testable import SwiftStarKit

struct MetricsFormattingTests {
    // Dropped in SU.5b: bytesFormatsByteCount (it compared the formatter with itself).

    // One table per function (SU.17), each with its locale, so no row
    // depends on the machine's.
    private static let en = Locale(identifier: "en_US"), de = Locale(identifier: "de_DE")

    @Test(arguments: [
        (12.34 as Double?, en, "12.3 tok/s"),
        (nil, en, "—"),                         // rateIsEmDashForNil
        (12.34, de, "12,3 tok/s"),
    ]) func rate(_ value: Double?, _ locale: Locale, _ text: String) {
        #expect(MetricsFormatting.rate(value, locale: locale) == text)
    }

    @Test(arguments: [(189.84, de, "189,8"), (189.84, en, "189.8")])
    func rateNumber(_ value: Double, _ locale: Locale, _ text: String) {
        #expect(MetricsFormatting.rateNumber(value, locale: locale) == text)
    }

    // SU.6g, D2-D3: bytes in GiB like the engine's plan; decimals by locale.
    @Test(arguments: [
        (6_442_450_944 as Int64?, en, "6.0 GiB"),
        (nil, en, "—"),                         // bytesIsEmDashForNil
    ]) func bytes(_ value: Int64?, _ locale: Locale, _ text: String) {
        #expect(MetricsFormatting.bytes(value, locale: locale) == text)
    }

    @Test(arguments: [(Int64(6_442_450_944), de, "6,0 GiB"), (Int64(6_442_450_944), en, "6.0 GiB")])
    func gib(_ value: Int64, _ locale: Locale, _ text: String) {
        #expect(MetricsFormatting.gib(bytes: value, locale: locale) == text)
    }

    @Test(arguments: [(8192, de, "8.192"), (8192, en, "8,192")])
    func number(_ value: Int, _ locale: Locale, _ text: String) {
        #expect(MetricsFormatting.number(value, locale: locale) == text)
    }

    /// One style: tenths under ten seconds, whole seconds from there.
    @Test(arguments: [
        (75.0, en, "75s"),
        (1.83, en, "1.8s"),
        (9.96, en, "10s"),                     // rounds up to whole
        (1.83, de, "1,8s"),
    ]) func duration(_ seconds: Double, _ locale: Locale, _ text: String) {
        #expect(MetricsFormatting.duration(seconds: seconds, locale: locale) == text)
    }

    // SU.6b: the Session card's prefix-cache line.
    @Test(arguments: [
        (EnginePrefixCache(outcome: "hit", tokens: 944, loadMs: 20, fillMs: nil), "hit · 944 tokens in 20 ms"),
        (EnginePrefixCache(outcome: "miss", tokens: 944, loadMs: nil, fillMs: 3880), "miss · 944 tokens filled in 3.9s"),
        (EnginePrefixCache(outcome: "error", tokens: 944, loadMs: nil, fillMs: nil), "error · 944 tokens"),
    ]) func prefixCacheLine(_ p: EnginePrefixCache, _ line: String) {
        #expect(MetricsFormatting.prefixCacheLine(p, locale: Locale(identifier: "en_US")) == line)
    }

    /// SU.17: the fill time follows the locale too, as the token count does.
    @Test func prefixCacheLineDurationFollowsTheLocale() {
        let miss = EnginePrefixCache(outcome: "miss", tokens: 1944, loadMs: nil, fillMs: 3880)
        #expect(MetricsFormatting.prefixCacheLine(miss, locale: Locale(identifier: "de_DE"))
            == "miss · 1.944 tokens filled in 3,9s")
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

    /// SU.6g, D2 (revised by the owner): actual against what the engine
    /// planned for this model and context; macOS's limit only as context.
    @Test func gpuTooltip() {
        let en = Locale(identifier: "en_US")
        #expect(MetricsFormatting.gpuTooltip(allocated: 6_442_450_944, planGiB: 26.07, limit: 115_448_000_000, locale: en)
            == "GPU memory: 6.0 GiB allocated, of the 26.1 GiB the engine planned for this model and context. macOS lets the GPU use up to 107.5 GiB on this Mac.")
        #expect(MetricsFormatting.gpuTooltip(allocated: 6_442_450_944, planGiB: nil, limit: 21_474_836_480, locale: en)
            == "GPU memory: 6.0 GiB allocated. macOS lets the GPU use up to 20.0 GiB on this Mac.")
    }
}
