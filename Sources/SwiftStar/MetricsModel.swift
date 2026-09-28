import Observation
import SwiftStarKit

/// The inspector's view of the engine's latest measurements.
@MainActor
@Observable
final class MetricsModel {
    var state = EngineMetricsState()
}
