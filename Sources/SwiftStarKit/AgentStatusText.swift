import Foundation

/// The bottom status bar's left-hand readout: the wire's `status.state` mapped
/// to prose, plus the fixed-width Prompt/Decode rate line (ported from the
/// DS4 Control agent window, `2989d2c`: rates are ratcheted — held at the last
/// nonzero reading — because the wire reports only one of prefill/gen as
/// nonzero per event, and a view-level ratchet silently drops intermediate
/// readings).
public enum AgentStatusText {
    /// The wire's eight `status.state` names → a short activity message.
    public static func stateMessage(_ state: String) -> String {
        switch state {
        case "idle": return "Ready"
        case "prefill": return "Prefilling…"
        case "generating": return "Working…"
        case "compacting": return "Compacting…"
        case "draining": return "Draining…"
        case "saving": return "Saving…"
        case "error": return "Error"
        case "stopped": return "Stopped"
        default: return "Working…"
        }
    }

    /// Fixed-width Prompt/Decode prefix followed by the activity message: only
    /// the message — the one part whose length changes — moves, so the eye can
    /// stay locked on the numbers. Rounded to whole tok/s; the tenths digit is
    /// not meaningful at these rates.
    public static func promptDecodeLine(promptTPS: Double, decodeTPS: Double, message: String) -> String {
        String(format: "Prompt %4.0f / Decode %4.0f tok/s — %@", promptTPS, decodeTPS, message)
    }

    /// The `2989d2c` lesson, as a pure function: keep the last nonzero reading.
    /// A fresh nonzero replaces it; a zero leaves it untouched.
    public static func ratchet(previous: Double, new: Double) -> Double {
        new > 0 ? new : previous
    }
}
