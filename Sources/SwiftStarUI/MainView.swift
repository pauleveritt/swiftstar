import SwiftUI
import SwiftStarKit

public struct MainView: View {
    @AppStorage(DefaultsKey.inspectorPresented.rawValue) private var inspectorPresented = false

    public init() {}

    public var body: some View {
        SessionView()
            .inspector(isPresented: $inspectorPresented) {
                InspectorView()
            }
            .frame(minWidth: 800, minHeight: 560)
    }
}
