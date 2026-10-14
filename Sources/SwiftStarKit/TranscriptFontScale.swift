import Foundation

/// The window's five body-font sizes, as discrete slider slots; the middle
/// one (18 pt) is the default (SU.9). Every text in the window scales from
/// it. Lives in Kit so the slider (Settings) and the clamp (stored values
/// that drift out of range) share one definition.
public enum TranscriptFontScale {
    public static let sizes: [Int] = [14, 16, 18, 20, 24]
    public static let defaultSize: Int = 18

    /// The slider slot for a stored size (an out-of-range value takes its
    /// nearest slot).
    public static func slot(for size: Int) -> Int {
        sizes.firstIndex(of: clamp(size)) ?? sizes.count - 1
    }

    /// The size at a slider slot, clamped to the slots there are.
    public static func size(forSlot slot: Int) -> Int {
        sizes[max(0, min(sizes.count - 1, slot))]
    }

    /// Clamps an arbitrary value to the nearest defined slot (a hand-edited or
    /// stale UserDefaults value must not fall off the slider). Ties resolve to
    /// the smaller size.
    public static func clamp(_ size: Int) -> Int {
        sizes.min { a, b in
            (abs(a - size), a) < (abs(b - size), b)
        } ?? defaultSize
    }

    /// One slot up from `size`'s slot, or nil at the largest (View › Bigger).
    public static func bigger(_ size: Int) -> Int? {
        let slot = slot(for: size) + 1
        return slot < sizes.count ? sizes[slot] : nil
    }

    /// One slot down from `size`'s slot, or nil at the smallest.
    public static func smaller(_ size: Int) -> Int? {
        let slot = slot(for: size) - 1
        return slot >= 0 ? sizes[slot] : nil
    }

    /// A smaller text's size for a body size `base`, in macOS's own
    /// proportions to its 13 pt body.
    public static func points(_ role: TextRole, base: Double) -> Double {
        switch role {
        case .caption: base * 0.8
        case .caption2: base * 0.72
        }
    }
}

/// The text styles that scale with the window's font size.
public enum TextRole: Sendable {
    case caption, caption2
}
