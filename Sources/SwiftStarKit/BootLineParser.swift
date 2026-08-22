import Foundation

public enum BootLineParser {
    /// Extracts the engine's startup memory plan (bytes) from the boot line
    /// "… = 46.51 GiB planned" (the `ds4: memory:` stderr line, P1/P2 verified:
    /// P1 fixtures/agent/provenance.md and the P2 live-smoke boot log).
    public static func plannedBytes(from line: String) -> Int64? {
        let parts = line.split(separator: " ")
        // "… = 46.51 GiB planned" — value, unit, keyword.
        guard let eq = parts.firstIndex(of: "="), eq + 3 < parts.count,
              parts[eq + 2] == "GiB", parts[eq + 3] == "planned" else { return nil }
        let value = Double(parts[eq + 1].trimmingCharacters(in: .whitespaces))
        guard let value else { return nil }
        return Int64(value * 1_073_741_824)
    }
}
