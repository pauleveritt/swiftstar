import Foundation

/// Folded wire-telemetry state. Ratcheted rates hold their last non-zero value
/// (the wire reports one rate at a time — a wire fact, so it lives here in the
/// model, not in a view).
public struct MetricsState: Equatable, Sendable {
    public var ctxUsed: Int?
    public var ctxSize: Int?
    public var prefillTPS: Double = 0
    public var genTPS: Double = 0
    public var memoryBudgetPlannedBytes: Int64?

    public init() {}
}

public struct MetricsReducer: Sendable {
    public init() {}

    public func reduce(_ state: inout MetricsState, _ event: WireEvent) {
        switch event {
        case .status(let s):
            // A status event whose ctx fields were zero-filled (absent on the
            // wire) must not blank the dial — one incomplete event would empty
            // the ring until the next complete one.
            if s.ctxUsed != 0 { state.ctxUsed = s.ctxUsed }
            if s.ctxSize != 0 { state.ctxSize = s.ctxSize }
            if s.prefillTPS != 0 { state.prefillTPS = s.prefillTPS }
            if s.genTPS != 0 { state.genTPS = s.genTPS }
        case .ready(let plannedBytes):
            state.memoryBudgetPlannedBytes = plannedBytes
        case .hello, .refused, .ignored:
            break
        }
    }
}
