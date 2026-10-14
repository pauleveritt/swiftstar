import Foundation

extension EngineController {
    /// The gallery app's controller (SU.12): the previews' running session,
    /// conversations and workspace. A fixture controller, so it never starts
    /// the engine, loads the catalog or reads the session lists.
    public static func gallery() -> EngineController { previewRunning }

    /// SU.3's leftover, in a real Debug run (SU.13): GPU metrics on and off,
    /// as the "GPU toggle" preview does, which once crashed SwiftUI's debug
    /// view storage. The gallery runs it when its `galleryFlipGPU` setting
    /// asks for a number of flips.
    public func galleryFlipGPU(times: Int) async {
        var showsGPU = true
        for _ in 0..<times {
            try? await Task.sleep(for: .milliseconds(100))
            showsGPU.toggle()
            replaceFixtureModel(Self.runningModel(withGPU: showsGPU))
        }
    }
}
