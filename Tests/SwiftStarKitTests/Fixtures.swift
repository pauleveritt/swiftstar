import Foundation
@testable import SwiftStarKit

/// The committed engine fixtures (`fixtures/engine/`), shared by every suite.
enum Fixtures {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/engine")

    /// Every line of a recorded `.ndjson` fixture, parsed in order.
    static func events(_ name: String) throws -> [EngineEvent] {
        let text = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
        var parser = EngineWireParser()
        return text.split(whereSeparator: \.isNewline).map { parser.parse(String($0)) }
    }

    /// A `models --json` fixture, decoded.
    static func modelList(_ name: String) throws -> EngineModelList {
        try EngineModelList.decode(Data(contentsOf: root.appendingPathComponent(name))).get()
    }
}
