import Foundation
import SwiftStarKit

/// The DeepSeek qualitative grader (P11 addendum D6, plan Task 4 Step 3a): a
/// pinned prompt (fixed rubric = spec + `mission.md` + `tech-stack.md`, plus the
/// generated code) sent to `deepseek/deepseek-chat` over OpenRouter, with a
/// timeout + one retry, parsed into a `GraderVerdict`. The grader never
/// fabricates a pass: a failed call or an unreadable response parses to
/// `.error`, not `.good`.
///
/// Live tier only — this performs a network call and is never part of CI or the
/// fast/integration test tiers.
enum DeepSeekGrader {
    static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    static let model = "deepseek/deepseek-chat"

    /// The pinned prompt: the rubric first, then the generated code, then the
    /// exact JSON contract. Kept in one place so the record can cite it.
    static func prompt(rubric: String, code: String) -> String {
        """
        You are a code reviewer grading an AI agent's implementation against a fixed rubric.

        RUBRIC (the spec, the mission, and the tech stack):
        \(rubric)

        GENERATED CODE (the agent's implementation):
        \(code)

        Does the implementation satisfy the rubric? Consider: does it use the
        required framework (FastAPI) and Jinja2 templates, does it implement every
        phase of the spec, and does it match the spec's user-visible behavior?

        Return ONLY a single JSON object (no markdown fences, no commentary) of the
        exact form:
        {"verdict":"good","reasons":["…","…"]}
        where "verdict" is "good" or "bad", and "reasons" is a list of short,
        specific strings naming what the code did right or wrong against the rubric.
        """
    }

    /// Run the grader: build the prompt, POST it to OpenRouter (one retry), parse
    /// the assistant's JSON content into a `GraderVerdict`. Any failure → `.error`.
    static func grade(rubric: String, code: String) -> GraderVerdict {
        guard let apiKey = apiKey() else {
            return GraderVerdict(verdict: .error, reasons: ["no OPENROUTER_API_KEY (or ~/.pi/agent/auth.json openrouter-curated key)"])
        }
        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "max_tokens": 2048,
            "messages": [
                ["role": "user", "content": prompt(rubric: rubric, code: code)]
            ],
        ]
        guard let raw = post(body: body, apiKey: apiKey) else {
            return GraderVerdict(verdict: .error, reasons: ["OpenRouter call failed (after retry)"])
        }
        return GraderVerdict.parse(raw)
    }

    // MARK: - plumbing

    /// `OPENROUTER_API_KEY` env wins; otherwise fall back to pi's auth store
    /// (`~/.pi/agent/auth.json`, the `openrouter-curated` credential), which is
    /// where this machine keeps the OpenRouter key.
    static func apiKey() -> String? {
        if let k = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !k.isEmpty {
            return k
        }
        let authPath = NSHomeDirectory() + "/.pi/agent/auth.json"
        guard let data = FileManager.default.contents(atPath: authPath),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let openRouter = obj["openrouter-curated"] as? [String: Any],
              let key = openRouter["key"] as? String, !key.isEmpty else {
            return nil
        }
        return key
    }

    /// POST the chat body; one retry on transport failure or non-2xx. Returns the
    /// assistant's raw text content, or nil on failure.
    static func post(body: [String: Any], apiKey: String) -> String? {
        for attempt in 0...1 {
            if attempt > 0 { sleep(2) }  // brief backoff before the single retry
            if let raw = postOnce(body: body, apiKey: apiKey) {
                return raw
            }
        }
        return nil
    }

    /// A small thread-safe box so the URLSession completion handler can hand its
    /// results back to the (synchronous) caller without Sendable-capture warnings.
    private final class ResponseBox: @unchecked Sendable {
        var data: Data?
        var status: Int = -1
    }

    static func postOnce(body: [String: Any], apiKey: String) -> String? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let box = ResponseBox()
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            box.data = data
            box.status = (response as? HTTPURLResponse)?.statusCode ?? -1
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 130)

        guard (200..<300).contains(box.status), let data = box.data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return nil
        }
        return content
    }
}
