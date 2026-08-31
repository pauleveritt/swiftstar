import SwiftUI

struct MainView: View {
    @State private var agentController = AgentController()
    @State private var metricsModel = MetricsModel()
    @State private var diagnosticsModel = DiagnosticsModel()
    @State private var inspectorTab: InspectorTab = .metrics
    @AppStorage("appShellInspectorPresented") private var inspectorPresented = false

    var body: some View {
        AgentView(controller: agentController)
            .inspector(isPresented: $inspectorPresented) {
                InspectorView(
                    tab: $inspectorTab,
                    metricsModel: metricsModel,
                    diagnosticsModel: diagnosticsModel)
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        inspectorPresented.toggle()
                    } label: {
                        Label("Inspector", systemImage: "sidebar.trailing")
                    }
                    .help(inspectorPresented ? "Hide Inspector" : "Show Inspector")
                }
            }
            .frame(minWidth: 800, minHeight: 560)
            .onAppear {
                metricsModel.start(controller: agentController)
                updateMetricsCollection()
                diagnosticsModel.start(controller: agentController)
            }
            .onDisappear {
                metricsModel.stop()
            }
            .onChange(of: agentController.runningPid) { _, _ in
                // A new session = a new capture dir: re-point the live telemetry
                // and re-analyze the diagnostics against the fresh session.
                metricsModel.start(controller: agentController)
                diagnosticsModel.start(controller: agentController)
            }
            .onChange(of: agentController.completedTurns) { _, _ in
                // The capture only becomes analyzable once a turn has been written
                // to it; the pid change alone fires while the wire is still empty.
                diagnosticsModel.start(controller: agentController)
            }
            .onChange(of: inspectorTab) { _, _ in
                updateMetricsCollection()
                if inspectorTab == .diagnostics { diagnosticsModel.start(controller: agentController) }
            }
            .onChange(of: inspectorPresented) { _, _ in
                updateMetricsCollection()
            }
    }

    private func updateMetricsCollection() {
        metricsModel.setCollecting(inspectorPresented && inspectorTab == .metrics)
    }
}
