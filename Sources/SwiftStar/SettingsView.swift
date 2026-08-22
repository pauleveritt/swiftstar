import SwiftUI

struct SettingsView: View {
    @AppStorage("engineDir") private var engineDir = ""
    @AppStorage("modelPath") private var modelPath = ""
    @AppStorage("contextSize") private var contextSize = 32768
    @AppStorage("port") private var port = 0

    var body: some View {
        TabView {
            Form {
                TextField("Engine directory (DS4_DIR)", text: $engineDir)
                TextField("Model file", text: $modelPath)
                Stepper("Context size: \(contextSize)", value: $contextSize, in: 1024...262144, step: 1024)
                Stepper("Port (0 = auto): \(port)", value: $port, in: 0...65535, step: 1)
                Text("Settings apply when the engine next starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(width: 460)
            .tabItem { Label("Engine", systemImage: "gearshape") }
        }
        .frame(width: 480, height: 220)
    }
}
