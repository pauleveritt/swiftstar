import SwiftUI

struct MainView: View {
    let engine: EngineController
    @State private var metricsModel = MetricsModel()
    @AppStorage("appShellInspectorPresented") private var inspectorPresented = false

    var body: some View {
        AgentView(controller: engine)
            .inspector(isPresented: $inspectorPresented) {
                InspectorView(metricsModel: metricsModel)
            }
            .frame(minWidth: 800, minHeight: 560)
            .onChange(of: engine.metrics, initial: true) { _, metrics in
                metricsModel.state = metrics
            }
    }
}
