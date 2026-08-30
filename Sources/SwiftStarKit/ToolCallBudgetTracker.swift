/// Counts tool requests within one turn and admits only the requests covered
/// by that turn's tool-call budget.
///
/// The count is advanced for every emitted request, including the first
/// refused request. That makes the boundary explicit: a budget of `N` admits
/// requests 1 through `N` and refuses request `N + 1` and every later request.
/// The tracker is deliberately independent of wire I/O so product and
/// headless loops cannot drift in their admission timing.
public struct ToolCallBudgetTracker: Sendable {
    public static let defaultBudget = 64

    public let budget: Int
    public private(set) var callsSeen = 0

    public init(budget: Int) {
        self.budget = budget
    }

    /// Record one emitted request and report whether the host may execute it.
    @discardableResult
    public mutating func admit() -> Bool {
        callsSeen += 1
        return callsSeen <= budget
    }
}
