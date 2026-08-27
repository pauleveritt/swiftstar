import SwiftUI

struct MainView: View {
    @State private var agentController = AgentController()
    @State private var metricsModel = MetricsModel()
    @State private var diagnosticsModel = DiagnosticsModel()

    var body: some View {
        TabView {
            AgentView(controller: agentController)
                .tabItem { Label("Agent", systemImage: "person.crop.circle") }
            MetricsView(model: metricsModel)
                .tabItem { Label("Metrics", systemImage: "gauge") }
            DiagnosticsView(model: diagnosticsModel)
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            PlaceholderView(title: "Help", phase: "P13")
                .tabItem { Label("Help", systemImage: "questionmark.circle") }
        }
        .frame(minWidth: 800, minHeight: 560)
        .onAppear {
            metricsModel.start(agentPid: agentController.runningPid)
            diagnosticsModel.start()
        }
        .onChange(of: agentController.runningPid) { _, newPid in
            metricsModel.start(agentPid: newPid)
        }
    }
}

struct PlaceholderView: View {
    let title: String
    let phase: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title).font(.title2)
            Text("\(title) arrives in \(phase).").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
