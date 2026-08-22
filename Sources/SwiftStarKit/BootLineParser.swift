import Foundation

public enum BootLineParser {
    /// Extracts the engine's startup memory plan (bytes) from the boot line
    /// "… = 46.51 GiB planned" (the `ds4: memory:` stderr line, P1/P2 verified:
    /// P1 fixtures/agent/provenance.md and the P2 live-smoke boot log).
    /// Anchored on the "GiB planned" tail (walking backward) so an earlier
    /// "=" in the line cannot mislead. The result is an estimate (two decimal
    /// places); callers should treat it as a plan, not a precise byte count.
    public static func plannedBytes(from line: String) -> Int64? {
        let parts = line.split(separator: " ")
        guard let planned = parts.lastIndex(of: "planned"),
              planned >= 2, parts[planned - 1] == "GiB",
              let value = Double(parts[planned - 2].trimmingCharacters(in: .whitespaces)),
              value > 0, value < 1_000_000  // a plan over 1M GiB is garbage, not RAM
        else { return nil }
        return Int64(value * 1_073_741_824)
    }
}
