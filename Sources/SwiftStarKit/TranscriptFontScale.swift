import Foundation

/// The transcript's four body-font sizes, as discrete slider slots. The third
/// slot (16 pt) is the default — one below the largest (18), per the product
/// decision. Lives in Kit so the slider (Settings) and the clamp (stored
/// values that drift out of range) share one definition.
public enum TranscriptFontScale {
    public static let sizes: [Int] = [12, 14, 16, 18]
    public static let defaultSize: Int = 16

    /// Clamps an arbitrary value to the nearest defined slot (a hand-edited or
    /// stale UserDefaults value must not fall off the slider). Ties resolve to
    /// the smaller size.
    public static func clamp(_ size: Int) -> Int {
        sizes.min { a, b in
            (abs(a - size), a) < (abs(b - size), b)
        } ?? defaultSize
    }
}
