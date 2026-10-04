import SwiftUI
import SwiftStarKit

struct MainView: View {
    @AppStorage(DefaultsKey.inspectorPresented.rawValue) private var inspectorPresented = false

    var body: some View {
        SessionView()
            .inspector(isPresented: $inspectorPresented) {
                InspectorView()
            }
            .frame(minWidth: 800, minHeight: 560)
    }
}
