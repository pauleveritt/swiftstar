import SwiftUI

struct MainView: View {
    @State private var agentController = AgentController()
    @State private var metricsModel = MetricsModel()
    @State private var diagnosticsModel = DiagnosticsModel()

    private enum Pane: String, CaseIterable, Identifiable {
        case agent, metrics, diagnostics

        var id: String { rawValue }

        var title: String {
            switch self {
            case .agent: "Agent"
            case .metrics: "Metrics"
            case .diagnostics: "Diagnostics"
            }
        }
        var systemImage: String {
            switch self {
            case .agent: "person.crop.circle"
            case .metrics: "gauge"
            case .diagnostics: "stethoscope"
            }
        }

        var group: PaneGroup {
            switch self {
            case .agent: .workspace
            case .metrics, .diagnostics: .observability
            }
        }
    }

    private enum PaneGroup: Equatable {
        case workspace, observability

        var title: String {
            switch self {
            case .workspace: "Workspace"
            case .observability: "Observability"
            }
        }

        var systemImage: String {
            switch self {
            case .workspace: "rectangle.3.group"
            case .observability: "waveform.path.ecg"
            }
        }
    }

    @State private var selection: Pane = .agent
    @AppStorage("appShellWorkspaceExpanded") private var workspaceExpanded = true
    @AppStorage("appShellObservabilityExpanded") private var observabilityExpanded = true
    // Lean-by-default: first launch shows only the detail column; the user's
    // choice persists across launches (P19.1 D1). `NavigationSplitViewVisibility`
    // is not Codable, so persist the raw string and map it through a Binding.
    @AppStorage("appShellColumnVisibility") private var columnVisibilityRaw = "detailOnly"

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: {
                switch columnVisibilityRaw {
                case "all": .all
                case "doubleColumn": .doubleColumn
                case "automatic": .automatic
                default: .detailOnly
                }
            },
            set: {
                columnVisibilityRaw = switch $0 {
                case .all: "all"
                case .doubleColumn: "doubleColumn"
                case .automatic: "automatic"
                default: "detailOnly"
                }
            }
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            List(selection: $selection) {
                sidebarGroup(.workspace, isExpanded: $workspaceExpanded)
                sidebarGroup(.observability, isExpanded: $observabilityExpanded)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            detailView
                .id(selection)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .animation(.snappy(duration: 0.28, extraBounce: 0.08), value: selection)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .frame(minWidth: 800, minHeight: 560)
        .onAppear {
            metricsModel.start(controller: agentController)
            metricsModel.setCollecting(selection == .metrics)
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
        .onChange(of: selection) { _, new in
            // Machine sampling is Metrics-only, and Diagnostics re-reads the
            // capture when the user actually looks at it.
            metricsModel.setCollecting(new == .metrics)
            if new == .diagnostics { diagnosticsModel.start(controller: agentController) }
        }
    }

    @ViewBuilder
    private func sidebarGroup(_ group: PaneGroup, isExpanded: Binding<Bool>) -> some View {
        Section(isExpanded: isExpanded) {
            ForEach(Pane.allCases.filter { $0.group == group }) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    Image(systemName: pane.systemImage)
                        .symbolEffect(.bounce, value: selection == pane)
                }
                .tag(pane)
            }
        } header: {
            Label(group.title, systemImage: group.systemImage)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .agent: AgentView(controller: agentController)
        case .metrics: MetricsView(model: metricsModel)
        case .diagnostics: DiagnosticsView(model: diagnosticsModel)
        }
    }
}
