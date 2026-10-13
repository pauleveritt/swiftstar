import Foundation

/// One entry of `ds4-dogfood sessions --json` (SU.7a): a session directory.
public struct EngineSessionEntry: Decodable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let source: String?
    public let modelID: String?
    /// Local time, as the engine writes it; nil when missing or unreadable.
    public let updated: Date?
    public let prompts: Int?
    /// This directory's first prompt, not its conversation's: a resumed
    /// session starts its own count.
    public let firstPrompt: String?
    public let lastPrompt: String?
    /// The path of the session this one resumed from.
    public let resumedFrom: String?
    public let resumable: Bool?
    public let problems: [String]?

    public init(id: String, path: String, source: String? = nil, modelID: String? = nil, updated: Date? = nil,
                prompts: Int? = nil, firstPrompt: String? = nil, lastPrompt: String? = nil,
                resumedFrom: String? = nil, resumable: Bool? = nil, problems: [String]? = nil) {
        self.id = id
        self.path = path
        self.source = source
        self.modelID = modelID
        self.updated = updated
        self.prompts = prompts
        self.firstPrompt = firstPrompt
        self.lastPrompt = lastPrompt
        self.resumedFrom = resumedFrom
        self.resumable = resumable
        self.problems = problems
    }

    private enum CodingKeys: String, CodingKey {
        case id, path, source, prompts, updated, resumable, problems
        case modelID = "model_id", firstPrompt = "first_prompt", lastPrompt = "last_prompt"
        case resumedFrom = "resumed_from"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            path: try c.decode(String.self, forKey: .path),
            source: try? c.decodeIfPresent(String.self, forKey: .source),
            modelID: try? c.decodeIfPresent(String.self, forKey: .modelID),
            updated: (try? c.decodeIfPresent(String.self, forKey: .updated)).flatMap { $0.flatMap(Self.parseUpdated) },
            prompts: try? c.decodeIfPresent(Int.self, forKey: .prompts),
            firstPrompt: try? c.decodeIfPresent(String.self, forKey: .firstPrompt),
            lastPrompt: try? c.decodeIfPresent(String.self, forKey: .lastPrompt),
            resumedFrom: try? c.decodeIfPresent(String.self, forKey: .resumedFrom),
            resumable: try? c.decodeIfPresent(Bool.self, forKey: .resumable),
            problems: try? c.decodeIfPresent([String].self, forKey: .problems))
    }

    /// The engine's local `yyyy-MM-dd'T'HH:mm:ss`.
    public static func parseUpdated(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: s)
    }

    public static func decodeList(_ data: Data) -> Result<[EngineSessionEntry], CatalogError> {
        do { return .success(try JSONDecoder().decode([EngineSessionEntry].self, from: data)) }
        catch { return .failure(.malformed(String(describing: error).prefix(200).description)) }
    }

    /// `…/sessions/<id>/run-*.json` → `<id>`, the session directory's name.
    public static func directoryID(fromCapturePath path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return String(parts[parts.count - 2])
    }
}

/// A conversation: a chain of sessions linked by `resumed_from`, shown at
/// its newest session (SU.7a, D2).
public struct Conversation: Identifiable, Equatable, Sendable {
    /// The newest session's id: the resume target.
    public let id: String
    public let title: String
    public let updated: Date?
    public let modelID: String?
    public let resumable: Bool
    public let problems: [String]
    /// Every listed session in the chain, newest first.
    public let sessionIDs: [String]

    public init(id: String, title: String, updated: Date?, modelID: String?, resumable: Bool,
                problems: [String], sessionIDs: [String]) {
        self.id = id
        self.title = title
        self.updated = updated
        self.modelID = modelID
        self.resumable = resumable
        self.problems = problems
        self.sessionIDs = sessionIDs
    }
}

public enum Conversations {
    /// One row per chain head (an entry nothing listed resumed from), titled
    /// by the oldest listed entry's first prompt, newest first. A session
    /// that can't be resumed and has no prompt (a resume opened and left) is
    /// dropped first, so the session it resumed stays its chain's head and
    /// stays resumable.
    public static func group(_ all: [EngineSessionEntry]) -> [Conversation] {
        let entries = all.filter { $0.resumable != false || ($0.prompts ?? 0) > 0 }
        let byPath = Dictionary(entries.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        let parents = Set(entries.compactMap(\.resumedFrom))
        let rows = entries.filter { !parents.contains($0.path) }.map { head -> Conversation in
            var chain = [head]
            var seen: Set<String> = [head.path]
            while let from = chain.last?.resumedFrom, let parent = byPath[from], seen.insert(parent.path).inserted {
                chain.append(parent)
            }
            let title = [chain.last?.firstPrompt, head.firstPrompt]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "Untitled"
            return Conversation(
                id: head.id, title: title, updated: head.updated, modelID: head.modelID,
                resumable: head.resumable ?? false, problems: head.problems ?? [], sessionIDs: chain.map(\.id))
        }
        return rows.sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }
    }

    /// "12m ago · qwen3.8-27b"; either part alone when the other is missing.
    public static func subtitle(_ c: Conversation, now: Date, locale: Locale = .current) -> String {
        let when = c.updated.map { updated -> String in
            let f = RelativeDateTimeFormatter()
            f.locale = locale
            f.unitsStyle = .abbreviated
            return f.localizedString(for: updated, relativeTo: now)
        }
        return [when, c.modelID].compactMap { $0 }.joined(separator: " · ")
    }
}
