import SwiftUI
import SwiftStarKit

struct MainView: View {
    let engine: EngineController
    @AppStorage(DefaultsKey.inspectorPresented.rawValue) private var inspectorPresented = false

    var body: some View {
        SessionView(controller: engine)
            .inspector(isPresented: $inspectorPresented) {
                InspectorView(engine: engine)
            }
            .frame(minWidth: 800, minHeight: 560)
    }
}
