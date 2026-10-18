import Foundation

/// Reads a session directory's `receipt.json`, which the engine refreshes at
/// every pause (ds4-engine `session_receipt.py:175`), for the candidate
/// worktree: where the engine's edited copies are (SU.16, D3).
public enum ReceiptReader {
    /// `worktree_path`, when the receipt names one and it still exists: the
    /// engine removes the worktree when its session ends
    /// (`candidate.py:143-177`). Nil for no receipt, an unreadable one, or no
    /// such key.
    public static func worktree(sessionDirectory: URL) -> URL? {
        guard let data = try? Data(contentsOf: sessionDirectory.appendingPathComponent("receipt.json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = object["worktree_path"] as? String, !path.isEmpty
        else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue
        else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
