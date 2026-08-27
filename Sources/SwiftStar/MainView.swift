import SwiftUI

struct MainView: View {
    @State private var agentController = AgentController()
    @State private var metricsModel = MetricsModel()
    @State private var diagnosticsModel = DiagnosticsModel()

    private enum Section: String, CaseIterable, Identifiable {
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
    }

    @State private var selection: Section = .agent
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
            List(Section.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            switch selection {
            case .agent: AgentView(controller: agentController)
            case .metrics: MetricsView(model: metricsModel)
            case .diagnostics: DiagnosticsView(model: diagnosticsModel)
            }
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
}
